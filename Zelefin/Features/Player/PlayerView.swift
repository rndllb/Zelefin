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
        // Direct Play binds its sample-buffer layer in `makeUIView`. Yield so that
        // attach happens before demux/decode, otherwise the first frames never appear.
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
                DirectPlayVideoLayer(engine: engine)
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

/// Binds the Direct Play layer once. Rebinding on every SwiftUI pass cycles AttributeGraph and can
/// detach the player layer while audio keeps running.
private struct DirectPlayVideoLayer: UIViewRepresentable {
    let engine: DirectPlayEngine

    func makeUIView(context: Context) -> DirectPlayPlayerView {
        let view = DirectPlayPlayerView()
        engine.bind(view: view)
        return view
    }

    func updateUIView(_: DirectPlayPlayerView, context _: Context) {}
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
