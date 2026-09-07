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

    /// On-device files have no HTTP ranges. Open through a file reader so libavformat
    /// never has to parse a path with spaces, and AVPlayer never gets gateway headers.
    static func shouldOpenAsURL(url: URL, method: PlaybackMethod, isHLS: Bool) -> Bool {
        url.isFileURL || shouldOpenAsHTTPURL(method: method, isHLS: isHLS)
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

/// Seekable file source for downloaded media. Custom IO keeps FFmpeg off `Application Support` paths.
final class LocalMediaByteReader: DirectPlayByteSource, @unchecked Sendable {
    private let handle: FileHandle
    private let url: URL
    private let size: Int64
    private let lock = NSLock()

    var discImageProbeEnabled: Bool { false }

    init?(url: URL) {
        guard url.isFileURL, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else {
            try? handle.close()
            return nil
        }
        self.handle = handle
        self.url = url
        self.size = size
    }

    func read(_ buffer: UnsafeMutablePointer<UInt8>?, size n: Int32) -> Int32 {
        guard let buffer, n > 0 else { return -1 }
        lock.lock()
        defer { lock.unlock() }
        return autoreleasepool { () -> Int32 in
            guard let data = try? handle.read(upToCount: Int(n)) else { return -1 }
            if data.isEmpty { return 0 }
            data.copyBytes(to: buffer, count: data.count)
            return Int32(data.count)
        }
    }

    func seek(offset: Int64, whence: Int32) -> Int64 {
        if whence == 65536 { return size }
        lock.lock()
        defer { lock.unlock() }
        let target: Int64
        switch whence {
        case SEEK_SET:
            target = offset
        case SEEK_CUR:
            target = Int64((try? handle.offset()) ?? 0) + offset
        case SEEK_END:
            target = size + offset
        default:
            return -1
        }
        guard target >= 0 else { return -1 }
        do {
            try handle.seek(toOffset: UInt64(target))
            return target
        } catch {
            return -1
        }
    }

    func close() {
        try? handle.close()
    }

    func makeIndependentReader() -> DirectPlayByteSource? {
        LocalMediaByteReader(url: url)
    }
}
