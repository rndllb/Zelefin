#if os(iOS) || os(tvOS)
import AVKit
import CoreMedia

/// Picture in Picture for the sample-buffer Direct Play path.
@MainActor
final class DirectPlayPictureInPicture: NSObject, AVPictureInPictureSampleBufferPlaybackDelegate {
    private(set) var controller: AVPictureInPictureController?
    private weak var source: DirectPlayPiPSource?

    var isSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    var isActive: Bool {
        controller?.isPictureInPictureActive ?? false
    }

    func attach(source: DirectPlayPiPSource?) {
        self.source = source
        guard isSupported, let source else {
            controller = nil
            return
        }
        let contentSource = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: source.layer,
            playbackDelegate: self
        )
        let created = AVPictureInPictureController(contentSource: contentSource)
        #if os(iOS)
        created.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        controller = created
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
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
        if Thread.isMainThread {
            return MainActor.assumeIsolated { source?.timeRange() ?? .zero }
        }
        return DispatchQueue.main.sync {
            source?.timeRange() ?? .zero
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(
        _ pictureInPictureController: AVPictureInPictureController
    ) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { source?.isPaused ?? true }
        }
        return DispatchQueue.main.sync {
            source?.isPaused ?? true
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
}
#endif
