import AVFoundation
import AVKit
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
    private(set) var mpv: MPVPlayback?
    private(set) var errorMessage: String?
    private(set) var hasFirstFrame = false
    private(set) var isPaused = false {
        didSet { updateWakeLock() }
    }
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isBuffering = false
    private(set) var playbackRate: Float = 1
    private(set) var audioOptions: [PlaybackTrackOption] = []
    private(set) var subtitleOptions: [PlaybackTrackOption] = []
    private(set) var pictureSize: CGSize = .zero
    private(set) var canUsePictureInPicture = false
    var isPictureInPictureActive: Bool {
        pictureInPicture.isActive || nativePictureInPictureActive
    }
    /// Set from PlayerView so stop can restore a SyncPlay Live Activity without SessionStore.
    var syncPlayGroupNameForRestore: (() -> String?)?
    private(set) var fillsScreen = false
    /// Top edge of the visible progress bar in screen points, nil while the controls are hidden.
    /// Subtitles that would sit under it rise above it.
    private(set) var controlsTop: CGFloat?
    @ObservationIgnored private var mpvSurfaceFrame: CGRect = .zero
    private(set) var showsPlaybackStats = false
    private(set) var playbackStats = PlaybackStatsSnapshot(sections: [])
    private(set) var sleepTimer: SleepTimerMode = .off
    /// Seconds left on a timed sleep timer, for the countdown label. Nil when the
    /// timer is off or set to end-of-episode.
    private(set) var sleepTimerRemaining: TimeInterval?
    private var sleepTimerTask: Task<Void, Never>?

    var selectedAudioID: Int?
    var selectedSubtitleID: Int?
    private let serverAudioID: Int?
    private let serverSubtitleID: Int?
    private var startedOnServerAudio = false
    private var startedOnServerSubtitle = false
    var isFinished = false {
        didSet { updateWakeLock() }
    }
    var skipSegments: [SkipSegment] = []
    var skipPrompt: SkipSegment?

    private let reporter: (any PlaybackReporting)?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var lastTrustedTime: TimeInterval = 0
    private var engineIsBuffering = false
    private var engineIsSeeking = false
    private var isSurfaceBound = false
    private var didStart = false {
        didSet { updateWakeLock() }
    }
    private let wakeLock = PlaybackWakeLock()
    private var didAttemptDeferredResume = false
    private var isRestoringForeground = false
    private var mpvTracks: [MPVPlayback.Track] = []
    private var nativePictureInPictureActive = false
    private var stopWhenPictureInPictureEnds = false
    /// Bumped after background return so SwiftUI detaches and reattaches the layer.
    private(set) var surfaceGeneration = 0
    private let pictureInPicture = DirectPlayPictureInPicture()
    /// Holds mute-while-playing for this session. Released with the model.
    private let alertPresence = PlaybackPresence()
    #if !targetEnvironment(macCatalyst)
    private let mpvPictureInPictureTransport = MPVPictureInPictureTransport()
    #endif
    private var resignActiveObserver: NSObjectProtocol?
    /// Companion AVPlayer for AirPlay only — MPV keeps local playback (ArcFin-style: route an AVPlayer, don't rebuild the engine).
    private(set) var airPlayRelay: AVPlayer?
    private var airPlayRelayObservation: NSKeyValueObservation?
    private var airPlayRelayTimeObserver: Any?
    private(set) var isAirPlayingExternally = false
    /// Parks the warm relay if the AirPlay sheet is cancelled (stops remux bandwidth fight).
    private var airPlayParkTask: Task<Void, Never>?
    /// Debounces brief `isExternalPlaybackActive` flickers while the route sheet opens.
    private var airPlayDisconnectTask: Task<Void, Never>?
    /// True while Chromecast owns playback (local engine is paused).
    var isCastingExternally: Bool { CastManager.shared.isConnected }
    private var castPositionPollTask: Task<Void, Never>?

    init(
        plan: PlaybackPlan,
        reporter: (any PlaybackReporting)?,
        pipelineOverride: PlaybackPipeline? = nil
    ) {
        self.plan = plan
        self.reporter = reporter
        self.pipeline = pipelineOverride ?? PlaybackPipelineResolver.pipeline(for: plan)
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
            player = Self.makeNativePlayer(
                url: plan.streamURL,
                extraHeaders: plan.extraHTTPHeaders,
                item: plan.item
            )
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
                refreshDeviceVolume()
                applyVolume()
                await seekNativeToResumeIfNeeded()
                player?.play()
                setPlaybackRate(PlaybackPreferences.defaultRate)
                observeNativeTime()
                observeNativeEnd()
                hasFirstFrame = true
            case .mpv:
                try Task.checkCancellation()
                await PlaybackAudioSession.activate()
                await waitUntilSurfaceReady()
                try Task.checkCancellation()
                startMPV()
                refreshDeviceVolume()
                applyVolume()
                setPlaybackRate(PlaybackPreferences.defaultRate)
            }
            await reportPlaybackStarted()
            didStart = true
            installResignActivePiPArming()
            onDidStart?()
            RemoteControlHub.shared.attach(self)
            LibraryAlertSettings.beginPlaybackPresence(alertPresence)
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
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        tearDownAirPlayRelay()
        airPlayParkTask?.cancel()
        airPlayParkTask = nil
        airPlayDisconnectTask?.cancel()
        airPlayDisconnectTask = nil
        castPositionPollTask?.cancel()
        castPositionPollTask = nil
        sleepTimerTask?.cancel()
        sleepTimerTask = nil

        let seconds = reportedSeconds
        pictureInPicture.suppressAutomaticStart()
        canUsePictureInPicture = false
        applyNativeAutomaticPictureInPicture?(false)
        player?.pause()
        mpv?.stop()
        didStart = false
        isAirPlayingExternally = false
        nativePictureInPictureActive = false
        stopWhenPictureInPictureEnds = false
        applyNativeAutomaticPictureInPicture = nil
        RemoteControlHub.shared.detach(self)
        LibraryAlertSettings.endPlaybackPresence(alertPresence)
        await reportPlaybackStopped(at: seconds)
        // Playback cleared Live Activities so PiP could start; put SyncPlay back if still joined.
        if let name = syncPlayGroupNameForRestore?() {
            SyncPlayActivityPresenter.start(groupName: name, statusLine: "Joined")
        }
    }

    /// Held while a title plays, so neither the screen nor the Mac sleeps under it.
    private func updateWakeLock() {
        wakeLock.hold(didStart && !isPaused && !isFinished)
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
        if dismissedIntoPictureInPicture {
            dismissedIntoPictureInPicture = false
            return
        }
        // Closing with PiP off already stopped in leavePlayback; skip a second stop.
        guard didStart else { return }
        if PlaybackPictureInPicturePolicy.shouldStopOnViewDismiss(
            pictureInPictureActive: isPictureInPictureActive
        ) {
            Task { await stop() }
            return
        }
        stopWhenPictureInPictureEnds = true
    }

    /// True when the player view left the screen after handing playback to PiP.
    private(set) var dismissedIntoPictureInPicture = false

    /// Prefer continuing in PiP when the user closes the player. Returns true if PiP took over.
    @discardableResult
    func leavePreferringPictureInPicture() async -> Bool {
        guard PlaybackPreferences.autoPictureInPictureOnLeave else { return false }
        if isPictureInPictureActive {
            stopWhenPictureInPictureEnds = true
            dismissedIntoPictureInPicture = true
            return true
        }
        guard didStart, !isFinished else { return false }
        startPictureInPictureIfPossible()
        for _ in 0..<24 {
            if isPictureInPictureActive { break }
            try? await Task.sleep(for: .milliseconds(40))
        }
        if isPictureInPictureActive {
            stopWhenPictureInPictureEnds = true
            dismissedIntoPictureInPicture = true
            return true
        }
        return false
    }

    func setNativePictureInPictureActive(_ active: Bool) {
        nativePictureInPictureActive = active
        handlePictureInPictureActiveChange(active)
    }

    func syncPictureInPicture() {
        guard !pictureInPicture.isBlocked else {
            canUsePictureInPicture = isPictureInPictureActive
            return
        }
        // Keep the controller absent when auto-PiP is off until the user taps PiP or leaves with it on.
        if PlaybackPreferences.autoPictureInPictureOnLeave || pictureInPicture.controller != nil {
            pictureInPicture.syncController()
        }
        canUsePictureInPicture = pictureInPicture.canStart || isPictureInPictureActive
    }

    /// Must run on `willResignActive`, not after awaiting anything, so PiP can arm before background.
    func startPictureInPictureIfPossible() {
        guard PlaybackPictureInPicturePolicy.shouldAutoStart(
            preferenceEnabled: PlaybackPreferences.autoPictureInPictureOnLeave
        ) else { return }
        pictureInPicture.armForBackground()
        canUsePictureInPicture = pictureInPicture.canStart || isPictureInPictureActive
    }

    /// Leave without PiP: tear the controller down so dismiss cannot auto-start it.
    func suppressAutomaticPictureInPicture() {
        pictureInPicture.suppressAutomaticStart()
        canUsePictureInPicture = false
        applyNativeAutomaticPictureInPicture?(false)
    }

    /// Native leave with the toggle on: let AVKit promote as the player VC dismisses.
    func prepareNativeLeaveIntoPictureInPicture() {
        guard PlaybackPreferences.autoPictureInPictureOnLeave else { return }
        guard player != nil, mpv == nil else { return }
        applyNativeAutomaticPictureInPicture?(true)
        stopWhenPictureInPictureEnds = true
        dismissedIntoPictureInPicture = true
    }

    /// Native AVPlayerViewController — set from PlayerView so leave can flip auto-PiP before dismiss.
    var applyNativeAutomaticPictureInPicture: ((Bool) -> Void)?

    func restoreAfterForeground() async {
        guard didStart, !isRestoringForeground else { return }
        if isPictureInPictureActive { return }
        isRestoringForeground = true
        defer { isRestoringForeground = false }

        #if !targetEnvironment(macCatalyst)
        // A display layer iOS invalidated in the background stays black until flushed.
        if let mpv, mpv.displayLayer.sampleBufferRenderer.status == .failed {
            mpv.displayLayer.sampleBufferRenderer.flush()
        }
        #endif
        if mpv != nil { return }

        if player != nil {
            surfaceGeneration += 1
            if !isPaused {
                player?.play()
            }
        }
    }

    var onUserTransport: ((RemotePlaybackAction) -> Void)?
    /// Fired when the user changes speed locally — SharePlay forwards it to peers.
    var onPlaybackRateChange: ((Float) -> Void)?
    var onDidStart: (() -> Void)?
    var onRemoteSeekApplied: ((TimeInterval) -> Void)?
    @ObservationIgnored private var isApplyingRemote = false

    func togglePlayPause() {
        let pause = !isPaused
        if isCastingExternally {
            CastManager.shared.togglePlayPause()
            isPaused = pause
            notifyUserTransport(pause ? .pause : .play)
            return
        }
        if isAirPlayingExternally, let airPlayRelay {
            if pause { airPlayRelay.pause() } else { airPlayRelay.play() }
            isPaused = pause
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
        if isCastingExternally {
            CastManager.shared.pause()
            isPaused = true
            return
        }
        if isAirPlayingExternally {
            airPlayRelay?.pause()
            isPaused = true
            return
        }
        if let mpv {
            mpv.pause()
            isPaused = true
            return
        }
        player?.pause()
        isPaused = true
    }

    private func resumePlayback() {
        if isCastingExternally {
            CastManager.shared.play()
            isPaused = false
            return
        }
        if isAirPlayingExternally {
            airPlayRelay?.play()
            isPaused = false
            return
        }
        if let mpv {
            mpv.play()
            isPaused = false
            return
        }
        player?.play()
        setPlaybackRate(playbackRate)
        isPaused = false
    }

    /// Mirrors device media volume (0–1). Gestures and keyboard change the system level.
    private(set) var volume: Float = 1
    private(set) var isMuted = false

    func setMuted(_ muted: Bool) {
        isMuted = muted
        applyVolume()
    }

    func adjustVolume(by delta: Float) {
        setVolumeLevel(volume + delta)
    }

    func setVolumeLevel(_ level: Float) {
        let clamped = min(1, max(0, level))
        DeviceVolume.set(clamped)
        // Optimistic UI — outputVolume can lag a frame behind the slider write.
        volume = clamped
        if volume > 0 { isMuted = false }
        applyVolume()
    }

    /// Syncs `volume` from the hardware level (e.g. at the start of a volume pan).
    func refreshDeviceVolume() {
        volume = DeviceVolume.level
    }

    private func applyVolume() {
        // Keep the player at full gain so gestures control the device volume only.
        let level: Float = isMuted ? 0 : 1
        mpv?.setVolume(level)
        player?.volume = level
        player?.isMuted = isMuted
    }

    /// Jumps to a share of the runtime, as the number keys do.
    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: duration * min(max(fraction, 0), 1))
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
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        if isCastingExternally {
            CastManager.shared.seek(toSeconds: clamped)
        } else if isAirPlayingExternally, let airPlayRelay {
            airPlayRelay.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else if let mpv {
            mpv.seek(to: clamped)
        } else if let player {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        skipPrompt = SkipSegment.prompt(in: skipSegments, at: clamped + 0.05)
        notifyUserTransport(.seek(clamped))
    }

    /// Local engine yields to Chromecast; poll the receiver playhead for chrome.
    func beginCastingExternally() {
        mpv?.pause()
        player?.pause()
        airPlayRelay?.pause()
        isPaused = CastManager.shared.isPaused
        startCastPositionPolling()
    }

    /// Resume local playback from the last Chromecast playhead.
    func resumeLocalPlaybackAfterCast() {
        castPositionPollTask?.cancel()
        castPositionPollTask = nil
        let playhead = CastManager.shared.lastKnownPositionSeconds ?? currentTime
        currentTime = playhead
        if let mpv {
            mpv.seek(to: playhead)
            if !isPaused { mpv.play() }
        } else if let player {
            let time = CMTime(seconds: playhead, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            if !isPaused { player.play() }
        }
    }

    private func startCastPositionPolling() {
        castPositionPollTask?.cancel()
        castPositionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isCastingExternally else { return }
                if let seconds = CastManager.shared.lastKnownPositionSeconds ?? CastManager.shared.currentPositionSeconds() {
                    self.currentTime = seconds
                }
                self.isPaused = CastManager.shared.isPaused
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// SharePlay peer command — applied locally without re-broadcasting.
    /// Must set `isApplyingRemote` so seek/play don't echo back over SharePlay (that ping-pong
    /// is what made Skip Intro stall one side).
    func applySharePlayCommand(_ command: SharePlayCommand) {
        guard command.itemId == plan.item.id else { return }
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        if abs(playbackRate - command.rate) > 0.01 {
            setPlaybackRate(command.rate)
        }
        switch command.kind {
        case .hello:
            break
        case .rate:
            break
        case .seek:
            // Skip Intro jumps far; ignore tiny corrections so we don't stack seeks.
            guard abs(currentTime - command.positionSeconds) > 1 else { return }
            seek(to: command.positionSeconds)
        case .play:
            if abs(currentTime - command.positionSeconds) > 2 {
                seek(to: command.positionSeconds)
            }
            if isPaused { togglePlayPause() }
        case .pause:
            if abs(currentTime - command.positionSeconds) > 2 {
                seek(to: command.positionSeconds)
            }
            if !isPaused { togglePlayPause() }
        }
    }

    /// Installs (or replaces) the companion AVPlayer used only for AirPlay. Does not stop MPV.
    func installAirPlayRelay(url: URL, extraHeaders: [String: String] = [:]) {
        tearDownAirPlayRelay()
        let relay = Self.makeNativePlayer(url: url, extraHeaders: extraHeaders, item: plan.item)
        // Stay muted on-device; the TV still gets video once a layer is in the hierarchy.
        relay.isMuted = true
        airPlayRelay = relay
        observeAirPlayRelay(relay)
    }

    /// Seek/warm the relay so AirPlay can pick video (not audio-only) when the sheet opens.
    func prepareAirPlayRelayForPresentation() async {
        guard let relay = airPlayRelay else { return }
        airPlayParkTask?.cancel()
        airPlayParkTask = nil
        let playhead = currentTime
        let time = CMTime(seconds: playhead, preferredTimescale: 600)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            relay.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                continuation.resume()
            }
        }
        // Playing (muted) with a full-size on-screen layer is what makes iOS offer video AirPlay.
        relay.isMuted = true
        relay.rate = playbackRate == 0 ? 1 : playbackRate
        relay.play()
        await waitUntilAirPlayRelayReady(relay)
        // Give the layer a couple frames of decoded video before the route sheet.
        try? await Task.sleep(for: .milliseconds(150))
    }

    /// After the route sheet opens: if the user cancels, stop the warm remux so MPV doesn't starve.
    func scheduleAirPlayRelayParkIfUnused() {
        airPlayParkTask?.cancel()
        airPlayParkTask = Task { [weak self] in
            // Sheet + device pick; if nothing connects, tear the relay down.
            for _ in 0..<24 {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                if self.isAirPlayingExternally || self.airPlayRelay?.isExternalPlaybackActive == true {
                    return
                }
            }
            guard let self, !self.isAirPlayingExternally else { return }
            self.parkUnusedAirPlayRelay()
        }
    }

    private func waitUntilAirPlayRelayReady(_ relay: AVPlayer) async {
        for _ in 0..<60 {
            if let item = relay.currentItem {
                switch item.status {
                case .readyToPlay:
                    let tracks = item.tracks.filter { $0.assetTrack?.mediaType == .video }
                    if !tracks.isEmpty || item.isPlaybackLikelyToKeepUp {
                        return
                    }
                case .failed:
                    return
                default:
                    break
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func observeAirPlayRelay(_ relay: AVPlayer) {
        airPlayRelayObservation = relay.observe(
            \.isExternalPlaybackActive,
            options: [.new]
        ) { [weak self] player, _ in
            let active = player.isExternalPlaybackActive
            Task { @MainActor in
                self?.handleAirPlayExternalActive(active)
            }
        }
        // Scrubber / progress follow the TV playhead while AirPlaying.
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        airPlayRelayTimeObserver = relay.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self, self.isAirPlayingExternally else { return }
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self.currentTime = seconds
                self.isPaused = self.airPlayRelay?.rate == 0
            }
        }
    }

    private func handleAirPlayExternalActive(_ active: Bool) {
        if active {
            airPlayDisconnectTask?.cancel()
            airPlayDisconnectTask = nil
            airPlayParkTask?.cancel()
            airPlayParkTask = nil
            guard !isAirPlayingExternally else { return }
            isAirPlayingExternally = true
            // TV shows the companion; pause MPV so the phone isn't double-decoding.
            mpv?.pause()
            isPaused = false
            airPlayRelay?.isMuted = false
            airPlayRelay?.rate = playbackRate == 0 ? 1 : playbackRate
            airPlayRelay?.play()
            return
        }
        // Route sheet open/cancel can flicker this flag — debounce before touching MPV.
        airPlayDisconnectTask?.cancel()
        airPlayDisconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            guard self.airPlayRelay?.isExternalPlaybackActive != true else { return }
            if !self.isAirPlayingExternally {
                // Cancelled before a real handoff — drop the warm relay, leave MPV alone.
                self.parkUnusedAirPlayRelay()
                return
            }
            self.isAirPlayingExternally = false
            let seconds = self.airPlayRelay?.currentTime().seconds
            let playhead = (seconds?.isFinite == true ? seconds! : self.currentTime)
            self.airPlayRelay?.pause()
            self.airPlayRelay?.isMuted = true
            if let mpv = self.mpv {
                mpv.seek(to: playhead)
                self.currentTime = playhead
                if !self.isPaused { mpv.play() }
            }
            // Stop remux download after the AirPlay session ends.
            self.tearDownAirPlayRelay()
        }
    }

    /// Stops a warm (muted) relay that never went external so it can't starve MPV.
    private func parkUnusedAirPlayRelay() {
        guard !isAirPlayingExternally else { return }
        let wasPlaying = !isPaused
        tearDownAirPlayRelay()
        if wasPlaying, let mpv {
            mpv.play()
        }
    }

    private func tearDownAirPlayRelay() {
        airPlayParkTask?.cancel()
        airPlayParkTask = nil
        airPlayDisconnectTask?.cancel()
        airPlayDisconnectTask = nil
        airPlayRelayObservation?.invalidate()
        airPlayRelayObservation = nil
        if let airPlayRelayTimeObserver, let airPlayRelay {
            airPlayRelay.removeTimeObserver(airPlayRelayTimeObserver)
        }
        airPlayRelayTimeObserver = nil
        airPlayRelay?.pause()
        airPlayRelay?.replaceCurrentItem(with: nil)
        airPlayRelay = nil
        isAirPlayingExternally = false
    }

    private func notifyUserTransport(_ action: RemotePlaybackAction) {
        guard !isApplyingRemote else { return }
        onUserTransport?(action)
    }

    private func publishWaitState() {
        let waiting = engineIsBuffering || engineIsSeeking
        if isBuffering != waiting {
            isBuffering = waiting
        }
    }

    var isSeeking: Bool { engineIsSeeking }

    var isRebuffering: Bool {
        hasFirstFrame && !isPaused && !engineIsSeeking && isBuffering
    }

    /// Seconds of media already buffered past the playhead (scrubber “ahead” fill).
    private(set) var bufferedAheadSeconds: TimeInterval = 0

    private func refreshBufferedAhead() {
        if let player, let item = player.currentItem {
            let ranges = item.loadedTimeRanges.compactMap { $0.timeRangeValue }.map {
                ClosedRange(uncheckedBounds: ($0.start.seconds, $0.end.seconds))
            }
            bufferedAheadSeconds = PlaybackStats.bufferedAhead(ranges: ranges, playhead: currentTime)
            return
        }
        if let mpv {
            bufferedAheadSeconds = max(0, mpv.stats().cacheSeconds ?? 0)
            return
        }
        bufferedAheadSeconds = 0
    }

    func selectAudio(id: Int) {
        selectedAudioID = id
        mpv?.selectAudio(id)
    }

    func selectSubtitle(id: Int?) {
        selectedSubtitleID = id
        applySubtitleSelection(id)
    }

    func applySubtitleAppearance() {
        player?.currentItem?.textStyleRules = SubtitleAppearance.textStyleRules()
        mpv?.setSubtitleStyle(SubtitleAppearance.mpvProperties())
        applyMPVSubtitlePosition()
    }

    func setControlsTop(_ top: CGFloat?) {
        guard controlsTop != top else { return }
        controlsTop = top
        applyMPVSubtitlePosition()
    }

    func setMPVSurfaceFrame(_ frame: CGRect) {
        guard mpvSurfaceFrame != frame else { return }
        mpvSurfaceFrame = frame
        applyMPVSubtitlePosition()
    }

    private func applyMPVSubtitlePosition() {
        guard let mpv else { return }
        let base = SubtitleAppearance.mpvSubtitlePosition
        let userScale = SubtitleAppearance.size.scale
        guard mpvSurfaceFrame.height > 0, pictureSize.width > 0, pictureSize.height > 0 else {
            mpv.setSubtitleScale(userScale)
            mpv.setSubtitlePosition(base)
            return
        }
        let adjusted = SubtitleAppearance.mpvFillSubtitle(
            userScale: userScale,
            basePosition: base,
            picture: pictureSize,
            window: mpvSurfaceFrame,
            fill: fillsScreen,
            ceiling: controlsTop.map { $0 - 8 }
        )
        mpv.setSubtitleScale(adjusted.scale)
        mpv.setSubtitlePosition(adjusted.position)
    }

    private func applySubtitleSelection(_ id: Int?) {
        mpv?.selectSubtitle(id)
    }

    func setPlaybackRate(_ rate: Float) {
        let previous = playbackRate
        playbackRate = rate
        mpv?.setRate(rate)
        if isAirPlayingExternally, let airPlayRelay {
            airPlayRelay.rate = airPlayRelay.rate == 0 ? 0 : rate
        }
        if let player {
            player.rate = player.rate == 0 ? 0 : rate
        }
        if !isApplyingRemote, abs(previous - rate) > 0.01 {
            onPlaybackRateChange?(rate)
        }
    }

    func togglePictureInPicture() {
        pictureInPicture.toggle()
        canUsePictureInPicture = pictureInPicture.canStart || isPictureInPictureActive
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
        #if !targetEnvironment(macCatalyst)
        if mpv != nil {
            attachMPVPictureInPicture()
        }
        #endif
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
        let trustedPlayhead = currentTime.isFinite ? currentTime : 0
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
        mpv.setSubtitleStyle(SubtitleAppearance.mpvProperties())
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
            refreshBufferedAhead()
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
            finishDeferredResumeIfNeeded()
            #if !targetEnvironment(macCatalyst)
            attachMPVPictureInPicture()
            #endif
        case .tracks(let tracks):
            applyMPVTracks(tracks)
        case .audioSelected(let id):
            if let id, selectedAudioID != id { selectedAudioID = id }
        case .subtitleSelected(let id):
            if selectedSubtitleID != id { selectedSubtitleID = id }
        case .videoSize(let size):
            pictureSize = size
            applyMPVSubtitlePosition()
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
        mpvTracks = tracks
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

        // mpv reports an empty list before the file opens; picking then would turn subtitles off for good.
        let externalCount = subtitles.filter(\.isExternal).count
        if !startedOnServerSubtitle, !tracks.isEmpty, externalCount >= plan.externalSubtitles.count {
            startedOnServerSubtitle = true
            guard serverSubtitleID != nil else {
                selectedSubtitleID = nil
                mpv.selectSubtitle(nil)
                return
            }
            let planned = plan.subtitleTracks.first(where: \.isSelected)
            let target = MPVTrackMatch.track(
                for: serverSubtitleID,
                language: planned?.language,
                in: tracks,
                kind: .subtitle,
                externalSubtitles: plan.externalSubtitles
            )
            selectedSubtitleID = target?.id
            mpv.selectSubtitle(target?.id)
        }
    }

    /// The server's stream index for a track picked in this player's menu, plus what it is, for the
    /// per-show memory. MPV numbers tracks per type, so its ids are not stream indices; its streamIndex
    /// is, for a file played as-is. AVPlayer lists tracks by stream index already.
    func audioPick(id: Int) -> (serverIndex: Int?, choice: TrackChoice?) {
        if mpv != nil {
            guard let track = mpvTracks.first(where: { $0.kind == .audio && $0.id == id }) else { return (nil, nil) }
            let index = plan.method == .directPlay ? track.streamIndex : nil
            return (index, TrackChoice(language: track.language, title: track.title, isForced: track.isForced))
        }
        let track = plan.audioTracks.first { $0.id == id }
        return (id, track.map { TrackChoice(language: $0.language, title: $0.title, isForced: SeriesTrackMemory.isForced($0)) })
    }

    /// True while the subtitle on screen is a picture (PGS, VobSub), which only the size setting changes.
    var showsPictureSubtitles: Bool {
        guard let id = selectedSubtitleID else { return false }
        let codec: String?
        if mpv != nil {
            codec = mpvTracks.first { $0.kind == .subtitle && $0.id == id }?.codec
        } else {
            codec = plan.subtitleTracks.first { $0.id == id }?.codec
        }
        return SubtitleAppearance.isPictureCodec(codec)
    }

    func subtitlePick(id: Int) -> (serverIndex: Int?, choice: TrackChoice?) {
        if mpv != nil {
            guard let track = mpvTracks.first(where: { $0.kind == .subtitle && $0.id == id }) else { return (nil, nil) }
            let choice = TrackChoice(language: track.language, title: track.title, isForced: track.isForced)
            guard plan.method == .directPlay else { return (nil, choice) }
            if !track.isExternal, let index = track.streamIndex {
                return (index, choice)
            }
            return (MPVTrackMatch.jellyfinSubtitleIndex(for: track, in: plan, mpvTracks: mpvTracks), choice)
        }
        let track = plan.subtitleTracks.first { $0.id == id }
        return (id, track.map { TrackChoice(language: $0.language, title: $0.title, isForced: SeriesTrackMemory.isForced($0)) })
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
                self.refreshBufferedAhead()
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
        let seconds = player?.currentTime().seconds ?? 0
        return seconds.isFinite ? seconds : 0
    }

    private var reportedSeconds: TimeInterval { currentSeconds }

    private func applyFillScreen() {
        mpv?.setFillsScreen(fillsScreen)
        applyMPVSubtitlePosition()
    }

    private func refreshPlaybackStats() {
        playbackStats = makePlaybackStats()
    }

    private func makePlaybackStats() -> PlaybackStatsSnapshot {
        let playhead = currentSeconds
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
        } else if let player, let item = player.currentItem {
            let log = item.accessLog()?.events.last
            let indicated = item.loadedTimeRanges
                .compactMap { $0.timeRangeValue }
                .map { ClosedRange(uncheckedBounds: ($0.start.seconds, $0.end.seconds)) }
            let ahead = PlaybackStats.bufferedAhead(ranges: indicated, playhead: playhead)
            let size = item.presentationSize
            let facts = plan.sourceVideo
            sections.append(PlaybackStatsSection(title: AppLanguage.string("ui.video", default: "Video"), rows: [
                .init(label: "Codec", value: (facts?.codec ?? plan.videoCodec)?.uppercased() ?? "—"),
                .init(label: "Size", value: facts.map { "\($0.width)×\($0.height)" } ?? "—"),
                .init(label: "Display", value: size.width > 0 ? "\(Int(size.width))×\(Int(size.height))" : "—"),
                .init(label: "Aspect", value: PlaybackStats.aspectName(width: size.width, height: size.height)),
                .init(label: AppLanguage.string("ui.frame_rate", default: "Frame rate"), value: frameRateLabel(facts?.frameRate)),
                .init(label: AppLanguage.string("ui.bitrate", default: "Bitrate"), value: PlaybackStats.bitrateLabel(Int64(facts?.bitrate ?? plan.item.sourceBitrate ?? 0))),
                .init(label: "Range", value: plan.videoRange.displayName),
                .init(label: "Audio", value: plan.audioFormat.displayName),
                .init(label: "Container", value: plan.container.uppercased())
            ]))
            sections.append(PlaybackStatsSection(title: AppLanguage.string("settings.network", default: "Network"), rows: [
                .init(label: "Host", value: plan.streamURL.host ?? "—"),
                .init(label: AppLanguage.string("detail.file", default: "File"), value: PlaybackStats.bytesLabel(plan.byteSize ?? 0)),
                .init(label: "Buffer", value: isBuffering ? "Rebuffering" : String(format: "%.1fs ahead", ahead)),
                .init(label: "Indicated", value: PlaybackStats.bitrateLabel(Int64((log?.indicatedBitrate ?? 0).rounded()))),
                .init(label: "Observed", value: PlaybackStats.bitrateLabel(Int64((log?.observedBitrate ?? 0).rounded())))
            ]))
        }

        return PlaybackStatsSnapshot(sections: sections)
    }

    private var playerLabel: String {
        switch pipeline {
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
            .init(label: AppLanguage.string("settings.size", default: "Size"), value: pixelLabel(width: Int32(width), height: Int32(height))),
            .init(label: AppLanguage.string("ui.display", default: "Display"), value: pixelLabel(width: Int32(displayWidth), height: Int32(displayHeight))),
            .init(label: "Aspect", value: PlaybackStats.aspectName(width: CGFloat(displayWidth), height: CGFloat(displayHeight))),
            .init(label: AppLanguage.string("ui.frame_rate", default: "Frame rate"), value: frameRateLabel(stats.frameRate ?? facts?.frameRate)),
            .init(label: AppLanguage.string("ui.average_bitrate", default: "Average bitrate"), value: PlaybackStats.bitrateLabel(sourceBitrate)),
            .init(label: "Live bitrate", value: stats.videoBitrate.map { PlaybackStats.bitrateLabel(Int64($0)) } ?? "—"),
            .init(label: "Range", value: stats.rangeLabel),
            .init(label: "Pixels", value: [stats.hardwarePixelFormat, stats.pixelFormat].compactMap { $0 }.joined(separator: " → ").nonEmpty ?? "—"),
            .init(label: "Container", value: (stats.container ?? plan.container).uppercased())
        ]
        if plan.method != .directPlay, let stream = Self.transcodeBitrate(in: plan.streamURL) {
            videoRows.append(.init(label: AppLanguage.string("ui.stream", default: "Stream"), value: PlaybackStats.bitrateLabel(Int64(stream))))
        }

        let audioTrack = [NativeLanguage.displayName(stats.audioLanguage), stats.audioTitle]
            .compactMap { $0 }.joined(separator: " · ")
        let sampleRate = stats.audioSampleRate.map { String(format: "%.1f kHz", Double($0) / 1000) }
        let audioRows: [PlaybackStatsRow] = [
            .init(label: "Track", value: audioTrack.nonEmpty ?? "—"),
            .init(label: "Codec", value: stats.audioCodec?.uppercased() ?? "—"),
            .init(label: "Layout", value: [stats.channelLabel, sampleRate].compactMap { $0 }.joined(separator: " · ").nonEmpty ?? "—"),
            .init(label: AppLanguage.string("ui.bitrate", default: "Bitrate"), value: PlaybackStats.bitrateLabel(Int64(stats.audioBitrate ?? 0))),
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
            .init(label: AppLanguage.string("detail.file", default: "File"), value: PlaybackStats.bytesLabel(plan.byteSize ?? 0)),
            .init(label: "Buffer", value: stats.isBuffering ? "Rebuffering" : String(format: "%.1fs ahead", stats.cacheSeconds ?? 0)),
            .init(label: AppLanguage.string("ui.speed", default: "Speed"), value: PlaybackStats.bitrateLabel(Int64((stats.cacheSpeed ?? 0) * 8))),
            .init(label: "Seeking", value: stats.isSeeking ? "Yes" : "No"),
            .init(label: "Live", value: plan.isLive ? "Yes" : "No")
        ]

        return [
            PlaybackStatsSection(title: AppLanguage.string("ui.video", default: "Video"), rows: videoRows),
            PlaybackStatsSection(title: AppLanguage.string("player.audio", default: "Audio"), rows: audioRows),
            PlaybackStatsSection(title: "Decode", rows: decodeRows),
            PlaybackStatsSection(title: AppLanguage.string("settings.network", default: "Network"), rows: networkRows)
        ]
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

    #if !targetEnvironment(macCatalyst)
    private func attachMPVPictureInPicture() {
        guard let mpv else { return }
        mpvPictureInPictureTransport.model = self
        bindPictureInPictureCallbacks()
        pictureInPicture.attach(layer: mpv.displayLayer, transport: mpvPictureInPictureTransport)
        canUsePictureInPicture = pictureInPicture.canStart || isPictureInPictureActive
    }
    #endif

    private func bindPictureInPictureCallbacks() {
        pictureInPicture.onPossibleChange = { [weak self] possible in
            self?.canUsePictureInPicture = possible
        }
        pictureInPicture.onActiveChange = { [weak self] active in
            self?.handlePictureInPictureActiveChange(active)
        }
    }

    private func installResignActivePiPArming() {
        guard resignActiveObserver == nil else { return }
        // Only observe when auto-PiP is enabled — avoids any resign-active start path when off.
        guard PlaybackPreferences.autoPictureInPictureOnLeave else { return }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.startPictureInPictureIfPossible()
            }
        }
    }

    private func handlePictureInPictureActiveChange(_ active: Bool) {
        if active {
            return
        }
        guard stopWhenPictureInPictureEnds else { return }
        stopWhenPictureInPictureEnds = false
        Task { await stop() }
    }

    private static func makeNativePlayer(
        url: URL,
        extraHeaders: [String: String] = [:],
        item media: MediaItem
    ) -> AVPlayer {
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
        AirPlayExternalMetadata.apply(to: item, item: media)
        let player = AVPlayer(playerItem: item)
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.appliesMediaSelectionCriteriaAutomatically = true
        return player
    }
}

