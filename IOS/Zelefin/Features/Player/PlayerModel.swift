import AVFoundation
import AVKit
import Combine
import Observation
import UIKit

/// A client-side sleep timer: pause after a fixed duration, or stop when the
/// current item finishes. Portable — no server involvement.
enum SleepTimerMode: Equatable, Hashable, Sendable {
    case off
    case minutes(Int)
    case endOfEpisode
}

@MainActor
@Observable
final class PlayerModel {
    let plan: PlaybackPlan
    let pipeline: PlaybackPipeline
    private(set) var player: AVPlayer?
    private(set) var engine: DirectPlayEngine?
    private(set) var mpv: MPVPlayback?
    private(set) var errorMessage: String?
    private(set) var hasFirstFrame = false
    private(set) var isPaused = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var playbackRate: Float = 1
    private(set) var audioOptions: [PlaybackTrackOption] = []
    private(set) var subtitleOptions: [PlaybackTrackOption] = []
    private(set) var subtitleCues: [DirectPlaySubtitleCue] = []
    private(set) var pictureSize: CGSize = .zero
    private(set) var canUsePictureInPicture = false
    var isPictureInPictureActive: Bool {
        pictureInPicture.isActive || nativePictureInPictureActive
    }
    private(set) var fillsScreen = false
    private(set) var showsPlaybackStats = false
    private(set) var playbackStats = PlaybackStatsSnapshot(sections: [])
    private(set) var sleepTimer: SleepTimerMode = .off
    /// Seconds left on a timed sleep timer, for the countdown label. Nil when the
    /// timer is off or set to end-of-episode.
    private(set) var sleepTimerRemaining: TimeInterval?
    private var sleepTimerTask: Task<Void, Never>?
    /// Prefetch/retained window from the engine. The overlay only sees `subtitleCues` after a playhead filter.
    private var retainedSubtitleCues: [DirectPlaySubtitleCue] = []

    var selectedAudioID: Int?
    var selectedSubtitleID: Int?
    /// What Jellyfin chose for this user's settings; applied once the engine lists its tracks.
    private let serverAudioID: Int?
    private let serverSubtitleID: Int?
    private var startedOnServerAudio = false
    /// Jellyfin's audio pick, held until the first frame so the switch never reloads mid-startup.
    private var pendingServerAudioID: Int?
    private var startedOnServerSubtitle = false
    var isFinished = false
    var skipSegments: [SkipSegment] = []
    var skipPrompt: SkipSegment?

    private let reporter: (any PlaybackReporting)?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cancellables: Set<AnyCancellable> = []
    private var pendingDirectPlaySeek: TimeInterval?
    private var isDrainingDirectPlaySeeks = false
    private var acceptsDirectPlaySeeks = true
    private var playheadIsTrusted = true
    private var lastTrustedTime: TimeInterval = 0
    private var engineIsBuffering = false
    private var readerIsStalled = false
    private var networkReader: JellyfinByteRangeReader?
    private var stallWatchTask: Task<Void, Never>?
    private var engineIsSeeking = false
    private var isSurfaceBound = false
    private var didStart = false
    private var didAttemptDeferredResume = false
    private var isRestoringForeground = false
    private var nativePictureInPictureActive = false
    private var stopWhenPictureInPictureEnds = false
    /// Bumped after background return so SwiftUI detaches and reattaches the layer.
    private(set) var surfaceGeneration = 0
    private let pictureInPicture = DirectPlayPictureInPicture()

