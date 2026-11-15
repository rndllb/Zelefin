import AVFoundation
import AVKit
import SwiftUI
import UIKit

/// Whether AVPlayer is sending video to AirPlay / an external screen.
enum AirPlayRoutePolicy {
    static func isExternalVideoActive(_ player: AVPlayer?) -> Bool {
        player?.isExternalPlaybackActive == true
    }
}

/// Metadata the Apple TV Now Playing card reads from `AVPlayerItem.externalMetadata`
/// (separate from the phone’s MPNowPlayingInfoCenter).
enum AirPlayExternalMetadata {
    static func items(for item: MediaItem) -> [AVMetadataItem] {
        var items: [AVMetadataItem] = []
        items.append(metadata(.commonIdentifierTitle, value: item.name))
        if let line = secondaryLine(for: item) {
            items.append(metadata(.commonIdentifierArtist, value: line))
        }
        return items
    }

    static func apply(to playerItem: AVPlayerItem, item: MediaItem) {
        playerItem.externalMetadata = items(for: item)
    }

    private static func secondaryLine(for item: MediaItem) -> String? {
        if item.kind == .episode {
            var parts: [String] = []
            if let series = item.seriesName, !series.isEmpty {
                parts.append(series)
            }
            if let season = item.seasonIndex, let episode = item.episodeIndex {
                parts.append("S\(season), E\(episode)")
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        if let year = item.year {
            return String(year)
        }
        return nil
    }

    private static func metadata(
        _ identifier: AVMetadataIdentifier,
        value: String
    ) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.identifier = identifier
        item.value = value as NSString
        item.extendedLanguageTag = "und"
        return item
    }
}

/// Fires the system AirPlay sheet from a normal SwiftUI button (ArcFin-style).
@MainActor
final class AirPlayRouteBridge {
    weak var button: UIButton?

    func presentPicker() {
        button?.sendActions(for: .touchUpInside)
    }
}

/// Hidden system route picker mounted once; `bridge.presentPicker()` opens it.
struct AirPlayRoutePickerHost: UIViewRepresentable {
    var bridge: AirPlayRouteBridge

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .clear
        picker.isUserInteractionEnabled = false
        bridge.button = picker.subviews.compactMap { $0 as? UIButton }.first
        return picker
    }

    func updateUIView(_ picker: AVRoutePickerView, context: Context) {
        if bridge.button == nil {
            bridge.button = picker.subviews.compactMap { $0 as? UIButton }.first
        }
    }
}

/// A real `AVPlayerLayer` in the window hierarchy. Without it, iOS often AirPlays audio only.
struct AirPlayRelayLayerHost: UIViewRepresentable {
    var player: AVPlayer?

    func makeUIView(context: Context) -> AirPlayRelayPlayerView {
        let view = AirPlayRelayPlayerView()
        view.player = player
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ view: AirPlayRelayPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }
}

final class AirPlayRelayPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        playerLayer.videoGravity = .resizeAspect
        // Keep the layer composited (not opacity-0) so AirPlay classifies as video.
        isOpaque = false
        alpha = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set {
            playerLayer.player = newValue
            playerLayer.videoGravity = .resizeAspect
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
