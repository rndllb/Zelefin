import AetherEngine
import Foundation
import UIKit

typealias DirectPlayEngine = AetherEngine
typealias DirectPlayPlayerView = AetherPlayerView
typealias DirectPlayByteSource = IOReader
typealias DirectPlayPiPSource = SoftwarePiPSource
typealias DirectPlayTrack = TrackInfo
typealias DirectPlaySubtitleCue = SubtitleCue
typealias DirectPlaySubtitlePlacement = SubtitleTextPlacement
typealias DirectPlaySubtitleImage = SubtitleImage
typealias DirectPlayVideoFormat = VideoFormat
typealias DirectPlayVideoRoute = VideoRoute
typealias DirectPlayAudioDelivery = AudioDelivery
typealias DirectPlayPlaybackPhase = PlaybackPhase
typealias DirectPlaySeekEvent = SeekEvent

/// How long Direct Play waits for SwiftUI to insert `AetherPlayerView` before `load()`.
enum DirectPlaySurfaceGate {
    static let waitBudget: TimeInterval = 2
    static let pollNanoseconds: UInt64 = 20_000_000
}

/// Aether plays audio with no picture when the probe opens the file but never finds a
/// video stream (`playbackBackend == .audio`). A second open through the HTTP URL lets
/// libavformat see the path extension instead of a forced custom-IO hint.
enum DirectPlayLoadPolicy {
    static func shouldReloadAsURL(isAudioOnlyBackend: Bool, expectsVideo: Bool) -> Bool {
        isAudioOnlyBackend && expectsVideo
    }

    /// Remux/transcode HLS has no file to range-request; open the playlist URL instead.
    static func shouldOpenAsHTTPURL(method: PlaybackMethod, isHLS: Bool) -> Bool {
        method != .directPlay || isHLS
    }
}

/// Returning from background leaves audio on a dead sample-buffer layer. Aether
/// asks the host to rebuild; Control Center / the app switcher peek should not.
enum PlaybackForegroundRecovery {
    static let settleNanoseconds: UInt64 = 100_000_000

    static func shouldRestore(wasBackgrounded: Bool, pictureInPictureActive: Bool) -> Bool {
        wasBackgrounded && !pictureInPictureActive
    }
}

/// Sample-buffer PiP is refused if the controller is built before the layer is
/// in a window, and a `.zero` playable range also makes AVKit refuse to start.
enum PlaybackPictureInPicturePolicy {
    static func canCreateController(isSupported: Bool, layerIsInWindow: Bool) -> Bool {
        isSupported && layerIsInWindow
    }

    static func shouldStopOnViewDismiss(pictureInPictureActive: Bool) -> Bool {
        !pictureInPictureActive
    }

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

/// Session options for Zelefin Direct Play: FFmpeg demux through `JellyfinByteRangeReader`,
/// VideoToolbox decode, `AVSampleBufferDisplayLayer` presentation.
enum DirectPlayLoadOptions {
    static func usesSampleBufferDecode(for pipeline: PlaybackPipeline) -> Bool {
        switch pipeline {
        case .directDecode:
            true
        case .appleNative:
            false
        }
    }

    @MainActor
    static func make(for plan: PlaybackPlan) -> LoadOptions {
        var headers = PlaybackHTTPHeaders.fields(for: plan.streamURL)
        for (name, value) in plan.extraHTTPHeaders {
            headers[name] = value
        }
        let selectedAudioLanguage = plan.audioTracks.first(where: \.isSelected)?.language
        let selectedSubtitleLanguage = plan.subtitleTracks.first(where: \.isSelected)?.language
        let duration = plan.item.runtime.flatMap { seconds in
            seconds > 0 ? seconds : nil
        }
        return LoadOptions(
            httpHeaders: headers,
            matchContentEnabled: true,
            panelIsInHDRMode: isPanelInHDRMode,
            prepareNativeSubtitles: false,
            eagerNativeSubtitleReaders: false,
            maxConcurrentSourceRequests: 2,
            declaredDurationSeconds: duration,
            preferredAudioLanguages: languageList(selectedAudioLanguage),
            preferredSubtitleLanguages: languageList(selectedSubtitleLanguage),
            preferredDecodePath: usesSampleBufferDecode(for: .directDecode) ? .software : .automatic
        )
    }

    private static func languageList(_ language: String?) -> [String] {
        guard let language else { return [] }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "und" else { return [] }
        return [trimmed]
    }

    @MainActor
    private static var isPanelInHDRMode: Bool {
        UIScreen.main.currentEDRHeadroom > 1
    }
}
