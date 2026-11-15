import AVFoundation
import Foundation
import UIKit

/// `AVAudioSession.setActive(true)` is a synchronous round trip to the audio server, and the
/// first one after launch can hold the main thread long enough that the player ignores taps.
/// Activating here first, off the main thread, turns a later session call into a no-op.
enum PlaybackAudioSession {
    static func activate() async {
        await Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .moviePlayback, policy: .default)
            try? session.setSupportsMultichannelContent(true)
            try? session.setActive(true)
        }.value
    }

    /// Theme songs and theme video sound. The default session goes silent with the Ring/Silent
    /// switch on silent, so this uses playback, mixed with other apps' audio rather than stopping it.
    static func activateForThemeMedia() {
        Task.detached(priority: .userInitiated) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setActive(true)
        }
    }

    /// For a player closed before anything played, so other apps' audio can resume.
    static func deactivate() {
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

/// How long playback waits for SwiftUI to insert the video surface before `load()`.
enum DirectPlaySurfaceGate {
    static let waitBudget: TimeInterval = 0.45
    static let pollNanoseconds: UInt64 = 8_000_000
}

/// Remux/transcode HLS has no file to range-request; live MPEG-TS is an infinite pipe.
/// Direct Play with no known size opens the stream URL as-is.
enum DirectPlayLoadPolicy {
    static func shouldReloadAsURL(isAudioOnlyBackend: Bool, expectsVideo: Bool) -> Bool {
        isAudioOnlyBackend && expectsVideo
    }

    static func shouldOpenAsHTTPURL(
        method: PlaybackMethod,
        isHLS: Bool,
        isLive: Bool = false,
        hasKnownSize: Bool = true
    ) -> Bool {
        method != .directPlay || isHLS || isLive || !hasKnownSize
    }

    /// On-device files have no HTTP ranges. Open through a file reader so libavformat
    /// never has to parse a path with spaces, and AVPlayer never gets gateway headers.
    static func shouldOpenAsURL(
        url: URL,
        method: PlaybackMethod,
        isHLS: Bool,
        isLive: Bool = false,
        hasKnownSize: Bool = true
    ) -> Bool {
        url.isFileURL || shouldOpenAsHTTPURL(
            method: method,
            isHLS: isHLS,
            isLive: isLive,
            hasKnownSize: hasKnownSize
        )
    }
}

/// Local downloads must not wait on Jellyfin (intro skipper, remux fallback, progress).
enum OfflinePlaybackPolicy {
    static func shouldFetchSkipSegments(isLocalFile: Bool) -> Bool {
        !isLocalFile
    }

    static func shouldReportToServer(isLocalFile: Bool) -> Bool {
        !isLocalFile
    }

    static func shouldFallBackToRemux(isLocalFile: Bool) -> Bool {
        !isLocalFile
    }
}

/// Returning from background can leave a dead sample-buffer layer. Rebuild when
/// needed; Control Center / the app switcher peek should not.
enum PlaybackForegroundRecovery {
    static let settleNanoseconds: UInt64 = 100_000_000

    static func shouldRestore(wasBackgrounded: Bool, pictureInPictureActive: Bool) -> Bool {
        wasBackgrounded && !pictureInPictureActive
    }
}

/// AirPlay video needs AVPlayer. Captions only reach Apple TV reliably when the
/// server puts them on an HLS rendition (remux/transcode with SubtitleStreamIndex).
enum AirPlayHandoffPolicy {
    static func needsServerRemux(
        containerNeedsRemux: Bool,
        selectedSubtitleID: Int?
    ) -> Bool {
        containerNeedsRemux || selectedSubtitleID != nil
    }
}

/// Sample-buffer PiP is refused if the controller is built before the layer is
/// in a window, and a `.zero` playable range also makes AVKit refuse to start.
enum PlaybackPictureInPicturePolicy {
    static func canCreateController(isSupported: Bool, layerIsInWindow: Bool) -> Bool {
        isSupported && layerIsInWindow
    }

    /// Background / leave auto-PiP only when the user enabled it. Manual PiP stays available.
    static func shouldAutoStart(preferenceEnabled: Bool) -> Bool {
        preferenceEnabled
    }

    static func shouldStopOnViewDismiss(pictureInPictureActive: Bool) -> Bool {
        !pictureInPictureActive
    }

    @MainActor
    static func isLayerInWindow(_ layer: CALayer) -> Bool {
        var node: CALayer? = layer
        while let current = node {
            if let view = current.delegate as? UIView, view.window != nil {
                return true
            }
            node = current.superlayer
        }
        return false
    }
}

/// Server HLS remux/transcode has subtitle renditions on the playlist, not
/// demuxable packets. Open that playlist with AVPlayer when Native is selected.
enum DirectPlayLoadOptions {
    static func shouldUseNativeRemoteHLS(url: URL, container: String?) -> Bool {
        if PlaybackPipelineResolver.isHLS(url) { return true }
        return (container ?? "").lowercased().contains("hls")
    }
}
