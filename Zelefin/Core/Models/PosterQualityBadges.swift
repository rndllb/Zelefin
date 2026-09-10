import Foundation

enum PosterQualityBadge: Equatable, Hashable, Identifiable, Sendable {
    case fourK
    case hd
    case hdr(String)
    case atmos

    var id: String {
        switch self {
        case .fourK: "4k"
        case .hd: "hd"
        case let .hdr(label): "hdr-\(label)"
        case .atmos: "atmos"
        }
    }

    var title: String {
        switch self {
        case .fourK: "4K"
        case .hd: "HD"
        case let .hdr(label): label
        case .atmos: "Atmos"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .fourK: "4K"
        case .hd: "HD"
        case let .hdr(label): label == "DV" ? "Dolby Vision" : label
        case .atmos: "Dolby Atmos"
        }
    }
}

enum PosterQualityBadges {
    static func badges(for item: MediaItem) -> [PosterQualityBadge] {
        var result: [PosterQualityBadge] = []
        switch item.videoResolution {
        case .fourK:
            result.append(.fourK)
        case .hd:
            result.append(.hd)
        case .sd, .unknown:
            break
        }
        switch item.videoRange {
        case .dolbyVision:
            result.append(.hdr("DV"))
        case .hdr10Plus:
            result.append(.hdr("HDR10+"))
        case .hdr10, .hlg:
            result.append(.hdr("HDR"))
        case .sdr:
            break
        }
        if item.audioFormat == .atmos {
            result.append(.atmos)
        }
        return result
    }
}
