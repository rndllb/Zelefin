import AVKit
import CoreMedia

/// Transport answers for sample-buffer Picture in Picture (MPV `vo_avfoundation`).
@MainActor
protocol SampleBufferPiPTransport: AnyObject {
    var isPaused: Bool { get }
    func setPlaying(_ playing: Bool)
    func skip(by seconds: Double)
    func timeRange() -> CMTimeRange
}

/// Picture in Picture for an `AVSampleBufferDisplayLayer` (MPV `vo_avfoundation`).
@MainActor
final class DirectPlayPictureInPicture: NSObject, AVPictureInPictureControllerDelegate, AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var controller: AVPictureInPictureController?
    private weak var transport: (any SampleBufferPiPTransport)?
    private weak var layer: AVSampleBufferDisplayLayer?
    private weak var attachedLayer: AVSampleBufferDisplayLayer?
    private var possibleObservation: NSKeyValueObservation?
    /// Set while leaving without PiP so layout/dismiss cannot recreate the controller.
    private(set) var isBlocked = false

    var onPossibleChange: ((Bool) -> Void)?
    var onActiveChange: ((Bool) -> Void)?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isActive: Bool {
        controller?.isPictureInPictureActive ?? false
    }

    var canStart: Bool {
        if isBlocked { return false }
        if isActive { return true }
        if let controller { return controller.isPictureInPicturePossible }
        // Controller is created lazily; still offer the manual PiP button when supported.
        return layer != nil && isSupported
    }

    func attach(layer: AVSampleBufferDisplayLayer, transport: any SampleBufferPiPTransport) {
        isBlocked = false
        self.layer = layer
        self.transport = transport
        // Only build the controller up front when auto-PiP is on. Otherwise create it on
        // manual toggle / arm — an idle controller can still be promoted when leaving.
        if PlaybackPreferences.autoPictureInPictureOnLeave {
            syncController()
        } else {
            tearDownController()
            onPossibleChange?(canStart)
        }
    }

    func syncController(forceRecreate: Bool = false) {
        guard !isBlocked else {
            onPossibleChange?(false)
            return
        }
        guard let layer else {
            tearDownController()
            onPossibleChange?(false)
            return
        }
        guard PlaybackPictureInPicturePolicy.canCreateController(
            isSupported: isSupported,
            layerIsInWindow: PlaybackPictureInPicturePolicy.isLayerInWindow(layer)
        ) else {
            return
        }
        if !forceRecreate, controller != nil, attachedLayer === layer {
            controller?.canStartPictureInPictureAutomaticallyFromInline = false
            onPossibleChange?(canStart)
            return
        }
        tearDownController()
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: layer,
            playbackDelegate: self
        )
        let created = AVPictureInPictureController(contentSource: contentSource)
        created.delegate = self
        // Never let AVKit auto-start when the player leaves the screen — that ignores the
        // "PiP When Leaving" toggle. We only start via armForBackground / toggle.
        created.canStartPictureInPictureAutomaticallyFromInline = false
        observePossible(created)
        attachedLayer = layer
        controller = created
        onPossibleChange?(created.isPictureInPicturePossible || created.isPictureInPictureActive)
    }

    /// Close / dismiss with the toggle off: kill the controller so AVKit cannot promote playback.
    func suppressAutomaticStart() {
        isBlocked = true
        if let controller, controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        }
        tearDownController()
        layer = nil
        transport = nil
        onPossibleChange?(false)
    }

    func toggle() {
        isBlocked = false
        syncController(forceRecreate: controller?.isPictureInPicturePossible == false)
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        startIfPossible(controller)
    }

    /// Call from `willResignActive` / scene background so auto-PiP can start while the layer
    /// still has frames. Only when the leave preference is on.
    func armForBackground() {
        guard !isBlocked else { return }
        syncController(forceRecreate: controller?.isPictureInPicturePossible == false)
        guard let controller, !controller.isPictureInPictureActive else { return }
        startIfPossible(controller)
    }

    func startAutomaticallyIfPossible() {
        armForBackground()
    }

    private func startIfPossible(_ controller: AVPictureInPictureController) {
        if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
            return
        }
        DispatchQueue.main.async { [weak controller] in
            guard let controller else { return }
            if controller.isPictureInPicturePossible {
                controller.startPictureInPicture()
            } else if !controller.isPictureInPictureActive {
                ZelefinLog.info("Playback", "PiP still not possible after arming")
            }
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
            ZelefinLog.error("Playback", "PiP failed to start: \(error.localizedDescription)")
            setActive(false)
        }
    }

    nonisolated func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        false
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        setPlaying playing: Bool
    ) {
        Task { @MainActor in
            transport?.setPlaying(playing)
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
            return MainActor.assumeIsolated { transport?.isPaused ?? true }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { transport?.isPaused ?? true }
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
            transport?.skip(by: skipInterval.seconds)
        }
    }

    nonisolated private func playableTimeRange() -> CMTimeRange {
        let fallback = CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)
        if Thread.isMainThread {
            return MainActor.assumeIsolated { transport?.timeRange() ?? fallback }
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated { transport?.timeRange() ?? fallback }
        }
    }
}