    init(plan: PlaybackPlan, reporter: (any PlaybackReporting)?) {
        self.plan = plan
        self.reporter = reporter
        self.pipeline = PlaybackPipelineResolver.pipeline(for: plan)
        self.serverAudioID = plan.audioTracks.first(where: \.isSelected)?.id
        self.serverSubtitleID = plan.subtitleTracks.first(where: \.isSelected)?.id
        self.selectedAudioID = serverAudioID ?? plan.audioTracks.first?.id
        self.selectedSubtitleID = serverSubtitleID
        self.duration = plan.item.runtime ?? 0
        self.audioOptions = plan.audioTracks.map(PlaybackTrackOption.init)
        self.subtitleOptions = plan.subtitleTracks.map(PlaybackTrackOption.init)
        self.playbackRate = PlaybackPreferences.defaultRate

        switch pipeline {
        case .appleNative:
            player = Self.makeNativePlayer(url: plan.streamURL, extraHeaders: plan.extraHTTPHeaders)
        case .directDecode:
            do {
                let created = try DirectPlayEngine()
                created.ownsVideoNowPlayingSession = false
                created.deactivatesAudioSessionOnStop = true
                created.setExternalMetadata(nowPlayingMetadata())
                engine = created
                observeEngine(created)
            } catch {
                errorMessage = error.localizedDescription
            }
        case .mpv:
            do {
                let created = try MPVPlayback()
                mpv = created
                observeMPV(created)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func start() async {
        do {
            switch pipeline {
            case .appleNative:
                await PlaybackAudioSession.activate()
                await seekNativeToResumeIfNeeded()
                player?.play()
                setPlaybackRate(PlaybackPreferences.defaultRate)
                observeNativeTime()
                observeNativeEnd()
                hasFirstFrame = true
            case .directDecode:
                try Task.checkCancellation()
                await PlaybackAudioSession.activate()
                await waitUntilSurfaceReady()
                try Task.checkCancellation()
                try await startDirectPlay()
                setPlaybackRate(PlaybackPreferences.defaultRate)
            case .mpv:
                try Task.checkCancellation()
                await PlaybackAudioSession.activate()
                await waitUntilSurfaceReady()
                try Task.checkCancellation()
                startMPV()
                setPlaybackRate(PlaybackPreferences.defaultRate)
            }
            await reportPlaybackStarted()
            didStart = true
            onDidStart?()
            RemoteControlHub.shared.attach(self)
        } catch is CancellationError {
            await stop()
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        cancellables.removeAll()
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        stallWatchTask?.cancel()
        stallWatchTask = nil
        networkReader = nil
        readerIsStalled = false
        retainedSubtitleCues = []
        subtitleCues = []

        let seconds = reportedSeconds
        acceptsDirectPlaySeeks = false
        pendingDirectPlaySeek = nil
        player?.pause()
        engine?.stop()
        mpv?.stop()
        didStart = false
        nativePictureInPictureActive = false
        stopWhenPictureInPictureEnds = false
        RemoteControlHub.shared.detach(self)
        await reportPlaybackStopped(at: seconds)
    }

    private func reportPlaybackStarted() async {
        guard let reporter else { return }
        await reporter.started(
            at: PlaybackResumePolicy.reportStartPosition(
                playhead: currentSeconds,
                plannedStart: plan.startTime
            )
        )
    }

    private func reportPlaybackStopped(at seconds: TimeInterval) async {
        guard let reporter else { return }
        await reporter.stopped(at: seconds)
    }

    private func reportProgress(at seconds: TimeInterval? = nil, isPaused: Bool) async {
        guard let reporter else { return }
        await reporter.progress(at: seconds ?? currentSeconds, isPaused: isPaused)
    }

    func markPlaybackViewDismissed() {
        if PlaybackPictureInPicturePolicy.shouldStopOnViewDismiss(
            pictureInPictureActive: isPictureInPictureActive
        ) {
            Task { await stop() }
            return
        }
        stopWhenPictureInPictureEnds = true
    }

    func setNativePictureInPictureActive(_ active: Bool) {
        nativePictureInPictureActive = active
        handlePictureInPictureActiveChange(active)
    }

    func syncPictureInPicture() {
        pictureInPicture.syncController()
        canUsePictureInPicture = pictureInPicture.canStart
    }

    /// Aether drops video packets while backgrounded and does not reattach a
    /// failed `AVSampleBufferDisplayLayer`. Rebuild at the playhead, then force
    /// SwiftUI to bind a fresh surface.
    func restoreAfterForeground() async {
        guard didStart, !isRestoringForeground else { return }
        if isPictureInPictureActive { return }
        isRestoringForeground = true
        defer { isRestoringForeground = false }

        if let mpv {
            // A display layer iOS invalidated in the background stays black until flushed.
            if mpv.displayLayer.status == .failed {
                mpv.displayLayer.flush()
            }
            return
        }

        if let engine {
            let resume = !isPaused
            do {
                try await Task.sleep(nanoseconds: PlaybackForegroundRecovery.settleNanoseconds)
                try Task.checkCancellation()
                guard self.engine === engine else { return }
                try await engine.reloadAtCurrentPosition()
                surfaceGeneration += 1
                syncPictureInPicture()
                if resume {
                    engine.play()
                }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        if player != nil {
            surfaceGeneration += 1
            if !isPaused {
                player?.play()
            }
        }
    }

    var onUserTransport: ((RemotePlaybackAction) -> Void)?
    var onDidStart: (() -> Void)?
    var onRemoteSeekApplied: ((TimeInterval) -> Void)?
    @ObservationIgnored private var isApplyingRemote = false

    func togglePlayPause() {
        let pause = !isPaused
        if let engine {
            engine.togglePlayPause()
        } else if let mpv {
            if pause { mpv.pause() } else { mpv.play() }
        } else {
            guard let player else { return }
            if player.rate == 0 {
                player.play()
            } else {
                player.pause()
            }
        }
        notifyUserTransport(pause ? .pause : .play)
    }

    func applyRemote(_ action: RemotePlaybackAction) {
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        switch action {
        case .playPause:
            togglePlayPause()
        case .pause:
            pausePlayback()
        case .play:
            resumePlayback()
        case .seek(let time):
            seek(to: time)
            onRemoteSeekApplied?(time)
        case .skip(let interval):
            skip(by: interval)
        case .previous:
            skip(by: -30)
        case .mute:
            setMuted(true)
        case .unmute:
            setMuted(false)
        case .volumeUp:
            adjustVolume(by: 0.1)
        case .volumeDown:
            adjustVolume(by: -0.1)
        case .stop, .next:
            break
        }
        Task { await reportProgress(isPaused: isPaused) }
    }

    private func pausePlayback() {
        if let engine {
            if !isPaused { engine.togglePlayPause() }
            return
        }
        if let mpv {
            mpv.pause()
            return
        }
        player?.pause()
        isPaused = true
    }

    private func resumePlayback() {
        if let engine {
            if isPaused { engine.togglePlayPause() }
            return
        }
        if let mpv {
            mpv.play()
            return
        }
        player?.play()
        setPlaybackRate(playbackRate)
        isPaused = false
    }

    private func setMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    private func adjustVolume(by delta: Float) {
        guard let player else { return }
        player.volume = min(1, max(0, player.volume + delta))
        if delta > 0 { player.isMuted = false }
    }

    func skipCurrentSegment() {
        guard let skipPrompt else { return }
        seek(to: skipPrompt.seekTime)
    }

    private func applySkipPrompt(at seconds: TimeInterval) {
        let prompt = SkipSegment.prompt(in: skipSegments, at: seconds)
        if skipPrompt != prompt {
            skipPrompt = prompt
        }
        guard let prompt, PlaybackPreferences.shouldAutoSkip(prompt.kind) else { return }
        skipCurrentSegment()
    }

    func skip(by interval: TimeInterval) {
        seek(to: currentTime + interval)
    }

    func seek(to seconds: TimeInterval) {
        let upper = duration > 0 ? duration : seconds
        let clamped = min(max(0, seconds), upper)
        currentTime = clamped
        if engine != nil {
            enqueueDirectPlaySeek(clamped)
        } else if let mpv {
            mpv.seek(to: clamped)
        } else if let player {
            let time = CMTime(seconds: clamped, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        skipPrompt = SkipSegment.prompt(in: skipSegments, at: clamped + 0.05)
        notifyUserTransport(.seek(clamped))
    }

    private func notifyUserTransport(_ action: RemotePlaybackAction) {
        guard !isApplyingRemote else { return }
        onUserTransport?(action)
    }

    private func enqueueDirectPlaySeek(_ seconds: TimeInterval) {
        guard acceptsDirectPlaySeeks else { return }
        playheadIsTrusted = false
        let startDrain = DirectPlaySeekCoalesce.enqueue(
            pending: &pendingDirectPlaySeek,
            latest: seconds,
            isDraining: isDrainingDirectPlaySeeks
        )
        guard startDrain else { return }
        isDrainingDirectPlaySeeks = true
        Task { await drainDirectPlaySeeks() }
    }

    private func drainDirectPlaySeeks() async {
        while acceptsDirectPlaySeeks, engine != nil {
            let target = pendingDirectPlaySeek
            pendingDirectPlaySeek = nil
            guard let target else {
                isDrainingDirectPlaySeeks = false
                if acceptsDirectPlaySeeks, pendingDirectPlaySeek != nil {
                    isDrainingDirectPlaySeeks = true
                    continue
                }
                return
            }
            if let engine {
                await engine.seek(to: target)
            }
        }
        pendingDirectPlaySeek = nil
        isDrainingDirectPlaySeeks = false
    }

    private func handleDirectPlaySeekEvent(_ event: DirectPlaySeekEvent) {
        playheadIsTrusted = DirectPlayProgressPolicy.playheadTrusted(after: event.outcome)
        switch event.outcome {
        case .began, .superseded:
            publishWaitState()
        case .landed(let rendered):
            lastTrustedTime = rendered
            currentTime = rendered
            publishWaitState()
            Task { await reportProgress(at: rendered, isPaused: isPaused) }
        case .rejected, .stalled:
            // A stalled seek jumps the clock and can leave video waiting on a PTS
            // that never arrives (black frame + audio from the wrong place). Keep
            // the last on-screen time instead of reopening at the failed target.
            currentTime = lastTrustedTime
            publishWaitState()
        }
    }

    private func publishWaitState() {
        let waiting = engineIsBuffering || engineIsSeeking || readerIsStalled
        if isBuffering != waiting {
            isBuffering = waiting
        }
    }

    var isSeeking: Bool { engineIsSeeking }

    var isRebuffering: Bool {
        hasFirstFrame && !isPaused && !engineIsSeeking && isBuffering
    }

    var bufferedAheadSeconds: TimeInterval {
        if let engine {
            return PlaybackStats.bufferedAhead(ranges: engine.residentRanges, playhead: currentTime)
        }
        if let player, let item = player.currentItem {
            let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }.map {
                ClosedRange(uncheckedBounds: ($0.start.seconds, $0.end.seconds))
            }
            return PlaybackStats.bufferedAhead(ranges: ranges, playhead: currentTime)
        }
        return 0
    }

    private func applyPendingServerAudio() {
        guard hasFirstFrame, let id = pendingServerAudioID, let engine else { return }
        pendingServerAudioID = nil
        engine.selectAudioTrack(index: id)
    }

    func selectAudio(id: Int) {
        pendingServerAudioID = nil
        selectedAudioID = id
        engine?.selectAudioTrack(index: id)
        mpv?.selectAudio(id)
    }

    func selectSubtitle(id: Int?) {
        selectedSubtitleID = id
        applySubtitleSelection(id)
    }

    func applySubtitleAppearance() {
        player?.currentItem?.textStyleRules = SubtitleAppearance.textStyleRules()
        publishVisibleSubtitleCues(at: currentSeconds)
    }

    private func applySubtitleSelection(_ id: Int?) {
        if let mpv {
            mpv.selectSubtitle(id)
            return
        }
        guard let engine else { return }
        if let id {
            let resolved = PlaybackSubtitleSelection.engineIndex(
                requested: id,
                planTracks: plan.subtitleTracks,
                engineTracks: engine.subtitleTracks
            )
            if let resolved {
                if selectedSubtitleID != resolved {
                    selectedSubtitleID = resolved
                }
                if engine.activeSubtitleTrackIndex != resolved {
                    engine.selectSubtitleTrack(index: resolved)
                }
            }
        } else {
            engine.clearSubtitle()
        }
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        engine?.setRate(rate)
        mpv?.setRate(rate)
        if let player {
            player.rate = player.rate == 0 ? 0 : rate
        }
    }

    func togglePictureInPicture() {
        pictureInPicture.toggle()
    }

    func toggleFillScreen() {
        fillsScreen.toggle()
        applyFillScreen()
        refreshPlaybackStats()
    }

    func togglePlaybackStats() {
        showsPlaybackStats.toggle()
        if showsPlaybackStats {
            refreshPlaybackStats()
        }
    }

    /// True when playback should stop (not auto-advance) once the current item ends.
    var sleepAtEndOfEpisode: Bool { sleepTimer == .endOfEpisode }

    func setSleepTimer(_ mode: SleepTimerMode) {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemaining = nil
        sleepTimer = mode
        guard case let .minutes(minutes) = mode, minutes > 0 else { return }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerRemaining = deadline.timeIntervalSinceNow
        sleepTimerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let remaining = deadline.timeIntervalSinceNow
                self?.sleepTimerRemaining = max(0, remaining)
                if remaining <= 0 { break }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.fireSleepTimer()
        }
    }

    private func fireSleepTimer() {
        sleepTimer = .off
        sleepTimerRemaining = nil
        sleepTimerTask = nil
        if !isPaused {
            pausePlayback()
        }
    }

    func noteSurfaceReady() {
        isSurfaceBound = true
    }

    private func waitUntilSurfaceReady() async {
        let deadline = Date().addingTimeInterval(DirectPlaySurfaceGate.waitBudget)
        while !isSurfaceBound, Date() < deadline {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: DirectPlaySurfaceGate.pollNanoseconds)
        }
    }

    private func seekNativeToResumeIfNeeded() async {
        guard let player,
              let resume = PlaybackResumePolicy.clientStartPosition(
                method: plan.method,
                startTime: plan.startTime,
                clientOwnsPlayhead: plan.clientOwnsPlayhead
              )
        else { return }
        let time = CMTime(seconds: resume, preferredTimescale: 600)
        _ = await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = resume
        lastTrustedTime = resume
    }

    private var resumeStartPosition: TimeInterval? {
        PlaybackResumePolicy.clientStartPosition(
            method: plan.method,
            startTime: plan.startTime,
            clientOwnsPlayhead: plan.clientOwnsPlayhead
        )
    }

    private func noteResumePlayhead() {
        guard let resume = resumeStartPosition else { return }
        currentTime = resume
        lastTrustedTime = resume
    }

    private func finishDeferredResumeIfNeeded() {
        guard !didAttemptDeferredResume else { return }
        let playhead = engine?.clock.currentTime ?? currentTime
        let trustedPlayhead = playhead.isFinite ? playhead : currentTime
        guard PlaybackResumePolicy.needsDeferredSeek(
            method: plan.method,
            playhead: trustedPlayhead,
            plannedStart: plan.startTime,
            clientOwnsPlayhead: plan.clientOwnsPlayhead
        ) else { return }
        didAttemptDeferredResume = true
        let target = plan.startTime
        Task { seek(to: target) }
    }

    private func startDirectPlay() async throws {
        guard let created = engine else {
            throw ZelefinError.playbackEngineUnavailable
        }

        let url = plan.streamURL
        var headers = PlaybackHTTPHeaders.fields(for: url)
        for (name, value) in plan.extraHTTPHeaders {
            headers[name] = value
        }
        let options = DirectPlayLoadOptions.make(for: plan)
        try Task.checkCancellation()
        if url.isFileURL {
            guard let reader = LocalMediaByteReader(url: url) else {
                throw ZelefinError.offlineFileUnreadable
            }
            var fileOptions = options
            fileOptions.httpHeaders = [:]
            try await created.load(
                source: .custom(reader, formatHint: StreamContainer.formatHint(from: url)),
                startPosition: resumeStartPosition,
                options: fileOptions
            )
        } else if DirectPlayLoadPolicy.shouldOpenAsHTTPURL(
            method: plan.method,
            isHLS: PlaybackPipelineResolver.isHLS(url),
            isLive: plan.isLive,
            hasKnownSize: plan.byteSize != nil
        ) {
            try await created.load(
                source: .url(url),
                startPosition: resumeStartPosition,
                options: options
            )
        } else {
            let knownSize = plan.byteSize
            let reader = try await Task.detached {
                guard let reader = JellyfinByteRangeReader(
                    url: url,
                    headers: headers,
                    knownSize: knownSize
                ) else {
                    throw ZelefinError.byteRangeUnsupported
                }
                return reader
            }.value
            try Task.checkCancellation()
            // Custom IO has no filename. A forced libavformat name that does not match the
            // bytes makes the probe miss the video stream; Aether then plays audio only.
            try await created.load(
                source: .custom(reader, formatHint: nil),
                startPosition: resumeStartPosition,
                options: options
            )
            if DirectPlayLoadPolicy.shouldReloadAsURL(
                isAudioOnlyBackend: created.playbackBackend == .audio,
                expectsVideo: true
            ) {
                try await created.load(
                    source: .url(url),
                    startPosition: resumeStartPosition,
                    options: options
                )
            } else {
                watchForReaderStalls(reader)
            }
        }
        noteResumePlayhead()
        hasFirstFrame = created.hasFirstFrameReadyForDisplay
        updatePictureSize(from: created)
        syncPictureInPicture()
        finishDeferredResumeIfNeeded()
    }

    /// Polls the Direct Play reader so a dead link reads as rebuffering: the spinner shows and the
    /// live adaptive monitor steps down to a transcode instead of leaving a silent frozen picture.
    private func watchForReaderStalls(_ reader: JellyfinByteRangeReader) {
        networkReader = reader
        stallWatchTask?.cancel()
        stallWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, let reader = self.networkReader else { return }
                let stalled = self.hasFirstFrame && !self.isPaused && !self.engineIsSeeking
                    && ReaderStallPolicy.isStalled(
                        secondsWithoutProgress: reader.secondsWithoutProgress,
                        bufferedAhead: self.bufferedAheadSeconds
                    )
                guard stalled != self.readerIsStalled else { continue }
                self.readerIsStalled = stalled
                self.publishWaitState()
            }
        }
    }

    private func observeEngine(_ engine: DirectPlayEngine) {
        engine.$hasFirstFrameReadyForDisplay
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ready in
                Task { @MainActor in
                    guard let self, ready else { return }
                    self.hasFirstFrame = true
                    self.applyPendingServerAudio()
                    if let engine = self.engine {
                        self.updatePictureSize(from: engine)
                    }
                    self.syncPictureInPicture()
                    self.finishDeferredResumeIfNeeded()
                }
            }
            .store(in: &cancellables)

        engine.$isBuffering
            .receive(on: DispatchQueue.main)
            .sink { [weak self] buffering in
                Task { @MainActor in
                    guard let self else { return }
                    self.engineIsBuffering = buffering
                    self.publishWaitState()
                }
            }
            .store(in: &cancellables)

        engine.$isSeeking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seeking in
                Task { @MainActor in
                    guard let self else { return }
                    self.engineIsSeeking = seeking
                    self.publishWaitState()
                }
            }
            .store(in: &cancellables)

        engine.seekEvents
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleDirectPlaySeekEvent(event)
                }
            }
            .store(in: &cancellables)

