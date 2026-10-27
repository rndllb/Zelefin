import AVKit
import SwiftUI
import UIKit

struct PlayerView: View {
    let item: MediaItem
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
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
        }
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
            Task { await PlaybackAudioSession.activate() }
            await prepareAndStart()
        }
        .task(id: liveAdaptiveMonitorID) {
            await monitorLiveAdaptive()
        }
        .onDisappear {
            isOnScreen = false
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
        }
        .onChange(of: model?.isFinished) { _, finished in
            guard finished == true else { return }
            if model?.plan.isLive == true { return }
            Task { await advanceOrDismiss() }
        }
        .onChange(of: model?.errorMessage) { _, message in
            guard let message else { return }
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
        .onChange(of: session.adaptiveBitrate.path.transport) { previous, _ in
            guard previous != .other else { return }
            liveBitrateOverride = nil
            Task { await retuneAdaptiveBitrate() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteStopPlayback)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteNextTrack)) { _ in
            Task { await advanceOrDismiss() }
        }
        .openSubtitlesSearch(item: $subtitleSearchItem, mediaSourceID: subtitleSearchFileID)
    }

    private var isCinemaBumper: Bool {
        cinemaIndex + 1 < cinemaQueue.count
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            playerWasBackgrounded = true
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
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
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
                .accessibilityLabel("Loading")
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
            let launch = session.launchOptions(for: target.id)
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

    private func startPlayback(_ plan: PlaybackPlan, skipSegments: [SkipSegment]? = nil) async {
        await waitForPresentation()
        // Restarts run in unstructured tasks that outlive the view; never start after close.
        guard !Task.isCancelled, isOnScreen else { return }
        let reporter = session.makePlaybackReporter(for: plan)
        let created = PlayerModel(plan: plan, reporter: reporter)
        created.onUserTransport = { action in
            Task { await session.forwardSyncPlay(action) }
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
        } else if !plan.skipSegments.isEmpty {
            created.skipSegments = plan.skipSegments
        } else if created.plan.isLive != true,
           OfflinePlaybackPolicy.shouldFetchSkipSegments(isLocalFile: plan.streamURL.isFileURL) {
            let client = session.client
            let library = session.library
            Task {
                var segments: [SkipSegment] = []
                if let client {
                    // Checking `/Plugins` first left every non-administrator without skip markers:
                    // that list is admin-only, so Intro Skipper always looked missing to them.
                    segments = await IntroSkipperClient(client: client).segments(for: plan.item.id)
                }
                if segments.isEmpty, PlaybackPreferences.usesTheIntroDB, let library {
                    segments = await TheIntroDB.segments(for: plan.item, library: library)
                }
                created.skipSegments = segments
            }
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
            dismiss()
            return
        }
        guard PlaybackPreferences.autoPlayNextEpisode else {
            dismiss()
            return
        }
        guard let library = session.library,
              let next = await library.nextEpisode(after: activeItem)
        else {
            dismiss()
            return
        }
        await model?.stop()
        model = nil
        didFallBackToRemux = false
        fallbackError = nil
        activeItem = next
        liveBitrateOverride = nil
        appliedBitrate = nil
        await prepareAndStart()
    }

    /// The first open after a cold start can fail while the server spins up; a reopen works.
    private func retryStart() async {
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

    @ViewBuilder
    private func playerSurface(_ model: PlayerModel) -> some View {
        if let engine = model.engine {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        DirectPlayVideoLayer(
                            engine: engine,
                            surfaceGeneration: model.surfaceGeneration,
                            onBound: { model.noteSurfaceReady() },
                            onLayerAttached: { model.syncPictureInPicture() }
                        )
                    }
                    .ignoresSafeArea()
                DirectPlaySubtitleOverlay(
                    cues: model.subtitleCues,
                    pictureSize: model.pictureSize,
                    fillsScreen: model.fillsScreen
                )
                playerChrome(model)
                if model.showsPlaybackStats {
                    PlaybackStatsOverlay(snapshot: model.playbackStats)
                }
            }
        } else if let mpv = model.mpv {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                MPVVideoSurface(layer: mpv.displayLayer, onBound: { model.noteSurfaceReady() })
                    .ignoresSafeArea()
                playerChrome(model)
                if model.showsPlaybackStats {
                    PlaybackStatsOverlay(snapshot: model.playbackStats)
                }
            }
        } else if let player = model.player {
            NativePlayerContainer(
                player: player,
                surfaceGeneration: model.surfaceGeneration,
                skipTitle: isCinemaBumper ? "Skip" : model.skipPrompt?.title,
                onSkip: {
                    if isCinemaBumper {
                        Task { await advanceOrDismiss() }
                    } else {
                        model.skipCurrentSegment()
                    }
                },
                onPictureInPictureActive: { model.setNativePictureInPictureActive($0) }
            )
            .ignoresSafeArea()
        } else {
            loadingSurface
        }
    }

    /// Zelefin's controls and track menus, shared by the AetherEngine and MPV players.
    private func playerChrome(_ model: PlayerModel) -> some View {
        AVKitPlaybackChrome(
            model: model,
            title: model.plan.item.name,
            quality: session.launchOptions(for: item.id).resolvedQuality,
            canAddSubtitles: !isCinemaBumper && session.shouldShowAddSubtitles(for: activeItem),
            onClose: { dismiss() },
            onQualityChange: { quality in
                Task { await changeQuality(quality) }
            },
            onAddSubtitles: {
                subtitleSearchFileID = model.plan.mediaSourceID
                subtitleSearchItem = activeItem
            },
            onAudioChange: { id in
                model.selectAudio(id: id)
                session.updateLaunchOptions(for: activeItem.id) { $0.audioIndex = id }
            },
            onSubtitleChange: { id in
                model.selectSubtitle(id: id)
                session.updateLaunchOptions(for: activeItem.id) { options in
                    options.subtitlesDisabled = id == nil
                    options.subtitleIndex = id
                }
            },
            onSkipCinema: isCinemaBumper ? { Task { await advanceOrDismiss() } } : nil
        )
    }

    private func errorOverlay(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text("Playback failed")
                .font(.title2.weight(.semibold))
            Text(message)
                .font(.body)
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .padding(24)
        .frame(maxWidth: 480)
    }
}

