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

    init(item: MediaItem) {
        self.item = item
        _activeItem = State(initialValue: item)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                playerSurface(model)
            } else {
                ProgressView().tint(.white)
            }
            if model == nil {
                loadingClose
            }
            if let message = fallbackError {
                errorOverlay(message)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            await prepareAndStart()
        }
        .onDisappear {
            model?.markPlaybackViewDismissed()
        }
        .onChange(of: model?.isFinished) { _, finished in
            guard finished == true else { return }
            Task { await advanceOrDismiss() }
        }
        .onChange(of: model?.errorMessage) { _, message in
            guard let message, !didFallBackToRemux else { return }
            guard let plan = model?.plan, plan.method == .directPlay else { return }
            if OfflinePlaybackPolicy.shouldFallBackToRemux(isLocalFile: plan.streamURL.isFileURL) {
                Task { await fallBackToRemux(from: message) }
                return
            }
            fallbackError = message
        }
        .onChange(of: scenePhase) { _, phase in
            handleScenePhase(phase)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteStopPlayback)) { _ in
            dismiss()
        }
        .onReceive(NotificationCenter.default.publisher(for: .zelefinRemoteNextTrack)) { _ in
            Task { await advanceOrDismiss() }
        }
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

    private func prepareAndStart() async {
        if let local = downloads.playbackPlan(for: activeItem, account: session.session) {
            guard !Task.isCancelled else { return }
            await startPlayback(local)
            return
        }
        guard let library = session.library else {
            fallbackError = "Sign in to play this title."
            return
        }
        do {
            var plan = try await library.playbackPlan(for: activeItem)
            if PlaybackPipelineResolver.needsServerRemuxForNativePlayer(
                url: plan.streamURL,
                method: plan.method,
                container: plan.container,
                videoCodec: plan.videoCodec,
                usesNativePlayer: PlaybackPreferences.useNativeVideoPlayer
            ) {
                plan = try await library.playbackPlan(for: activeItem, allowDirectPlay: false)
            }
            try Task.checkCancellation()
            await startPlayback(plan)
        } catch is CancellationError {
            return
        } catch {
            fallbackError = error.localizedDescription
        }
    }

    private func startPlayback(_ plan: PlaybackPlan, skipSegments: [SkipSegment]? = nil) async {
        let reporter: PlaybackReporter?
        if OfflinePlaybackPolicy.shouldReportToServer(isLocalFile: plan.streamURL.isFileURL),
           let client = session.client {
            reporter = PlaybackReporter(client: client, plan: plan)
        } else {
            reporter = nil
        }
        let created = PlayerModel(plan: plan, reporter: reporter)
        if let skipSegments {
            created.skipSegments = skipSegments
        }
        model = created
        await Task.yield()
        do {
            if skipSegments == nil,
               OfflinePlaybackPolicy.shouldFetchSkipSegments(isLocalFile: plan.streamURL.isFileURL),
               let client = session.client {
                let skipper = IntroSkipperClient(client: client)
                if await skipper.isInstalled() {
                    try Task.checkCancellation()
                    created.skipSegments = await skipper.segments(for: plan.item.id)
                }
            }
            try Task.checkCancellation()
            await created.start()
        } catch is CancellationError {
            await created.stop()
        } catch {
            fallbackError = error.localizedDescription
        }
    }

    private func advanceOrDismiss() async {
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
        await prepareAndStart()
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
            let remux = try await library.playbackPlan(for: activeItem, allowDirectPlay: false)
            try Task.checkCancellation()
            await startPlayback(remux, skipSegments: skip)
        } catch is CancellationError {
            return
        } catch {
            fallbackError = error.localizedDescription
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
                if model.showsPlaybackStats {
                    PlaybackStatsOverlay(snapshot: model.playbackStats)
                }
                AVKitPlaybackChrome(
                    model: model,
                    title: model.plan.item.name,
                    onClose: { dismiss() }
                )
                if !model.hasFirstFrame || model.isBuffering {
                    ProgressView()
                        .tint(.white)
                        .allowsHitTesting(false)
                }
            }
        } else if let player = model.player {
            NativePlayerContainer(
                player: player,
                surfaceGeneration: model.surfaceGeneration,
                skipTitle: model.skipPrompt?.title,
                onSkip: { model.skipCurrentSegment() },
                onPictureInPictureActive: { model.setNativePictureInPictureActive($0) }
            )
            .ignoresSafeArea()
        } else {
            ProgressView().tint(.white)
        }
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
