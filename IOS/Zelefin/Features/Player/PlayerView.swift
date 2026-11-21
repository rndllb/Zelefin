import AVFoundation
import AVKit
import GroupActivities
import SwiftUI
import UIKit

struct PlayerView: View {
    let item: MediaItem
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(SharePlayManager.self) private var sharePlay
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var activeItem: MediaItem
    @State private var model: PlayerModel?
    @State private var didFallBackToRemux = false
    @State private var fallbackError: String?
    @State private var playerWasBackgrounded = false
    @State private var subtitleSearchItem: MediaItem?
    @State private var subtitleSearchFileID: String?
    @State private var resumeOverride: TimeInterval?
    @State private var appliedBitrate: Int?
    @State private var liveBitrateOverride: Int?
    @State private var cinemaQueue: [MediaItem] = []
    @State private var cinemaIndex = 0
    @State private var presentationSettled = false
    @State private var didRetryStart = false
    @State private var isOnScreen = true
    @State private var autoAdvancedEpisodeCount = 0
    @State private var showsStillWatchingPrompt = false
    @State private var isLeavingPlayback = false
    @State private var alertPresence = PlaybackPresence()
    @State private var airPlayRouteBridge = AirPlayRouteBridge()
    @State private var castRouteBridge = CastRouteBridge()
    @State private var isPreparingAirPlayRelay = false
    @State private var isPreparingCast = false
    @State private var showsSyncPlaySheet = false

    /// Roughly the full-screen / zoom presentation. Building the video surface or unlocking
    /// rotation before it ends stalls the animation part way up the screen.
    private static let presentationDuration: Duration = .milliseconds(450)

    init(item: MediaItem) {
        self.item = item
        _activeItem = State(initialValue: item)
    }

    /// Spinner and close stay on top until the first frame, so a slow server never leaves
    /// a black screen with auto-hidden controls.
    private var showsLoadingOverlay: Bool {
        guard fallbackError == nil else { return false }
        guard let model else { return true }
        return !model.hasFirstFrame && model.errorMessage == nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            #if !targetEnvironment(macCatalyst)
            // Under MPV: full-size AVPlayerLayer so AirPlay routes video (not audio-only).
            if let relay = model?.airPlayRelay {
                AirPlayRelayLayerHost(player: relay)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            #endif
            if let model {
                playerSurface(model)
            }
            if showsLoadingOverlay {
                loadingSurface
                    .transition(.opacity)
            }
            if let message = fallbackError {
                errorOverlay(message)
            }
            if showsStillWatchingPrompt {
                stillWatchingOverlay
            }
            #if !targetEnvironment(macCatalyst)
            AirPlayRoutePickerHost(bridge: airPlayRouteBridge)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if CastManager.shared.isCastAvailable {
                CastRoutePickerHost(bridge: castRouteBridge)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.2), value: showsLoadingOverlay)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            try? await Task.sleep(for: Self.presentationDuration)
            guard !Task.isCancelled else { return }
            presentationSettled = true
            InterfaceOrientationLock.setPhoneLandscapeAllowed(true)
        }
        .task {
            session.rememberNowPlaying(activeItem)
            #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
            // Clear downloads/SyncPlay/etc. so sample-buffer PiP can become possible.
            await ZelefinLiveActivityController.shared.endAllActivities()
            #endif
            Task { await PlaybackAudioSession.activate() }
            await prepareAndStart()
        }
        .task(id: liveAdaptiveMonitorID) {
            await monitorLiveAdaptive()
        }
        .onAppear {
            LibraryAlertSettings.beginPlaybackPresence(alertPresence)
            sharePlay.playerOpened(activeItem)
        }
        .onDisappear {
            isOnScreen = false
            sharePlay.playerClosed(activeItem.id)
            LibraryAlertSettings.endPlaybackPresence(alertPresence)
            InterfaceOrientationLock.setPhoneLandscapeAllowed(false)
            if let time = model?.currentTime {
                session.updateNowPlayingPosition(time)
            }
            if model == nil {
                PlaybackAudioSession.deactivate()
            }
            model?.markPlaybackViewDismissed()
        }
        .onChange(of: activeItem) { _, item in
            session.rememberNowPlaying(item)
            sharePlay.playerOpened(item)
        }
        .playerCastSharePlay(
            sharePlay: sharePlay,
            activeItem: activeItem,
            model: model,
            onHelloReply: { _ in
                sharePlay.send(
                    model?.isPaused == false ? .play : .pause,
                    itemId: activeItem.id,
                    positionSeconds: model?.currentTime ?? 0,
                    rate: model?.playbackRate ?? 1
                )
            },
            onFollowItem: { id in
                Task { await followSharePlay(to: id) }
            },
            onCastConnected: {
                Task { await startCasting() }
            },
            onCastDisconnected: {
                model?.resumeLocalPlaybackAfterCast()
            },
            onCastFinished: {
                Task { await advanceOrDismiss() }
            }
        )
        .onChange(of: model?.isFinished) { _, finished in
            guard finished == true else { return }
            if model?.plan.isLive == true { return }
            Task { await advanceOrDismiss() }
        }
        .onChange(of: model?.errorMessage) { _, message in
            guard let message else { return }
            ZelefinLog.error("Playback", "The player stopped on \"\(activeItem.name)\": \(message)")
            if model?.hasFirstFrame != true, !didRetryStart {
                didRetryStart = true
                Task { await retryStart() }
                return
            }
            guard !didFallBackToRemux, let plan = model?.plan, plan.method == .directPlay else {
                fallbackError = message
                return
            }
            if OfflinePlaybackPolicy.shouldFallBackToRemux(isLocalFile: plan.streamURL.isFileURL) {
                Task { await fallBackToRemux(from: message) }
                return
            }
            fallbackError = message
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onChange(of: fallbackError) { _, message in
            if let message {
                ZelefinLog.error("Playback", "Couldn't play \"\(activeItem.name)\": \(message)")
            }
        }
        .onChange(of: session.adaptiveBitrate.path.transport) { previous, _ in
            guard previous != .other else { return }
            liveBitrateOverride = nil
            Task { await retuneAdaptiveBitrate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteStopPlayback)) { _ in
            Task { await leavePlayback(preferPictureInPicture: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteNextTrack)) { _ in
            Task { await advanceOrDismiss() }
        }
        .openSubtitlesSearch(item: $subtitleSearchItem, mediaSourceID: subtitleSearchFileID)
        .task(id: activeItem.id) {
            guard activeItem.kind == .movie || activeItem.kind == .episode else { return }
            await session.loadVersions(for: activeItem.id)
        }
        .alert(
            "SharePlay",
            isPresented: Binding(
                get: { sharePlay.notice != nil },
                set: { if !$0 { sharePlay.notice = nil } }
            )
        ) {
            Button(AppLanguage.string("common.ok", default: "OK"), role: .cancel) { sharePlay.notice = nil }
        } message: {
            Text(sharePlay.notice ?? "")
        }
        .sheet(isPresented: $showsSyncPlaySheet) {
            SyncPlayPlaySheet(item: activeItem) {
                showsSyncPlaySheet = false
            }
            .environment(session)
            .environment(downloads)
        }
    }

    private var isCinemaBumper: Bool {
        cinemaIndex + 1 < cinemaQueue.count
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            playerWasBackgrounded = true
            if PlaybackPreferences.autoPictureInPictureOnLeave {
                model?.startPictureInPictureIfPossible()
            }
        case .active:
            let pipActive = model?.isPictureInPictureActive ?? false
            guard PlaybackForegroundRecovery.shouldRestore(
                wasBackgrounded: playerWasBackgrounded,
                pictureInPictureActive: pipActive
            ) else { return }
            playerWasBackgrounded = false
            Task { await model?.restoreAfterForeground() }
        default:
            break
        }
    }