#if !targetEnvironment(macCatalyst)
/// Bridges MPV playhead / pause / seek into `AVPictureInPictureSampleBufferPlaybackDelegate`.
@MainActor
final class MPVPictureInPictureTransport: SampleBufferPiPTransport {
    weak var model: PlayerModel?

    var isPaused: Bool { model?.isPaused ?? true }

    func setPlaying(_ playing: Bool) {
        guard let model else { return }
        if playing == model.isPaused {
            model.togglePlayPause()
        }
    }

    func skip(by seconds: Double) {
        model?.skip(by: seconds)
    }

    func timeRange() -> CMTimeRange {
        guard let model else {
            return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        }
        let duration = model.duration
        if duration > 0, duration.isFinite {
            return CMTimeRange(
                start: .zero,
                duration: CMTime(seconds: duration, preferredTimescale: 600)
            )
        }
        return CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
    }
}
#endif

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
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

/// Keeps the screen on, and on the Mac the computer awake, while something plays. mpv draws its own
/// frames, so the system can't tell video is on the way AVPlayer's can.
final class PlaybackWakeLock {
    private var activity: NSObjectProtocol?
    private var isHeld = false

    @MainActor
    func hold(_ held: Bool) {
        guard held != isHeld else { return }
        isHeld = held
        #if targetEnvironment(macCatalyst)
        if held {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .idleDisplaySleepDisabled, .idleSystemSleepDisabled],
                reason: "Playing video"
            )
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        #else
        UIApplication.shared.isIdleTimerDisabled = held
        #endif
    }

    deinit {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        #if !targetEnvironment(macCatalyst)
        if isHeld {
            Task { @MainActor in UIApplication.shared.isIdleTimerDisabled = false }
        }
        #endif
    }
}