/// Hosts `AetherPlayerView` at the size SwiftUI actually proposes. A zero-size
/// representable leaves Aether decoding into a layer that is never visible: audio
/// plays, the picture stays black.
private final class DirectPlaySurfaceView: UIView {
    let playerView = DirectPlayPlayerView()
    var onReady: (() -> Void)?
    private var didNotify = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        playerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playerView)
        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        notifyIfReady()
    }

    func notifyIfReady() {
        guard !didNotify, bounds.width > 1, bounds.height > 1 else { return }
        didNotify = true
        onReady?()
    }
}

/// Rebinds on every SwiftUI update (Aether #188). An empty `updateUIView` leaves a
/// reused surface showing a detached layer: black video over working audio.
/// Hosts the layer mpv's vo_avfoundation paints into.
private struct MPVVideoSurface: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer
    var onBound: () -> Void

    func makeUIView(context: Context) -> LayerHostView {
        let view = LayerHostView()
        view.backgroundColor = .black
        view.host(layer)
        return view
    }

    func updateUIView(_ uiView: LayerHostView, context: Context) {
        uiView.host(layer)
        onBound()
    }

    final class LayerHostView: UIView {
        private weak var hosted: CALayer?

        func host(_ layer: CALayer) {
            guard hosted !== layer else { return }
            hosted?.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            hosted = layer
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}

private struct DirectPlayVideoLayer: UIViewRepresentable {
    let engine: DirectPlayEngine
    var surfaceGeneration: Int
    var onBound: () -> Void
    var onLayerAttached: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBound: onBound, onLayerAttached: onLayerAttached)
    }

    func makeUIView(context: Context) -> DirectPlaySurfaceView {
        let view = DirectPlaySurfaceView()
        context.coordinator.bind(
            engine,
            to: view,
            generation: surfaceGeneration,
            onBound: onBound,
            onLayerAttached: onLayerAttached
        )
        return view
    }

    func updateUIView(_ uiView: DirectPlaySurfaceView, context: Context) {
        context.coordinator.bind(
            engine,
            to: uiView,
            generation: surfaceGeneration,
            onBound: onBound,
            onLayerAttached: onLayerAttached
        )
    }

    @MainActor
    final class Coordinator {
        var onBound: () -> Void
        var onLayerAttached: () -> Void
        private var lastGeneration: Int?

        init(onBound: @escaping () -> Void, onLayerAttached: @escaping () -> Void) {
            self.onBound = onBound
            self.onLayerAttached = onLayerAttached
        }

        func bind(
            _ engine: DirectPlayEngine,
            to view: DirectPlaySurfaceView,
            generation: Int,
            onBound: @escaping () -> Void,
            onLayerAttached: @escaping () -> Void
        ) {
            self.onBound = onBound
            self.onLayerAttached = onLayerAttached
            if lastGeneration != generation {
                if lastGeneration != nil {
                    engine.unbind(view: view.playerView)
                }
                lastGeneration = generation
            }
            engine.bind(view: view.playerView)
            view.onReady = { [weak self] in
                self?.onBound()
            }
            view.notifyIfReady()
            onLayerAttached()
        }
    }
}

struct NativePlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var surfaceGeneration: Int
    var skipTitle: String?
    var onSkip: () -> Void
    var onPictureInPictureActive: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSkip: onSkip, onPictureInPictureActive: onPictureInPictureActive)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        context.coordinator.install(on: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if context.coordinator.surfaceGeneration != surfaceGeneration {
            controller.player = nil
            context.coordinator.surfaceGeneration = surfaceGeneration
        }
        controller.player = player
        controller.delegate = context.coordinator
        context.coordinator.onSkip = onSkip
        context.coordinator.onPictureInPictureActive = onPictureInPictureActive
        context.coordinator.install(on: controller)
        context.coordinator.update(title: skipTitle)
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