    private var loadingClose: some View {
        VStack {
            HStack {
                Button(action: { Task { await leavePlayback(preferPictureInPicture: PlaybackPreferences.autoPictureInPictureOnLeave) } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.string("common.close", default: "Close"))
                Spacer()
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private var loadingSurface: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .accessibilityLabel(AppLanguage.string("player.loading", default: "Loading"))
            loadingClose
        }
    }

    private func waitForPresentation() async {
        while !presentationSettled, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// Plays `activeItem`, which the next-episode advance and the cinema queue move along. Starting
    /// from `item` (what the player opened with) replayed the first episode at every advance.
    private func prepareAndStart() async {
        var target = activeItem
        if target.kind == .series || target.kind == .season {
            do {
                target = try await resolvePlayableItem(target)
                activeItem = target
            } catch {
                fallbackError = error.localizedDescription
                return
            }
        }
        if let local = downloads.playbackPlan(for: target, account: session.session) {
            guard !Task.isCancelled else { return }
            appliedBitrate = nil
            liveBitrateOverride = nil
            await startPlayback(local)
            return
        }
        guard let library = session.library else {
            fallbackError = "Sign in to play this title."
            return
        }
        do {
            var launch = session.launchOptions(for: target.id)
            await measureConnectionIfUnknown(for: launch)
            let maxBitrate = streamingBitrate(for: launch)
            appliedBitrate = maxBitrate
            let featureStart = resumeOverride ?? target.playbackPosition
            let planTask = Task {
                try await library.playbackPlan(
                    for: target,
                    audioIndex: launch.audioIndex,
                    subtitleIndex: launch.subtitleStreamIndex,
                    maxBitrate: maxBitrate,
                    startTime: featureStart,
                    mediaSourceID: launch.mediaSourceID
                )
            }
            let introTask: Task<[MediaItem], Never>? = (cinemaQueue.isEmpty && !launch.skipCinemaIntros)
                ? Task { await library.cinemaIntros(for: target.id) }
                : nil
            var plan: PlaybackPlan
            if isCinemaBumper {
                planTask.cancel()
                plan = try await library.playbackPlan(
                    for: activeItem,
                    allowDirectPlay: true,
                    maxBitrate: maxBitrate,
                    startTime: 0,
                    mediaSourceID: nil
                )
            } else {
                plan = try await planTask.value
                if let introTask, let intros = await finishedIfReady(introTask), !intros.isEmpty {
                    cinemaQueue = intros + [target]
                    cinemaIndex = 0
                    activeItem = intros[0]
                    plan = try await library.playbackPlan(
                        for: activeItem,
                        allowDirectPlay: true,
                        maxBitrate: maxBitrate,
                        startTime: 0,
                        mediaSourceID: nil
                    )
                } else {
                    activeItem = target
                    let remembered = rememberedTracks(for: target, in: plan, launch: launch)
                    if remembered.audio != nil || remembered.subtitle != nil {
                        session.updateLaunchOptions(for: target.id) { options in
                            if let audio = remembered.audio { options.audioIndex = audio }
                            if let subtitle = remembered.subtitle {
                                options.subtitlesDisabled = subtitle == -1
                                options.subtitleIndex = subtitle == -1 ? nil : subtitle
                            }
                        }
                        launch = session.launchOptions(for: target.id)
                        plan = try await library.playbackPlan(
                            for: target,
                            audioIndex: launch.audioIndex,
                            subtitleIndex: launch.subtitleStreamIndex,
                            maxBitrate: maxBitrate,
                            startTime: featureStart,
                            mediaSourceID: launch.mediaSourceID
                        )
                    }
                }
            }
            resumeOverride = nil
            if PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: plan.streamURL,
                method: plan.method,
                container: plan.container,
                videoCodec: plan.videoCodec,
                usesNativePlayer: PlaybackPipelineResolver.prefersNativePlayer(
                    preference: PlaybackPreferences.useNativeVideoPlayer,
                    hasSidecarSubtitles: !plan.externalSubtitles.isEmpty
                )
            ) {
                plan = try await library.playbackPlan(
                    for: activeItem,
                    audioIndex: isCinemaBumper ? nil : launch.audioIndex,
                    subtitleIndex: isCinemaBumper ? nil : launch.subtitleStreamIndex,
                    allowDirectPlay: false,
                    maxBitrate: maxBitrate,
                    startTime: plan.startTime,
                    mediaSourceID: isCinemaBumper ? nil : launch.mediaSourceID
                )
            }
            try Task.checkCancellation()
            await startPlayback(plan)
        } catch is CancellationError {
            return
        } catch {
            fallbackError = error.localizedDescription
        }
    }

    private func resolvePlayableItem(_ item: MediaItem) async throws -> MediaItem {
        let seriesID = item.kind == .season ? (item.seriesID ?? item.id) : item.id
        if let cached = session.homeLayout.episode(forSeriesID: seriesID) {
            return cached
        }
        guard let library = session.library else {
            throw ZelefinError.missingUser
        }
        return try await library.playableItem(for: item)
    }

    /// Takes cinema intros only when they already finished during the playback-plan
    /// request. Waiting on `/Intros` was holding Play behind an extra server round trip.
    private func finishedIfReady<T: Sendable>(_ task: Task<T, Never>) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                await Task.yield()
                return nil
            }
            let value = await group.next() ?? nil
            group.cancelAll()
            return value
        }
    }

    /// Same rule as Android: Auto on a home server Direct Plays immediately. A 750KB
    /// BitrateTest used to run first and hold Play for up to four seconds.
    private func streamingBitrate(for launch: PlaybackLaunchOptions) -> Int {
        if let liveBitrateOverride {
            return liveBitrateOverride
        }
        if launch.resolvedQuality == .auto,
           let host = session.activeServerURL?.host,
           ServerURL.isOnLocalNetwork(host) {
            return PlaybackQuality.auto.bitsPerSecond
        }
        // Off the home network only: the test download competes with the stream's first bytes.
        Task { await session.adaptiveBitrate.refreshIfNeeded(library: session.library) }
        return session.adaptiveBitrate.resolvedBitsPerSecond(
            sourceBitrate: activeItem.sourceBitrate,
            launch: launch
        )
    }

    private var liveAdaptiveMonitorID: String {
        guard let model else { return "idle" }
        return "\(model.plan.playSessionID ?? "")|\(model.plan.streamURL.absoluteString)"
    }

    private func monitorLiveAdaptive() async {
        guard model != nil else { return }
        if model?.plan.isLive == true { return }
        var tracker = LiveAdaptiveTracker(startedAt: Date())
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard PlaybackPreferences.adaptiveBitrateEnabled else { continue }
            guard let model else { return }
            guard model.plan.streamURL.isFileURL != true else { return }
            let launch = session.launchOptions(for: activeItem.id)
            if let override = launch.quality, override != .auto { return }
            let current = PlaybackQuality.atOrBelow(appliedBitrate ?? launch.resolvedQuality.bitsPerSecond)
            let sample = LiveAdaptiveSample(
                hasFirstFrame: model.hasFirstFrame,
                isPaused: model.isPaused,
                isSeeking: model.isSeeking,
                isRebuffering: model.isRebuffering,
                bufferedAhead: model.bufferedAheadSeconds,
                current: current,
                ceiling: PlaybackPreferences.selectedQuality,
                sourceBitsPerSecond: activeItem.sourceBitrate
            )
            switch tracker.action(now: Date(), sample: sample) {
            case .none:
                break
            case .stepDown:
                if let next = PlaybackQuality.stepDown(
                    from: current,
                    sourceBitsPerSecond: activeItem.sourceBitrate
                ) {
                    await applyLiveAdaptive(next)
                    return
                }
            case .stepUp:
                if let next = PlaybackQuality.stepUp(
                    from: current,
                    sourceBitsPerSecond: activeItem.sourceBitrate,
                    ceiling: PlaybackPreferences.selectedQuality
                ) {
                    await applyLiveAdaptive(next)
                    return
                }
            }
        }
    }

    private func applyLiveAdaptive(_ quality: PlaybackQuality) async {
        guard model?.plan.streamURL.isFileURL != true else { return }
        liveBitrateOverride = quality.bitsPerSecond
        appliedBitrate = quality.bitsPerSecond
        let skip = model?.skipSegments ?? []
        resumeOverride = model?.currentTime
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        await prepareAndStart()
        if let created = model, created.skipSegments.isEmpty {
            created.skipSegments = skip
        }
    }

    /// Off the home network with no recent sample, measure before choosing Direct Play: the path
    /// estimate trusts any Wi-Fi, and a phone hotspot reads as Wi-Fi. Measuring alongside the start
    /// could only correct the next play. Costs at most the 4s probe timeout, once per network every 90s.
    private func measureConnectionIfUnknown(for launch: PlaybackLaunchOptions) async {
        guard PlaybackPreferences.adaptiveBitrateEnabled, liveBitrateOverride == nil else { return }
        guard launch.resolvedQuality == .auto else { return }
        if let host = session.activeServerURL?.host, ServerURL.isOnLocalNetwork(host) { return }
        await session.adaptiveBitrate.refreshIfNeeded(library: session.library)
    }

    private func retuneAdaptiveBitrate() async {
        guard PlaybackPreferences.adaptiveBitrateEnabled else { return }
        guard model != nil, model?.plan.isLive != true else { return }
        guard model?.plan.streamURL.isFileURL != true else { return }
        let launch = session.launchOptions(for: activeItem.id)
        if let override = launch.quality, override != .auto { return }
        let next = streamingBitrate(for: launch)
        let previous = appliedBitrate ?? launch.resolvedQuality.bitsPerSecond
        guard PlaybackQuality.atOrBelow(next) != PlaybackQuality.atOrBelow(previous) else { return }
        let skip = model?.skipSegments ?? []
        resumeOverride = model?.currentTime
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        await prepareAndStart()
        if let created = model, created.skipSegments.isEmpty {
            created.skipSegments = skip
        }
    }

    private func startPlayback(
        _ plan: PlaybackPlan,
        skipSegments: [SkipSegment]? = nil,
        pipelineOverride: PlaybackPipeline? = nil
    ) async {
        await waitForPresentation()
        // Restarts run in unstructured tasks that outlive the view; never start after close.
        guard !Task.isCancelled, isOnScreen else { return }
        ZelefinLog.info("Playback", Self.logLine(for: plan))
        let reporter = session.makePlaybackReporter(for: plan)
        let created = PlayerModel(plan: plan, reporter: reporter, pipelineOverride: pipelineOverride)
        created.syncPlayGroupNameForRestore = { [session] in
            guard session.syncPlayGroupID != nil else { return nil }
            return session.syncPlayGroupName
        }
        created.onUserTransport = { [sharePlay] action in
            Task { await session.forwardSyncPlay(action) }
            Self.forwardSharePlay(action, itemID: plan.item.id, sharePlay: sharePlay, model: created)
        }
        created.onPlaybackRateChange = { [sharePlay] rate in
            guard sharePlay.isActive else { return }
            sharePlay.send(
                .rate,
                itemId: plan.item.id,
                positionSeconds: created.currentTime,
                rate: rate
            )
        }
        created.onRemoteSeekApplied = { time in
            Task {
                try? await session.library?.syncPlayReady(
                    isPlaying: true,
                    playlistItemID: session.syncPlayPlaylistItemID,
                    position: time
                )
            }
        }
        created.onDidStart = {
            session.noteHomeQueueResumed(plan.item.id)
        }
        if let skipSegments {
            created.skipSegments = skipSegments
        } else if created.plan.isLive != true,
           OfflinePlaybackPolicy.shouldFetchSkipSegments(isLocalFile: plan.streamURL.isFileURL) {
            created.skipSegments = plan.skipSegments
            let client = session.client
            let library = session.library
            Task {
                var segments = plan.skipSegments
                if segments.isEmpty, let client {
                    // Checking `/Plugins` first left every non-administrator without skip markers:
                    // that list is admin-only, so Intro Skipper always looked missing to them.
                    segments = await IntroSkipperClient(client: client).segments(for: plan.item.id)
                }
                if PlaybackPreferences.usesTheIntroDB, !TheIntroDB.coversEveryKind(segments), let library {
                    segments = TheIntroDB.filling(segments, from: await TheIntroDB.segments(for: plan.item, library: library))
                }
                created.skipSegments = segments
            }
        } else {
            created.skipSegments = plan.skipSegments
        }
        model = created
        await Task.yield()
        do {
            try Task.checkCancellation()
            await created.start()
            if session.syncPlayGroupID != nil {
                try? await session.library?.syncPlayReady(
                    isPlaying: true,
                    playlistItemID: session.syncPlayPlaylistItemID,
                    position: plan.startTime
                )
            }
        } catch is CancellationError {
            await created.stop()
        } catch {
            fallbackError = error.localizedDescription
        }
    }

    private func advanceOrDismiss() async {
        if cinemaIndex + 1 < cinemaQueue.count {
            cinemaIndex += 1
            await model?.stop()
            model = nil
            didFallBackToRemux = false
            fallbackError = nil
            activeItem = cinemaQueue[cinemaIndex]
            liveBitrateOverride = nil
            appliedBitrate = nil
            resumeOverride = cinemaIndex == cinemaQueue.count - 1 ? item.playbackPosition : 0
            await prepareAndStart()
            return
        }
        cinemaQueue = []
        cinemaIndex = 0
        if model?.sleepAtEndOfEpisode == true {
            await leavePlayback(preferPictureInPicture: false)
            return
        }
        guard PlaybackPreferences.autoPlayNextEpisode else {
            await leavePlayback(preferPictureInPicture: false)
            return
        }
        if shouldAskStillWatching {
            if model?.isPaused == false {
                model?.togglePlayPause()
            }
            showsStillWatchingPrompt = true
            return
        }
        if await !playNextEpisode(countsTowardStillWatching: true) {
            await leavePlayback(preferPictureInPicture: false)
        }
    }

    private var shouldAskStillWatching: Bool {
        PlaybackPreferences.askStillWatching
            && activeItem.kind == .episode
            && autoAdvancedEpisodeCount >= PlaybackPreferences.stillWatchingEpisodeThreshold
    }

    /// Moves on to the episode after this one. False when there isn't one.
    @discardableResult
    private func playNextEpisode(countsTowardStillWatching: Bool) async -> Bool {
        guard let library = session.library,
              let next = await library.nextEpisode(after: activeItem)
        else { return false }
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        activeItem = next
        liveBitrateOverride = nil
        appliedBitrate = nil
        if countsTowardStillWatching {
            autoAdvancedEpisodeCount += 1
        }
        await prepareAndStart()
        return true
    }

    private func continueAfterStillWatching() async {
        showsStillWatchingPrompt = false
        autoAdvancedEpisodeCount = 0
        if await !playNextEpisode(countsTowardStillWatching: true) {
            await leavePlayback(preferPictureInPicture: false)
        }
    }

    private func stopAfterStillWatching() async {
        showsStillWatchingPrompt = false
        autoAdvancedEpisodeCount = 0
        await leavePlayback(preferPictureInPicture: false)
    }

    /// Close / dismiss. Prefer PiP when the user leaves while something is still playing.
    private func leavePlayback(preferPictureInPicture: Bool) async {
        guard !isLeavingPlayback else { return }
        isLeavingPlayback = true
        defer { isLeavingPlayback = false }
        showsStillWatchingPrompt = false
        // Always re-read the setting here — don't trust a captured Bool from the button action.
        let wantsPiP = preferPictureInPicture && PlaybackPreferences.autoPictureInPictureOnLeave
        if wantsPiP {
            if let model, await model.leavePreferringPictureInPicture() {
                closePlayer()
                return
            }
            // Native AVPlayer: PiP starts when the VC leaves the screen with auto-inline on.
            model?.prepareNativeLeaveIntoPictureInPicture()
            closePlayer()
            return
        }
        // Stop first so AVKit has nothing left to promote into a PiP window on dismiss.
        model?.suppressAutomaticPictureInPicture()
        await model?.stop()
        closePlayer()
    }

    /// Mac hosts the player in the window overlay, so closing clears that item.
    /// iPhone and iPad dismiss the full-screen cover.
    private func closePlayer() {
        #if targetEnvironment(macCatalyst)
        session.pendingPlayerItem = nil
        #else
        dismiss()
        #endif
    }

    private var stillWatchingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 20) {
                Text(AppLanguage.string("player.still_watching", default: "Are you still watching?"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(String(format: AppLanguage.string("player.still_watching_body", default: "You’ve auto-played %d episodes."), PlaybackPreferences.stillWatchingEpisodeThreshold))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Button {
                        Task { await stopAfterStillWatching() }
                    } label: {
                        Text(AppLanguage.string("player.stop", default: "Stop"))
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    Button {
                        Task { await continueAfterStillWatching() }
                    } label: {
                        Text(AppLanguage.string("common.continue", default: "Continue"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.white, in: Capsule())
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(28)
        }
        .allowsHitTesting(true)
    }

    /// The first open after a cold start can fail while the server spins up; a reopen works.
    /// `Playing "Dune" (movie) by directPlay: mkv, hevc, dolbyVision, from a download, at 0:00`
    private static func logLine(for plan: PlaybackPlan) -> String {
        let source = plan.streamURL.isFileURL ? "a download" : (plan.streamURL.host ?? "the server")
        let facts = [plan.container, plan.videoCodec, String(describing: plan.videoRange), String(describing: plan.audioFormat)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let version = plan.versions.count > 1 ? ", version \(plan.mediaSourceID ?? "default") of \(plan.versions.count)" : ""
        return "Playing \"\(plan.item.name)\" (\(plan.item.kind)) by \(plan.method): \(facts), from \(source), at \(PlaybackTimeFormatting.elapsed(plan.startTime))\(version)"
    }

    private func retryStart() async {
        ZelefinLog.warning("Playback", "Starting again: the first try never showed a picture")
        let skip = model?.skipSegments ?? []
        resumeOverride = model.map(\.currentTime).flatMap { $0 > 0 ? $0 : nil }
        await model?.stop()
        model = nil
        fallbackError = nil
        await prepareAndStart()
        if let created = model, created.skipSegments.isEmpty {
            created.skipSegments = skip
        }
    }

    private func fallBackToRemux(from message: String) async {
        guard !didFallBackToRemux else { return }
        didFallBackToRemux = true
        ZelefinLog.warning("Playback", "Direct Play failed (\(message)); asking the server to remux instead")
        let skip = model?.skipSegments ?? []
        await model?.stop()
        model = nil
        fallbackError = nil
        guard let library = session.library else {
            fallbackError = message
            return
        }
        do {
            try Task.checkCancellation()
            let launch = session.launchOptions(for: activeItem.id)
            let remux = try await library.playbackPlan(
                for: activeItem,
                allowDirectPlay: false,
                maxBitrate: streamingBitrate(for: launch),
                startTime: resumeOverride ?? activeItem.playbackPosition,
                mediaSourceID: isCinemaBumper ? nil : launch.mediaSourceID
            )
            try Task.checkCancellation()
            await startPlayback(remux, skipSegments: skip)
        } catch is CancellationError {
            return
        } catch {
            fallbackError = error.localizedDescription
        }
    }

    private func changeQuality(_ quality: PlaybackQuality) async {
        let current = session.launchOptions(for: activeItem.id).resolvedQuality
        session.updateLaunchOptions(for: activeItem.id) { $0.quality = quality }
        liveBitrateOverride = nil
        guard quality != current else { return }
        guard model?.plan.streamURL.isFileURL != true else { return }
        let skip = model?.skipSegments ?? []
        resumeOverride = model?.currentTime
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        await prepareAndStart()
        if let created = model, created.skipSegments.isEmpty {
            created.skipSegments = skip
        }
    }

    /// Picks up from the same moment on the other file, with the new version's default tracks.
    private func changeVersion(_ versionID: String) async {
        guard versionID != model?.plan.mediaSourceID else { return }
        session.chooseVersion(versionID, for: activeItem.id)
        guard !isCinemaBumper, model?.plan.streamURL.isFileURL != true else { return }
        let skip = model?.skipSegments ?? []
        resumeOverride = model?.currentTime
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        await prepareAndStart()
        if let created = model, created.skipSegments.isEmpty {
            created.skipSegments = skip
        }
    }

    private var playerVersions: [MediaVersion] {
        guard !isCinemaBumper else { return [] }
        return session.mediaVersions[activeItem.id] ?? []
    }

    @ViewBuilder
    private func playerSurface(_ model: PlayerModel) -> some View {
        if let mpv = model.mpv {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                MPVVideoSurface(
                    layer: mpv.displayLayer,
                    pictureSize: model.pictureSize,
                    fillsScreen: model.fillsScreen,
                    onBound: { model.noteSurfaceReady() },
                    onLayerAttached: { model.syncPictureInPicture() },
                    onResizeSettled: { frame, size in
                        model.setMPVSurfaceFrame(frame)
                        mpv.noteSurfaceSize(size)
                    }
                )
                .ignoresSafeArea()
                if model.isCastingExternally {
                    castingPlaceholder
                } else if model.isAirPlayingExternally {
                    Color.black.opacity(0.72).ignoresSafeArea()
                    VStack(spacing: 10) {
                        Image(systemName: "airplayvideo")
                            .font(.system(size: 36, weight: .semibold))
                        Text(AppLanguage.string("player.airplaying", default: "AirPlaying"))
                            .font(.title3.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .allowsHitTesting(false)
                }
                playerChrome(model)
                if model.showsPlaybackStats {
                    PlaybackStatsOverlay(snapshot: model.playbackStats)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let player = model.player {
            NativePlayerContainer(
                player: player,
                surfaceGeneration: model.surfaceGeneration,
                skipTitle: isCinemaBumper ? "Skip" : model.skipPrompt?.title,
                allowsAutomaticPictureInPicture: PlaybackPreferences.autoPictureInPictureOnLeave,
                onSkip: {
                    if isCinemaBumper {
                        Task { await advanceOrDismiss() }
                    } else {
                        model.skipCurrentSegment()
                    }
                },
                onPictureInPictureActive: { model.setNativePictureInPictureActive($0) },
                onControllerReady: { controller in
                    model.applyNativeAutomaticPictureInPicture = { allowed in
                        controller.canStartPictureInPictureAutomaticallyFromInline = allowed
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
        } else {
            loadingSurface
        }
    }

    /// The audio and subtitle picked on an earlier episode of this show, as this episode's stream indices.
    /// A pick made on this episode itself wins, and nothing changes where the server already matches.
    private func rememberedTracks(for item: MediaItem, in plan: PlaybackPlan, launch: PlaybackLaunchOptions) -> (audio: Int?, subtitle: Int?) {
        guard item.kind == .episode, let seriesID = item.seriesID, let accountID = session.session?.accountID,
              launch.audioIndex == nil, launch.subtitleIndex == nil, !launch.subtitlesDisabled,
              let memory = SeriesTrackMemory.saved(accountID: accountID, seriesID: seriesID) else { return (nil, nil) }
        return memory.indices(in: plan)
    }

    private func rememberForShow(_ mutate: (inout SeriesTrackMemory) -> Void) {
        guard activeItem.kind == .episode, !isCinemaBumper,
              let seriesID = activeItem.seriesID, let accountID = session.session?.accountID else { return }
        SeriesTrackMemory.update(accountID: accountID, seriesID: seriesID, mutate)
    }

    /// Zelefin's controls and track menus for the MPV player.
    private func playerChrome(_ model: PlayerModel) -> some View {
        AVKitPlaybackChrome(
            model: model,
            title: model.plan.item.name,
            quality: session.launchOptions(for: item.id).resolvedQuality,
            canAddSubtitles: !isCinemaBumper && session.shouldShowAddSubtitles(for: activeItem),
            onClose: { Task { await leavePlayback(preferPictureInPicture: PlaybackPreferences.autoPictureInPictureOnLeave) } },
            onQualityChange: { quality in
                Task { await changeQuality(quality) }
            },
            versions: playerVersions,
            selectedVersionID: model.plan.mediaSourceID ?? session.launchOptions(for: activeItem.id).mediaSourceID,
            onVersionChange: { versionID in
                Task { await changeVersion(versionID) }
            },
            onAddSubtitles: {
                subtitleSearchFileID = model.plan.mediaSourceID
                subtitleSearchItem = activeItem
            },
            onAudioChange: { id in
                model.selectAudio(id: id)
                let pick = model.audioPick(id: id)
                session.updateLaunchOptions(for: activeItem.id) { $0.audioIndex = pick.serverIndex }
                rememberForShow { $0.audio = pick.choice ?? $0.audio }
            },
            onSubtitleChange: { id in
                model.selectSubtitle(id: id)
                let pick = id.map(model.subtitlePick(id:))
                session.updateLaunchOptions(for: activeItem.id) { options in
                    options.subtitlesDisabled = id == nil
                    options.subtitleIndex = pick?.serverIndex
                }
                rememberForShow { memory in
                    memory.subtitlesOff = id == nil
                    if let choice = pick?.choice { memory.subtitle = choice }
                }
            },
            onSkipCinema: isCinemaBumper ? { Task { await advanceOrDismiss() } } : nil,
            onNext: activeItem.kind == .episode && !isCinemaBumper
                ? { Task { _ = await playNextEpisode(countsTowardStillWatching: false) } }
                : nil,
            keyboardEnabled: subtitleSearchItem == nil,
            watchTogether: watchTogetherChrome(for: model)
        )
    }

    private func watchTogetherChrome(for model: PlayerModel) -> AVKitWatchTogetherChrome {
        let syncAvailable = !session.lacksJellyfinOnlyFeatures && !isCinemaBumper
        let syncActive = session.syncPlayGroupID != nil
        let syncTitle: String? = {
            guard syncAvailable else { return nil }
            if syncActive {
                let name = session.syncPlayGroupName?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let name, !name.isEmpty {
                    return "Leave SyncPlay (\(name))"
                }
                return "Leave SyncPlay"
            }
            return "SyncPlay"
        }()
        #if targetEnvironment(macCatalyst)
        let airPlay: (() -> Void)? = nil
        let cast: (() -> Void)? = nil
        #else
        let airPlay: (() -> Void)? = { Task { await presentAirPlayPicker() } }
        let cast: (() -> Void)? = CastManager.shared.isCastAvailable
            ? { castRouteBridge.presentPicker() }
            : nil
        #endif
        return AVKitWatchTogetherChrome(
            onAirPlay: airPlay,
            onCast: cast,
            isCastConnected: CastManager.shared.isConnected,
            castDeviceName: CastManager.shared.deviceName,
            isAirPlaying: model.isAirPlayingExternally,
            sharePlay: AVKitSharePlayChrome(
                isActive: sharePlay.isActive,
                title: sharePlay.isActive
                    ? (sharePlay.participantCount > 1
                        ? "Leave SharePlay (\(sharePlay.participantCount))"
                        : "Leave SharePlay")
                    : "SharePlay",
                onStart: { sharePlay.start(activeItem) },
                onLeave: { sharePlay.leave() }
            ),
            syncPlayTitle: syncTitle,
            syncPlayIsActive: syncActive,
            onSyncPlay: syncAvailable
                ? {
                    if syncActive {
                        Task { try? await session.leaveSyncPlayGroup() }
                    } else {
                        showsSyncPlaySheet = true
                    }
                }
                : nil
        )
    }

    private var castingPlaceholder: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.system(size: 40, weight: .semibold))
                Text("Casting to \(CastManager.shared.deviceName ?? "TV")")
                    .font(.title3.weight(.semibold))
                Text(activeItem.name)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
        }
    }

    private static func forwardSharePlay(
        _ action: RemotePlaybackAction,
        itemID: String,
        sharePlay: SharePlayManager,
        model: PlayerModel
    ) {
        guard sharePlay.isActive else { return }
        let rate = model.playbackRate
        switch action {
        case .play:
            sharePlay.send(.play, itemId: itemID, positionSeconds: model.currentTime, rate: rate)
        case .pause:
            sharePlay.send(.pause, itemId: itemID, positionSeconds: model.currentTime, rate: rate)
        case .playPause:
            sharePlay.send(
                model.isPaused ? .pause : .play,
                itemId: itemID,
                positionSeconds: model.currentTime,
                rate: rate
            )
        case .seek(let time):
            sharePlay.send(.seek, itemId: itemID, positionSeconds: time, rate: rate)
        case .stop, .skip, .next, .previous, .mute, .unmute, .volumeUp, .volumeDown:
            break
        }
    }

    private func followSharePlay(to itemID: String) async {
        guard let library = session.library else { return }
        guard let next = try? await library.item(id: itemID) else { return }
        activeItem = next
        resumeOverride = nil
        await model?.stop()
        model = nil
        await prepareAndStart()
    }

    private func startCasting() async {
        guard let model else { return }
        guard !isPreparingCast else { return }
        isPreparingCast = true
        defer { isPreparingCast = false }
        model.beginCastingExternally()
        if CastManager.shared.nowPlayingItemID == activeItem.id {
            return
        }
        do {
            let plan = try await castPlaybackPlan(from: model)
            let poster = session.library?.primaryURL(for: activeItem, maxHeight: 720)
            let subtitleTracks = plan.externalSubtitles.map { track in
                CastManager.SubtitleTrack(
                    id: track.streamIndex,
                    url: track.url,
                    languageCode: track.language,
                    name: track.name
                )
            }
            let activeSubtitle = model.selectedSubtitleID.flatMap { id in
                let serverIndex = model.subtitlePick(id: id).serverIndex
                return subtitleTracks.contains(where: { $0.id == serverIndex || $0.id == id })
                    ? (serverIndex ?? id)
                    : nil
            }
            CastManager.shared.loadMedia(
                itemID: activeItem.id,
                streamURL: plan.streamURL,
                title: activeItem.name,
                subtitle: activeItem.seriesName,
                posterImageURL: poster,
                contentType: CastManager.contentType(for: plan.streamURL, container: plan.container),
                startPositionSeconds: model.currentTime,
                subtitleTracks: subtitleTracks,
                activeSubtitleTrackID: activeSubtitle,
                isTransportStreamHLS: CastManager.isTransportStreamHLS(plan.streamURL),
                isLive: plan.isLive
            )
        } catch {
            fallbackError = error.localizedDescription
            CastManager.shared.endSession()
        }
    }

    private func castPlaybackPlan(from model: PlayerModel) async throws -> PlaybackPlan {
        syncLaunchTracksForAirPlay(from: model)
        guard let library = session.library else {
            throw ZelefinError.missingUser
        }
        let launch = session.launchOptions(for: activeItem.id)
        // Chromecast Default Media Receiver needs a remux/transcode it can open (HLS/MP4).
        return try await library.playbackPlan(
            for: activeItem,
            audioIndex: isCinemaBumper ? nil : launch.audioIndex,
            subtitleIndex: isCinemaBumper ? nil : launch.subtitleStreamIndex,
            allowDirectPlay: false,
            maxBitrate: streamingBitrate(for: launch),
            startTime: model.currentTime,
            mediaSourceID: isCinemaBumper ? nil : launch.mediaSourceID
        )
    }

    /// ArcFin-style: keep MPV on screen, route a companion AVPlayer through the system picker.
    private func presentAirPlayPicker() async {
        guard let model else { return }
        if model.pipeline == .appleNative, let player = model.player {
            // Native path already is an AVPlayer — just open the sheet.
            _ = player
            airPlayRouteBridge.presentPicker()
            return
        }
        guard model.pipeline == .mpv else { return }
        if model.airPlayRelay == nil {
            guard !isPreparingAirPlayRelay else { return }
            isPreparingAirPlayRelay = true
            defer { isPreparingAirPlayRelay = false }
            do {
                let relayPlan = try await airPlayRelayPlan(from: model)
                model.installAirPlayRelay(
                    url: relayPlan.streamURL,
                    extraHeaders: relayPlan.extraHTTPHeaders
                )
                // Let SwiftUI mount the full-size relay layer before we warm/play it.
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(100))
            } catch {
                fallbackError = error.localizedDescription
                return
            }
        }
        await model.prepareAirPlayRelayForPresentation()
        airPlayRouteBridge.presentPicker()
        // If the sheet is cancelled, tear down the warm remux so local playback doesn't buffer forever.
        model.scheduleAirPlayRelayParkIfUnused()
    }

    /// Same stream when AVPlayer can open it; otherwise a remux with the current audio/subs.
    private func airPlayRelayPlan(from model: PlayerModel) async throws -> PlaybackPlan {
        syncLaunchTracksForAirPlay(from: model)
        let selectedSubtitleID = model.selectedSubtitleID
        let plan = model.plan
        let containerNeedsRemux = PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
            url: plan.streamURL,
            method: plan.method,
            container: plan.container,
            videoCodec: plan.videoCodec,
            usesNativePlayer: true
        )
        guard AirPlayHandoffPolicy.needsServerRemux(
            containerNeedsRemux: containerNeedsRemux,
            selectedSubtitleID: selectedSubtitleID
        ) else {
            return plan
        }
        guard let library = session.library else {
            throw ZelefinError.missingUser
        }
        let launch = session.launchOptions(for: activeItem.id)
        return try await library.playbackPlan(
            for: activeItem,
            audioIndex: isCinemaBumper ? nil : launch.audioIndex,
            subtitleIndex: isCinemaBumper ? nil : launch.subtitleStreamIndex,
            allowDirectPlay: false,
            maxBitrate: streamingBitrate(for: launch),
            startTime: model.currentTime,
            mediaSourceID: isCinemaBumper ? nil : launch.mediaSourceID
        )
    }

    private func syncLaunchTracksForAirPlay(from model: PlayerModel) {
        guard !isCinemaBumper else { return }
        if let audioID = model.selectedAudioID {
            let pick = model.audioPick(id: audioID)
            session.updateLaunchOptions(for: activeItem.id) { options in
                if let index = pick.serverIndex {
                    options.audioIndex = index
                }
            }
        }
        if let subtitleID = model.selectedSubtitleID {
            let pick = model.subtitlePick(id: subtitleID)
            session.updateLaunchOptions(for: activeItem.id) { options in
                options.subtitlesDisabled = false
                if let index = pick.serverIndex {
                    options.subtitleIndex = index
                }
            }
        } else {
            session.updateLaunchOptions(for: activeItem.id) { options in
                options.subtitlesDisabled = true
                options.subtitleIndex = nil
            }
        }
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(AppLanguage.string("player.playback_failed", default: "Playback failed"))
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button { Task { await leavePlayback(preferPictureInPicture: false) } } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLanguage.string("common.close", default: "Close"))
        }
        .padding(24)
        .frame(maxWidth: 480)
    }
}

/// Hosts the layer mpv's vo_avfoundation paints into.
private struct MPVVideoSurface: UIViewRepresentable {
    let layer: MPVVideoLayer
    var pictureSize: CGSize = .zero
    var fillsScreen = false
    var onBound: () -> Void
    var onLayerAttached: () -> Void = {}
    /// Window coordinates of the picture, and its size, after the window has stopped moving.
    var onResizeSettled: (CGRect, CGSize) -> Void = { _, _ in }

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .black
        #if targetEnvironment(macCatalyst)
        view.clipsToBounds = true
        #endif
        view.onAttached = onLayerAttached
        view.onResizeSettled = onResizeSettled
        view.pictureSize = pictureSize
        view.fillsScreen = fillsScreen
        view.host(layer)
        view.pinPicture(to: view.bounds.size)
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {
        let pictureChanged = uiView.pictureSize != pictureSize || uiView.fillsScreen != fillsScreen
        uiView.onAttached = onLayerAttached
        uiView.onResizeSettled = onResizeSettled
        uiView.pictureSize = pictureSize
        uiView.fillsScreen = fillsScreen
        uiView.host(layer)
        if pictureChanged {
            uiView.pinPicture(to: uiView.bounds.size, force: true)
        }
        if !context.coordinator.didBind {
            context.coordinator.didBind = true
            onBound()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var didBind = false
    }

    final class LayerHostView: UIView {
        /// Scales the already-drawn frame. The Metal layer is a child and is not resized during the drag.
        private let scaler = CALayer()
        private weak var hosted: CALayer?
        var onAttached: () -> Void = {}
        var onResizeSettled: (CGRect, CGSize) -> Void = { _, _ in }
        var pictureSize: CGSize = .zero
        var fillsScreen = false
        private var pinnedSize: CGSize = .zero
        private var settleWork: DispatchWorkItem?
        private var hasReportedFit = false
        private var isPinning = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            scaler.name = LayerHostScaleName
            scaler.anchorPoint = .zero
            layer.addSublayer(scaler)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: CGSize {
            CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
        }

        override var bounds: CGRect {
            didSet {
                guard abs(oldValue.width - bounds.width) > 0.5 || abs(oldValue.height - bounds.height) > 0.5 else { return }
                pinPicture(to: bounds.size)
            }
        }

        func host(_ layer: CALayer) {
            guard hosted !== layer else { return }
            hosted?.removeFromSuperlayer()
            layer.magnificationFilter = .linear
            scaler.addSublayer(layer)
            hosted = layer
            DispatchQueue.main.async { [weak self] in
                self?.onAttached()
            }
        }

        func pinPicture(to size: CGSize, force: Bool = false) {
            guard !isPinning, let hosted, size.width > 1, size.height > 1 else { return }
            guard force || abs(size.width - pinnedSize.width) > 0.5 || abs(size.height - pinnedSize.height) > 0.5 else { return }
            isPinning = true
            defer { isPinning = false }
            pinnedSize = size
            let base = hosted.bounds.size
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if base.width < 2 || base.height < 2 || !usesLiveScale {
                let scale = max(traitCollection.displayScale, 1)
                let next = CGRect(origin: .zero, size: size)
                hosted.anchorPoint = .zero
                hosted.transform = CATransform3DIdentity
                hosted.frame = next
                hosted.contentsScale = scale
                scaler.transform = CATransform3DIdentity
                scaler.frame = next
            } else if abs(base.width - size.width) < 0.5, abs(base.height - size.height) < 0.5 {
                scaler.transform = CATransform3DIdentity
                scaler.anchorPoint = .zero
                scaler.frame = CGRect(origin: .zero, size: size)
                hosted.anchorPoint = .zero
                hosted.transform = CATransform3DIdentity
                hosted.frame = CGRect(origin: .zero, size: size)
            } else {
                // Scale the wrapper only. Touching the Metal layer here stalls the drag and
                // makes MoltenVK redraw the old frame into the corner.
                let placement = Self.placement(from: base, to: size, picture: pictureSize, fills: fillsScreen)
                scaler.anchorPoint = .zero
                scaler.bounds = CGRect(origin: .zero, size: base)
                scaler.position = placement.position
                scaler.transform = CATransform3DMakeScale(placement.scaleX, placement.scaleY, 1)
            }
            CATransaction.commit()
            scheduleSettle()
        }

        /// The drag only scales a wrapper layer. mpv is told about the new size once the window
        /// has stayed still, so a live resize does not rebuild the video output.
        private func scheduleSettle() {
            settleWork?.cancel()
            if !hasReportedFit {
                hasReportedFit = true
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.bounds.width > 1, self.bounds.height > 1 else { return }
                    self.onResizeSettled(self.convert(self.bounds, to: nil), self.bounds.size)
                }
                return
            }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.bounds.width > 1, self.bounds.height > 1 else { return }
                self.onResizeSettled(self.convert(self.bounds, to: nil), self.bounds.size)
            }
            settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: work)
        }

        private var usesLiveScale: Bool {
            #if targetEnvironment(macCatalyst)
            true
            #else
            false
            #endif
        }

        /// Maps the picture mpv already drew into `from` onto the picture rect of `to`.
        /// The layer's baked-in black bars fall outside the view and get clipped.
        private static func placement(from: CGSize, to: CGSize, picture: CGSize, fills: Bool) -> (scaleX: CGFloat, scaleY: CGFloat, position: CGPoint) {
            guard picture.width > 1, picture.height > 1 else {
                let scale = min(to.width / from.width, to.height / from.height)
                let fitted = CGSize(width: from.width * scale, height: from.height * scale)
                return (
                    scale,
                    scale,
                    CGPoint(x: (to.width - fitted.width) / 2, y: (to.height - fitted.height) / 2)
                )
            }
            let source = DirectPlayPictureLayout.pictureRect(picture: picture, in: from, fill: fills)
            let target = DirectPlayPictureLayout.pictureRect(picture: picture, in: to, fill: fills)
            guard source.width > 1, source.height > 1, target.width > 1, target.height > 1 else {
                let scale = min(to.width / from.width, to.height / from.height)
                let fitted = CGSize(width: from.width * scale, height: from.height * scale)
                return (
                    scale,
                    scale,
                    CGPoint(x: (to.width - fitted.width) / 2, y: (to.height - fitted.height) / 2)
                )
            }
            let scaleX = target.width / source.width
            let scaleY = target.height / source.height
            return (
                scaleX,
                scaleY,
                CGPoint(
                    x: target.minX - source.minX * scaleX,
                    y: target.minY - source.minY * scaleY
                )
            )
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            pinPicture(to: bounds.size)
        }
    }
}

struct NativePlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var surfaceGeneration: Int
    var skipTitle: String?
    var allowsAutomaticPictureInPicture: Bool
    var hidesSystemChrome: Bool = false
    var onSkip: () -> Void
    var onPictureInPictureActive: (Bool) -> Void
    var onControllerReady: (AVPlayerViewController) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSkip: onSkip, onPictureInPictureActive: onPictureInPictureActive)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsAutomaticPictureInPicture
        controller.showsPlaybackControls = !hidesSystemChrome
        controller.updatesNowPlayingInfoCenter = true
        context.coordinator.install(on: controller)
        onControllerReady(controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.surfaceGeneration != surfaceGeneration {
            controller.player = nil
            context.coordinator.surfaceGeneration = surfaceGeneration
        }
        controller.player = player
        controller.delegate = context.coordinator
        controller.canStartPictureInPictureAutomaticallyFromInline = allowsAutomaticPictureInPicture
        controller.showsPlaybackControls = !hidesSystemChrome
        context.coordinator.onSkip = onSkip
        context.coordinator.onPictureInPictureActive = onPictureInPictureActive
        context.coordinator.install(on: controller)
        context.coordinator.update(title: skipTitle)
        onControllerReady(controller)
    }

    @MainActor
    final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
        var onSkip: () -> Void
        var onPictureInPictureActive: (Bool) -> Void
        var surfaceGeneration = 0
        private var button: UIButton?

        init(onSkip: @escaping () -> Void, onPictureInPictureActive: @escaping (Bool) -> Void) {
            self.onSkip = onSkip
            self.onPictureInPictureActive = onPictureInPictureActive
            super.init()
        }

        func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
            _ playerViewController: AVPlayerViewController
        ) -> Bool {
            false
        }

        func playerViewControllerDidStartPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            onPictureInPictureActive(true)
        }

        func playerViewControllerDidStopPictureInPicture(
            _ playerViewController: AVPlayerViewController
        ) {
            onPictureInPictureActive(false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        func install(on controller: AVPlayerViewController) {
            controller.loadViewIfNeeded()
            guard button == nil else { return }
            guard let overlay = controller.contentOverlayView ?? controller.view else { return }

            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.92)
            config.baseForegroundColor = .black
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                return outgoing
            }
            let skipButton = UIButton(type: .system)
            skipButton.configuration = config
            skipButton.translatesAutoresizingMaskIntoConstraints = false
            skipButton.isHidden = true
            skipButton.addAction(UIAction { [weak self] _ in
                self?.onSkip()
            }, for: .primaryActionTriggered)

            overlay.addSubview(skipButton)
            NSLayoutConstraint.activate([
                skipButton.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -24),
                skipButton.bottomAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.bottomAnchor, constant: -56)
            ])
            button = skipButton
        }

        func update(title: String?) {
            button?.isHidden = title == nil
            if let title {
                button?.configuration?.title = title
            }
        }
    }
}
