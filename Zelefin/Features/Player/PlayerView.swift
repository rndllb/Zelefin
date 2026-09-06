import AVKit
import SwiftUI
import UIKit

struct PlayerView: View {
    let plan: PlaybackPlan
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var model: PlayerModel?
    @State private var didFallBackToRemux = false
    @State private var fallbackError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let model {
                playerSurface(model)
            } else {
                ProgressView().tint(.white)
            }
            if let message = fallbackError {
                errorOverlay(message)
            }
        }
        #if os(iOS)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .task {
            await startPlayback(plan)
        }
        .onDisappear {
            Task { await model?.stop() }
        }
        #if os(tvOS)
        .onPlayPauseCommand {
            model?.togglePlayPause()
        }
        #endif
        .onChange(of: model?.isFinished) { _, finished in
            if finished == true { dismiss() }
        }
        .onChange(of: model?.errorMessage) { _, message in
            guard let message, !didFallBackToRemux else { return }
            guard PlaybackPipelineResolver.pipeline(for: plan) == .directDecode else { return }
            Task { await fallBackToRemux(from: message) }
        }
    }

    private func startPlayback(_ plan: PlaybackPlan, skipSegments: [SkipSegment]? = nil) async {
        let reporter: PlaybackReporter?
        if let client = session.client {
            reporter = PlaybackReporter(client: client, plan: plan)
        } else {
            reporter = nil
        }
        let created = PlayerModel(plan: plan, reporter: reporter)
        if let skipSegments {
            created.skipSegments = skipSegments
        } else if let client = session.client {
            let skipper = IntroSkipperClient(client: client)
            if await skipper.isInstalled() {
                created.skipSegments = await skipper.segments(for: plan.item.id)
            }
        }
        model = created
        await Task.yield()
        await created.start()
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
            let remux = try await library.playbackPlan(for: plan.item, allowDirectPlay: false)
            await startPlayback(remux, skipSegments: skip)
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
                        DirectPlayVideoLayer(engine: engine) {
                            model.noteSurfaceReady()
                        }
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
                skipTitle: model.skipPrompt?.title,
                onSkip: { model.skipCurrentSegment() }
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
    var onBound: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBound: onBound)
    }

    func makeUIView(context: Context) -> DirectPlaySurfaceView {
        let view = DirectPlaySurfaceView()
        context.coordinator.bind(engine, to: view, onBound: onBound)
        return view
    }

    func updateUIView(_ uiView: DirectPlaySurfaceView, context: Context) {
        context.coordinator.bind(engine, to: uiView, onBound: onBound)
    }

    @MainActor
    final class Coordinator {
        var onBound: () -> Void

        init(onBound: @escaping () -> Void) {
            self.onBound = onBound
        }

        func bind(_ engine: DirectPlayEngine, to view: DirectPlaySurfaceView, onBound: @escaping () -> Void) {
            self.onBound = onBound
            engine.bind(view: view.playerView)
            view.onReady = { [weak self] in
                self?.onBound()
            }
            view.notifyIfReady()
        }
    }
}

struct NativePlayerContainer: UIViewControllerRepresentable {
    let player: AVPlayer
    var skipTitle: String?
    var onSkip: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSkip: onSkip)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(iOS)
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        #else
        controller.appliesPreferredDisplayCriteriaAutomatically = true
        #endif
        context.coordinator.install(on: controller)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        context.coordinator.onSkip = onSkip
        context.coordinator.install(on: controller)
        context.coordinator.update(title: skipTitle)
    }

    @MainActor
    final class Coordinator {
        var onSkip: () -> Void
        private var button: UIButton?

        init(onSkip: @escaping () -> Void) {
            self.onSkip = onSkip
        }

        func install(on controller: AVPlayerViewController) {
            controller.loadViewIfNeeded()
            guard button == nil else { return }
            guard let overlay = controller.contentOverlayView ?? controller.view else { return }

            var config = UIButton.Configuration.filled()
            config.cornerStyle = .capsule
            config.baseBackgroundColor = UIColor.white.withAlphaComponent(0.92)
            config.baseForegroundColor = .black
            #if os(tvOS)
            config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 28, bottom: 16, trailing: 28)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 28, weight: .semibold)
                return outgoing
            }
            #else
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = .systemFont(ofSize: 15, weight: .semibold)
                return outgoing
            }
            #endif
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
