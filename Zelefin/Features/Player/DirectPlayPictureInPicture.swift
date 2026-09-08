import AVKit
import CoreMedia

/// Picture in Picture for the sample-buffer Direct Play path.
@MainActor
final class DirectPlayPictureInPicture: NSObject, @preconcurrency AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var controller: AVPictureInPictureController?
    private weak var source: DirectPlayPiPSource?
    private weak var engine: DirectPlayEngine?
    private weak var attachedLayer: AVSampleBufferDisplayLayer?
    private var possibleObservation: NSKeyValueObservation?

    var onPossibleChange: ((Bool) -> Void)?
    var onActiveChange: ((Bool) -> Void)?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isActive: Bool {
        controller?.isPictureInPictureActive ?? false
    }

    var canStart: Bool {
        isActive || (controller?.isPictureInPicturePossible ?? false)
    }

    func attach(source: DirectPlayPiPSource?, engine: DirectPlayEngine?) {
        self.source = source
        self.engine = engine
        syncController()
    }

    func syncController() {
        guard let source else {
            tearDownController()
            engine?.pictureInPictureActive = false
            onPossibleChange?(false)
            return
        }
        guard PlaybackPictureInPicturePolicy.canCreateController(
            isSupported: isSupported,
            layerIsInWindow: PlaybackPictureInPicturePolicy.isLayerInWindow(source.layer)
        ) else {
            return
        }
        if controller != nil, attachedLayer === source.layer {
            return
        }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: source.layer,
            playbackDelegate: self
        )
        let created = AVPictureInPictureController(contentSource: contentSource)
        created.delegate = self
        created.canStartPictureInPictureAutomaticallyFromInline = true
        observePossible(created)
        attachedLayer = source.layer
        controller = created
        onPossibleChange?(created.isPictureInPicturePossible || created.isPictureInPictureActive)
    }

    func toggle() {
        syncController()
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        startIfPossible(controller)
    }

    private func startIfPossible(_ controller: AVPictureInPictureController) {
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            return
        }
        DispatchQueue.main.async { [weak self, weak controller] in
            guard let self, let controller, controller.isPictureInPicturePossible else { return }
            controller.startPictureInPicture()
        }
    }

    private func tearDownController() {
        possibleObservation = nil
        attachedLayer = nil
        controller = nil
    }

    private func observePossible(_ controller: AVPictureInPictureController) {
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            let active = controller.isPictureInPictureActive
            Task { @MainActor in
                self?.onPossibleChange?(possible || active)
            }
        }
    }

    private func setActive(_ active: Bool) {
        engine?.pictureInPictureActive = active
        onActiveChange?(active)
        onPossibleChange?(canStart)
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            setActive(true)
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(
        _ pictureInPictureController: AVPictureInPictureController
    ) {
        Task { @MainActor in
            setActive(false)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        Task { @MainActor in
            setActive(false)
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        Task { @MainActor in
            source?.setPlaying(playing)
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> CMTimeRange {
        playableTimeRange()
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { source?.isPaused ?? true }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { source?.isPaused ?? true }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime
    ) async {
        await MainActor.run {
            source?.skip(by: skipInterval.seconds)
        }
    }

    nonisolated private func playableTimeRange() -> CMTimeRange {
        let fallback = CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        if Thread.isMainThread {
            return MainActor.assumeIsolated { source?.timeRange() ?? fallback }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { source?.timeRange() ?? fallback }
        }
    }
}