        engine.$duration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                Task { @MainActor in
                    guard let self, seconds.isFinite, seconds > 0 else { return }
                    self.duration = seconds
                }
            }
            .store(in: &cancellables)

        engine.$audioTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                Task { @MainActor in
                    guard let self, !tracks.isEmpty else { return }
                    let options = tracks.map(PlaybackTrackOption.init)
                    if self.audioOptions != options {
                        self.audioOptions = options
                    }
                    // Move to the stream Jellyfin chose only for another language, and only once the
                    // first load has finished; see `StartingAudioPolicy`.
                    if !self.startedOnServerAudio {
                        self.startedOnServerAudio = true
                        if let wanted = self.serverAudioID,
                           let target = tracks.first(where: { $0.id == wanted }),
                           engine.activeAudioTrackIndex != wanted,
                           StartingAudioPolicy.shouldSwitch(
                               engineLanguage: tracks.first(where: { $0.id == engine.activeAudioTrackIndex })?.language,
                               serverLanguage: target.language
                           ) {
                            self.pendingServerAudioID = wanted
                            self.applyPendingServerAudio()
                        }
                    }
                }
            }
            .store(in: &cancellables)

        engine.$subtitleTracks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] tracks in
                Task { @MainActor in
                    guard let self, !tracks.isEmpty else { return }
                    let options = tracks.map(PlaybackTrackOption.init)
                    if self.subtitleOptions != options {
                        self.subtitleOptions = options
                    }
                    if !self.startedOnServerSubtitle {
                        self.startedOnServerSubtitle = true
                        // The server resolved the user's subtitle mode to none, so a default-flagged
                        // track in the file must not come up on its own.
                        if self.serverSubtitleID == nil {
                            self.selectedSubtitleID = nil
                            engine.clearSubtitle()
                            return
                        }
                    }
                    if let wanted = self.selectedSubtitleID {
                        self.applySubtitleSelection(wanted)
                    }
                }
            }
            .store(in: &cancellables)

        engine.$activeAudioTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                Task { @MainActor in
                    if let index, self?.selectedAudioID != index {
                        self?.selectedAudioID = index
                    }
                }
            }
            .store(in: &cancellables)

        engine.$activeSubtitleTrackIndex
            .receive(on: DispatchQueue.main)
            .sink { [weak self] index in
                Task { @MainActor in
                    if let index, self?.selectedSubtitleID != index {
                        self?.selectedSubtitleID = index
                    }
                }
            }
            .store(in: &cancellables)

        engine.$subtitleCues
            .receive(on: DispatchQueue.main)
            .sink { [weak self] cues in
                Task { @MainActor in
                    self?.replaceRetainedSubtitleCues(cues)
                }
            }
            .store(in: &cancellables)

        engine.$softwareDisplaySize
            .receive(on: DispatchQueue.main)
            .sink { [weak self] size in
                Task { @MainActor in
                    guard let self, let size, size.width > 0, size.height > 0 else { return }
                    self.pictureSize = size
                }
            }
            .store(in: &cancellables)

        engine.$softwarePiPSource
            .receive(on: DispatchQueue.main)
            .sink { [weak self] source in
                Task { @MainActor in
                    self?.attachPictureInPicture(source)
                }
            }
            .store(in: &cancellables)

        engine.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                Task { @MainActor in
                    if case .paused = state {
                        self?.isPaused = true
                    } else if case .playing = state {
                        self?.isPaused = false
                    }
                    if case .ended = state, let self, self.plan.isLive != true {
                        // A slow first load can hit end-of-stream before any frame. That is a
                        // failed start, not the end of the title, and must not close the player.
                        if self.hasFirstFrame {
                            self.isFinished = true
                        } else {
                            self.errorMessage = "The server stopped sending video before playback started."
                        }
                    }
                    if case .error(let message) = state {
                        self?.errorMessage = message
                    }
                }
            }
            .store(in: &cancellables)

        engine.clock.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] seconds in
                Task { @MainActor in
                    guard let self, seconds.isFinite else { return }
                    self.applySkipPrompt(at: seconds)
                    guard DirectPlayProgressPolicy.shouldReport(playheadTrusted: self.playheadIsTrusted) else {
                        self.publishVisibleSubtitleCues(at: self.currentTime)
                        if self.showsPlaybackStats {
                            self.refreshPlaybackStats()
                        }
                        return
                    }
                    if abs(self.currentTime - seconds) > 0.04 {
                        self.currentTime = seconds
                    }
                    self.lastTrustedTime = seconds
                    self.publishVisibleSubtitleCues(at: seconds)
                    if self.showsPlaybackStats {
                        self.refreshPlaybackStats()
                    }
                    let isPaused: Bool
                    if let engine = self.engine, case .paused = engine.state {
                        isPaused = true
                    } else {
                        isPaused = false
                    }
                    await self.reportProgress(at: seconds, isPaused: isPaused)
                }
            }
            .store(in: &cancellables)
    }

    private func startMPV() {
        guard let mpv else { return }
        var headers = PlaybackHTTPHeaders.fields(for: plan.streamURL)
        for (name, value) in plan.extraHTTPHeaders {
            headers[name] = value
        }
        mpv.load(.init(
            url: plan.streamURL,
            headers: plan.streamURL.isFileURL ? [:] : headers,
            startPosition: resumeStartPosition,
            externalSubtitles: plan.externalSubtitles
        ))
        noteResumePlayhead()
        applyFillScreen()
    }

    private func observeMPV(_ mpv: MPVPlayback) {
        mpv.onEvent = { [weak self] event in
            self?.handleMPV(event)
        }
    }

    private func handleMPV(_ event: MPVPlayback.Event) {
        switch event {
        case .time(let seconds):
            currentTime = seconds
            lastTrustedTime = seconds
            applySkipPrompt(at: seconds)
            if showsPlaybackStats {
                refreshPlaybackStats()
            }
            Task { await reportProgress(at: seconds, isPaused: isPaused) }
        case .duration(let seconds):
            duration = seconds
        case .paused(let paused):
            isPaused = paused
        case .buffering(let buffering):
            engineIsBuffering = buffering
            publishWaitState()
        case .firstFrame:
            hasFirstFrame = true
        case .tracks(let tracks):
            applyMPVTracks(tracks)
        case .audioSelected(let id):
            if let id, selectedAudioID != id { selectedAudioID = id }
        case .subtitleSelected(let id):
            if selectedSubtitleID != id { selectedSubtitleID = id }
        case .videoSize(let size):
            pictureSize = size
        case .ended:
            guard plan.isLive != true else { return }
            if hasFirstFrame {
                isFinished = true
            } else {
                errorMessage = "The server stopped sending video before playback started."
            }
        case .failed(let message):
            errorMessage = message
        }
    }

    /// The menus list mpv's own tracks, so every track in the file is choosable. Jellyfin's picks are
    /// applied once: audio as soon as tracks appear, subtitles after the sidecar files have joined.
    private func applyMPVTracks(_ tracks: [MPVPlayback.Track]) {
        guard let mpv else { return }
        let audio = tracks.filter { $0.kind == .audio }
        let subtitles = tracks.filter { $0.kind == .subtitle }
        let audioMenu = audio.map { PlaybackTrackOption(id: $0.id, title: MPVTrackMatch.title(for: $0)) }
        let subtitleMenu = subtitles.map { PlaybackTrackOption(id: $0.id, title: MPVTrackMatch.title(for: $0)) }
        if audioOptions != audioMenu { audioOptions = audioMenu }
        if subtitleOptions != subtitleMenu { subtitleOptions = subtitleMenu }

        if !startedOnServerAudio, !audio.isEmpty {
            startedOnServerAudio = true
            let planned = plan.audioTracks.first(where: \.isSelected)
            if let target = MPVTrackMatch.track(for: serverAudioID, language: planned?.language, in: tracks, kind: .audio) {
                selectedAudioID = target.id
                mpv.selectAudio(target.id)
            }
        }

        let externalCount = subtitles.filter(\.isExternal).count
        if !startedOnServerSubtitle, externalCount >= plan.externalSubtitles.count {
            startedOnServerSubtitle = true
            guard serverSubtitleID != nil else {
                selectedSubtitleID = nil
                mpv.selectSubtitle(nil)
                return
            }
            let planned = plan.subtitleTracks.first(where: \.isSelected)
            let target = MPVTrackMatch.track(for: serverSubtitleID, language: planned?.language, in: tracks, kind: .subtitle)
            selectedSubtitleID = target?.id
            mpv.selectSubtitle(target?.id)
        }
    }

    private func observeNativeTime() {
        guard let player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor in
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                self.applySkipPrompt(at: seconds)
                self.currentTime = seconds
                if let player = self.player {
                    self.isPaused = player.rate == 0
                    let waiting = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                        && player.reasonForWaitingToPlay == .toMinimizeStalls
                    if self.isBuffering != waiting {
                        self.isBuffering = waiting
                    }
                }
                await self.reportProgress(at: seconds, isPaused: self.isPaused)
            }
        }
    }

    private func observeNativeEnd() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player?.currentItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard self?.plan.isLive != true else { return }
                self?.isFinished = true
            }
        }
    }

    private var currentSeconds: TimeInterval {
        if mpv != nil {
            return currentTime
        }
        if let engine {
            let seconds = engine.clock.currentTime
            return seconds.isFinite ? seconds : 0
        }
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private var reportedSeconds: TimeInterval {
        DirectPlayProgressPolicy.shouldReport(playheadTrusted: playheadIsTrusted)
            ? currentSeconds
            : lastTrustedTime
    }

    private func replaceRetainedSubtitleCues(_ cues: [DirectPlaySubtitleCue]) {
        retainedSubtitleCues = cues
        publishVisibleSubtitleCues(at: currentSeconds)
    }

    private func publishVisibleSubtitleCues(at seconds: TimeInterval) {
        let visible = DirectPlayPictureLayout.visibleCues(
            in: retainedSubtitleCues,
            at: seconds - SubtitleAppearance.syncSeconds
        )
        if visible != subtitleCues {
            subtitleCues = visible
        }
    }

    private func nowPlayingMetadata() -> [AVMetadataItem] {
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle
        title.value = plan.item.name as NSString
        title.extendedLanguageTag = "und"
        return [title]
    }

    private func updatePictureSize(from engine: DirectPlayEngine) {
        if let size = engine.softwareDisplaySize, size.width > 0, size.height > 0 {
            pictureSize = size
            return
        }
        let width = CGFloat(engine.sourceVideoWidth)
        let height = CGFloat(engine.sourceVideoHeight)
        guard width > 0, height > 0 else { return }
        pictureSize = CGSize(width: width, height: height)
    }

    private func applyFillScreen() {
        engine?.videoGravity = fillsScreen ? .resizeAspectFill : .resizeAspect
        mpv?.setFillsScreen(fillsScreen)
    }

    private func refreshPlaybackStats() {
        playbackStats = makePlaybackStats()
    }

    private func makePlaybackStats() -> PlaybackStatsSnapshot {
        let playhead = currentSeconds
        let size = pictureSize
        var sections: [PlaybackStatsSection] = [
            PlaybackStatsSection(title: "Session", rows: [
                .init(label: "Title", value: plan.item.name),
                .init(label: "Playhead", value: "\(PlaybackStats.clockLabel(playhead)) / \(PlaybackStats.clockLabel(duration))"),
                .init(label: "Rate", value: abs(playbackRate - 1) < 0.01 ? "1x" : String(format: "%.2fx", playbackRate)),
                .init(label: "Stream", value: plan.method.displayName),
                .init(label: "Player", value: playerLabel),
                .init(label: "Zoom", value: fillsScreen ? "Fill" : "Fit")
            ])
        ]

        if let mpv {
            sections += mpvStatsSections(mpv.stats(), playhead: playhead)
        } else if let engine {
            // A server transcode or remux plays through AVPlayer inside the engine, which never
            // reads the source, so these fall back to what the server reported for the file.
            let facts = plan.sourceVideo
            let sourceWidth = engine.sourceVideoWidth > 0 ? Int(engine.sourceVideoWidth) : facts?.width ?? 0
            let sourceHeight = engine.sourceVideoHeight > 0 ? Int(engine.sourceVideoHeight) : facts?.height ?? 0
            let width = size.width > 0 ? size.width : CGFloat(sourceWidth)
            let height = size.height > 0 ? size.height : CGFloat(sourceHeight)
            var videoRows: [PlaybackStatsRow] = [
                .init(label: "Codec", value: (engine.sourceVideoCodecName ?? facts?.codec ?? plan.videoCodec)?.uppercased() ?? "—"),
                .init(label: "Size", value: pixelLabel(width: Int32(sourceWidth), height: Int32(sourceHeight))),
                .init(label: "Display", value: pixelLabel(width: Int32(width.rounded()), height: Int32(height.rounded()))),
                .init(label: "Aspect", value: PlaybackStats.aspectName(width: width, height: height)),
                .init(label: "Frame rate", value: frameRateLabel(engine.sourceVideoFrameRate ?? facts?.frameRate)),
                .init(label: "Average bitrate", value: PlaybackStats.bitrateLabel(sourceVideoBitrate(engine: engine))),
                // What the engine read from the stream over the last 10 seconds, video and audio together.
                .init(label: "Live bitrate", value: engine.liveTelemetry?.instantBitrateMbps
                    .map { PlaybackStats.bitrateLabel(Int64($0 * 1_000_000)) } ?? "—"),
                .init(label: "Range", value: videoRangeLabel(engine)),
                .init(label: "Container", value: (engine.sourceContainerFormat ?? plan.container).uppercased())
            ]
            if plan.method != .directPlay, let stream = Self.transcodeBitrate(in: plan.streamURL) {
                videoRows.append(.init(label: "Stream", value: PlaybackStats.bitrateLabel(Int64(stream))))
            }
            sections.append(PlaybackStatsSection(title: "Video", rows: videoRows))

            let audio = engine.audioTracks.first(where: { $0.id == engine.activeAudioTrackIndex })
                ?? engine.audioTracks.first
            let planAudio = plan.audioTracks.first(where: \.isSelected) ?? plan.audioTracks.first
            sections.append(PlaybackStatsSection(title: "Audio", rows: [
                .init(label: "Track", value: audio.map(audioTitle) ?? planAudio?.title ?? "—"),
                .init(label: "Codec", value: (audio?.codec ?? planAudio?.codec)?.uppercased() ?? "—"),
                .init(label: "Layout", value: audio.map(channelLabel) ?? "—"),
                .init(label: "Bitrate", value: PlaybackStats.bitrateLabel(audio?.bitrate ?? 0)),
                .init(label: "Delivery", value: audioDeliveryLabel(engine.audioDelivery))
            ]))

            let subtitle = engine.subtitleTracks.first(where: { $0.id == engine.activeSubtitleTrackIndex })
            sections.append(PlaybackStatsSection(title: "Decode", rows: [
                .init(label: "Video", value: engine.activeVideoDecoder ?? "—"),
                .init(label: "Audio", value: engine.activeAudioDecoder ?? "—"),
                .init(label: "Route", value: videoRouteLabel(engine.videoRoute)),
                .init(label: "Phase", value: phaseLabel(engine.playbackPhase)),
                .init(label: "Captions", value: subtitle.map { $0.name.isEmpty ? $0.codec : $0.name } ?? "Off")
            ]))

            let ahead = PlaybackStats.bufferedAhead(ranges: engine.residentRanges, playhead: playhead)
            sections.append(PlaybackStatsSection(title: "Network", rows: [
                .init(label: "Host", value: plan.streamURL.host ?? "—"),
                .init(label: "File", value: PlaybackStats.bytesLabel(plan.byteSize ?? 0)),
                .init(label: "Buffer", value: engine.isBuffering ? "Rebuffering" : String(format: "%.1fs ahead", ahead)),
                .init(label: "Seeking", value: engine.isSeeking ? "Yes" : "No"),
                .init(label: "Live", value: engine.isLive ? "Yes" : "No")
            ]))
        } else if let player, let item = player.currentItem {
            let log = item.accessLog()?.events.last
            let indicated = item.loadedTimeRanges
                .compactMap { $0.timeRangeValue }
                .map { ClosedRange(uncheckedBounds: ($0.start.seconds, $0.end.seconds)) }
            let ahead = PlaybackStats.bufferedAhead(ranges: indicated, playhead: playhead)
            let size = item.presentationSize
            let facts = plan.sourceVideo
            sections.append(PlaybackStatsSection(title: "Video", rows: [
                .init(label: "Codec", value: (facts?.codec ?? plan.videoCodec)?.uppercased() ?? "—"),
                .init(label: "Size", value: facts.map { "\($0.width)×\($0.height)" } ?? "—"),
                .init(label: "Display", value: size.width > 0 ? "\(Int(size.width))×\(Int(size.height))" : "—"),
                .init(label: "Aspect", value: PlaybackStats.aspectName(width: size.width, height: size.height)),
                .init(label: "Frame rate", value: frameRateLabel(facts?.frameRate)),
                .init(label: "Bitrate", value: PlaybackStats.bitrateLabel(Int64(facts?.bitrate ?? plan.item.sourceBitrate ?? 0))),
                .init(label: "Range", value: plan.videoRange.displayName),
                .init(label: "Audio", value: plan.audioFormat.displayName),
                .init(label: "Container", value: plan.container.uppercased())
            ]))
            sections.append(PlaybackStatsSection(title: "Network", rows: [
                .init(label: "Host", value: plan.streamURL.host ?? "—"),
                .init(label: "File", value: PlaybackStats.bytesLabel(plan.byteSize ?? 0)),
                .init(label: "Buffer", value: isBuffering ? "Rebuffering" : String(format: "%.1fs ahead", ahead)),
                .init(label: "Indicated", value: PlaybackStats.bitrateLabel(Int64((log?.indicatedBitrate ?? 0).rounded()))),
                .init(label: "Observed", value: PlaybackStats.bitrateLabel(Int64((log?.observedBitrate ?? 0).rounded())))
            ]))
        }

        return PlaybackStatsSnapshot(sections: sections)
    }

    private var playerLabel: String {
        switch pipeline {
        case .directDecode: "AetherEngine"
        case .mpv: "MPV"
        case .appleNative: "AVPlayer"
        }
    }

    private func mpvStatsSections(_ stats: MPVStats, playhead: TimeInterval) -> [PlaybackStatsSection] {
        let facts = plan.sourceVideo
        let width = stats.width ?? facts?.width ?? 0
        let height = stats.height ?? facts?.height ?? 0
        let displayWidth = stats.displayWidth ?? width
        let displayHeight = stats.displayHeight ?? height
        let sourceBitrate = Int64(facts?.bitrate ?? plan.item.sourceBitrate ?? 0)
        var videoRows: [PlaybackStatsRow] = [
            .init(label: "Codec", value: (stats.videoCodec ?? facts?.codec ?? plan.videoCodec)?.uppercased() ?? "—"),
            .init(label: "Size", value: pixelLabel(width: Int32(width), height: Int32(height))),
            .init(label: "Display", value: pixelLabel(width: Int32(displayWidth), height: Int32(displayHeight))),
            .init(label: "Aspect", value: PlaybackStats.aspectName(width: CGFloat(displayWidth), height: CGFloat(displayHeight))),
            .init(label: "Frame rate", value: frameRateLabel(stats.frameRate ?? facts?.frameRate)),
            .init(label: "Average bitrate", value: PlaybackStats.bitrateLabel(sourceBitrate)),
            .init(label: "Live bitrate", value: stats.videoBitrate.map { PlaybackStats.bitrateLabel(Int64($0)) } ?? "—"),
            .init(label: "Range", value: stats.rangeLabel),
            .init(label: "Pixels", value: [stats.hardwarePixelFormat, stats.pixelFormat].compactMap { $0 }.joined(separator: " → ").nonEmpty ?? "—"),
            .init(label: "Container", value: (stats.container ?? plan.container).uppercased())
        ]
        if plan.method != .directPlay, let stream = Self.transcodeBitrate(in: plan.streamURL) {
            videoRows.append(.init(label: "Stream", value: PlaybackStats.bitrateLabel(Int64(stream))))
        }

        let audioTrack = [NativeLanguage.displayName(stats.audioLanguage), stats.audioTitle]
            .compactMap { $0 }.joined(separator: " · ")
        let sampleRate = stats.audioSampleRate.map { String(format: "%.1f kHz", Double($0) / 1000) }
        let audioRows: [PlaybackStatsRow] = [
            .init(label: "Track", value: audioTrack.nonEmpty ?? "—"),
            .init(label: "Codec", value: stats.audioCodec?.uppercased() ?? "—"),
            .init(label: "Layout", value: [stats.channelLabel, sampleRate].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "—"),
            .init(label: "Bitrate", value: PlaybackStats.bitrateLabel(Int64(stats.audioBitrate ?? 0))),
            .init(label: "Output", value: stats.audioOutput ?? "—")
        ]

        let hardware = stats.hardwareDecoder.flatMap { $0 == "no" ? nil : $0 }
        let captions = [NativeLanguage.displayName(stats.subtitleLanguage), stats.subtitleTitle, stats.subtitleCodec?.uppercased()]
            .compactMap { $0 }.joined(separator: " · ")
        let dropped = (stats.droppedFrames ?? 0) + (stats.decoderDroppedFrames ?? 0)
        let decodeRows: [PlaybackStatsRow] = [
            .init(label: "Video", value: hardware.map { "Hardware (\($0))" } ?? "Software"),
            .init(label: "Output", value: stats.videoOutput ?? "—"),
            .init(label: "Rendered", value: stats.estimatedFrameRate.map { String(format: "%.2f fps", $0) } ?? "—"),
            .init(label: "Dropped", value: "\(dropped) frames"),
            .init(label: "A/V sync", value: stats.avSync.map { String(format: "%+.0f ms", $0 * 1000) } ?? "—"),
            .init(label: "Captions", value: captions.nonEmpty ?? "Off")
        ]

        let networkRows: [PlaybackStatsRow] = [
            .init(label: "Host", value: plan.streamURL.host ?? "Local file"),
            .init(label: "File", value: PlaybackStats.bytesLabel(plan.byteSize ?? 0)),
            .init(label: "Buffer", value: stats.isBuffering ? "Rebuffering" : String(format: "%.1fs ahead", stats.cacheSeconds ?? 0)),
            .init(label: "Speed", value: PlaybackStats.bitrateLabel(Int64((stats.cacheSpeed ?? 0) * 8))),
            .init(label: "Seeking", value: stats.isSeeking ? "Yes" : "No"),
            .init(label: "Live", value: plan.isLive ? "Yes" : "No")
        ]

        return [
            PlaybackStatsSection(title: "Video", rows: videoRows),
            PlaybackStatsSection(title: "Audio", rows: audioRows),
            PlaybackStatsSection(title: "Decode", rows: decodeRows),
            PlaybackStatsSection(title: "Network", rows: networkRows)
        ]
    }

    private func sourceVideoBitrate(engine: DirectPlayEngine) -> Int64 {
        if engine.sourceVideoBitrate > 0 { return engine.sourceVideoBitrate }
        return Int64(plan.sourceVideo?.bitrate ?? plan.item.sourceBitrate ?? 0)
    }

    /// The bitrate Zelefin asked the server to transcode to, from the stream URL.
    static func transcodeBitrate(in url: URL) -> Int? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["videobitrate", "maxstreamingbitrate"] {
            if let raw = items.first(where: { $0.name.lowercased() == name })?.value,
               let value = Int(raw), value > 0 {
                return value
            }
        }
        return nil
    }

    private func pixelLabel(width: Int32, height: Int32) -> String {
        guard width > 0, height > 0 else { return "—" }
        return "\(width)×\(height)"
    }

    private func frameRateLabel(_ rate: Double?) -> String {
        guard let rate, rate > 0 else { return "—" }
        if abs(rate - 23.976) < 0.02 { return "23.976 fps" }
        if abs(rate - rate.rounded()) < 0.02 {
            return "\(Int(rate.rounded())) fps"
        }
        return String(format: "%.3f fps", rate)
    }

    /// The file's range first: `videoFormat` is what the panel shows, so an HDR10 title on an SDR
    /// screen (base iPad) read as plain "SDR". The engine's own guidance is `sourceVideoFormat`
    /// for media labels. Jellyfin's stream metadata covers a source the probe has not tagged yet.
    private func videoRangeLabel(_ engine: DirectPlayEngine) -> String {
        var label = engine.sourceVideoFormat == .sdr && plan.videoRange != .sdr
            ? plan.videoRange.displayName
            : sourceRangeName(engine.sourceVideoFormat)
        if let profile = engine.sourceDVProfile {
            label += " P\(profile)"
        }
        if label != "SDR", engine.videoFormat == .sdr {
            label += " (tone-mapped to SDR)"
        } else if engine.videoFormat != engine.sourceVideoFormat, engine.videoFormat != .sdr {
            label += " (shown as \(sourceRangeName(engine.videoFormat)))"
        }
        return label
    }

    private func sourceRangeName(_ format: DirectPlayVideoFormat) -> String {
        switch format {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }

    private func audioTitle(_ track: DirectPlayTrack) -> String {
        if !track.name.isEmpty { return track.name }
        if let language = track.language, language.lowercased() != "und" {
            return Locale.current.localizedString(forLanguageCode: language) ?? language
        }
        return "Track \(track.id)"
    }

    private func channelLabel(_ track: DirectPlayTrack) -> String {
        if track.isAtmos { return "Atmos" }
        switch track.channels {
        case 2: return "Stereo"
        case 6: return "5.1"
        case 8: return "7.1"
        case 0: return "—"
        default: return "\(track.channels) ch"
        }
    }

    private func audioDeliveryLabel(_ delivery: DirectPlayAudioDelivery) -> String {
        switch delivery {
        case .none: "—"
        case .noAudioInSource: "No audio"
        case .streamCopy: "Bitstream"
        case .bridged: "Bridged"
        case .decoded: "Decoded"
        case .droppedNoPipeline: "Dropped"
        case .playerManaged: "AVPlayer"
        }
    }

    private func videoRouteLabel(_ route: DirectPlayVideoRoute) -> String {
        switch route {
        case .none: "—"
        case .remoteBypass: "AVPlayer"
        case .loopback: "Local HLS"
        case .software: "Sample buffer"
        case .audio: "Audio only"
        }
    }

    private func phaseLabel(_ phase: DirectPlayPlaybackPhase) -> String {
        switch phase {
        case .idle: "Idle"
        case .loading: "Loading"
        case .playing: "Playing"
        case .paused: "Paused"
        case .seeking: "Seeking"
        case .rebuffering: "Rebuffering"
        case .stalled(let reconnecting): reconnecting ? "Reconnecting" : "Stalled"
        case .ended: "Ended"
        case .error: "Error"
        }
    }

    private func attachPictureInPicture(_ source: DirectPlayPiPSource?) {
        pictureInPicture.onPossibleChange = { [weak self] possible in
            self?.canUsePictureInPicture = possible
        }
        pictureInPicture.onActiveChange = { [weak self] active in
            self?.handlePictureInPictureActiveChange(active)
        }
        pictureInPicture.attach(source: source, engine: engine)
        canUsePictureInPicture = pictureInPicture.canStart
    }

    private func handlePictureInPictureActiveChange(_ active: Bool) {
        if active {
            return
        }
        guard stopWhenPictureInPictureEnds else { return }
        stopWhenPictureInPictureEnds = false
        Task { await stop() }
    }

    private static func makeNativePlayer(url: URL, extraHeaders: [String: String] = [:]) -> AVPlayer {
        let item: AVPlayerItem
        if url.isFileURL {
            item = AVPlayerItem(url: url)
        } else {
            var headers = PlaybackHTTPHeaders.fields(for: url)
            for (name, value) in extraHeaders {
                headers[name] = value
            }
            if !headers.isEmpty || !(HTTPCookieStorage.shared.cookies(for: url) ?? []).isEmpty {
                var options: [String: Any] = [:]
                if !headers.isEmpty {
                    options["AVURLAssetHTTPHeaderFieldsKey"] = headers
                }
                if let cookies = HTTPCookieStorage.shared.cookies(for: url), !cookies.isEmpty {
                    options["AVURLAssetHTTPCookiesKey"] = cookies
                }
                item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
            } else {
                item = AVPlayerItem(url: url)
            }
        }
        item.textStyleRules = SubtitleAppearance.textStyleRules()
        let player = AVPlayer(playerItem: item)
        player.appliesMediaSelectionCriteriaAutomatically = true
        return player
    }
}

struct PlaybackTrackOption: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String

    init(id: Int, title: String) {
        self.id = id
        self.title = title
    }

    init(_ track: MediaTrack) {
        id = track.id
        if !track.title.isEmpty {
            title = track.title
        } else if let language = track.language, language.lowercased() != "und" {
            title = Locale.current.localizedString(forLanguageCode: language) ?? language
        } else {
            title = "Track \(track.id)"
        }
    }

    init(_ track: DirectPlayTrack) {
        id = track.id
        title = Self.displayTitle(for: track)
    }

    private static func displayTitle(for track: DirectPlayTrack) -> String {
        var parts: [String] = []
        if !track.name.isEmpty, track.name.lowercased() != "und" {
            parts.append(track.name)
        } else if let language = track.language, language.lowercased() != "und" {
            parts.append(Locale.current.localizedString(forLanguageCode: language) ?? language)
        }
        if track.channels >= 6 {
            parts.append(track.isAtmos ? "Atmos" : "\(track.channels) ch")
        } else if track.isAtmos {
            parts.append("Atmos")
        }
        if parts.isEmpty {
            return "Track \(track.id)"
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
