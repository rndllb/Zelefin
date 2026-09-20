import Foundation

/// Derives the poster quality/audio badges (resolution, dynamic range, Dolby
/// Atmos) from a Silo item's `overlay_summary`, mirroring how the reference
/// Silo clients render their card overlays. Pure functions so they can be
/// unit-tested against the server's string shapes directly.
enum SiloQuality {
    static func videoResolution(
        from summary: SiloOverlaySummary?,
        fallbackWidth: Int? = nil,
        fallbackHeight: Int? = nil
    ) -> VideoResolution {
        if let resolution = resolution(fromLabel: summary?.resolution) {
            return resolution
        }
        return resolution(width: fallbackWidth, height: fallbackHeight)
    }

    static func videoRange(from summary: SiloOverlaySummary?) -> VideoRange {
        guard let raw = summary?.hdr?.lowercased(), !raw.isEmpty else { return .sdr }
        if raw.contains("dv") || raw.contains("dolby") { return .dolbyVision }
        if raw.contains("hdr10+") || raw.contains("hdr10plus") { return .hdr10Plus }
        if raw.contains("hlg") { return .hlg }
        if raw.contains("hdr") || raw.contains("pq") { return .hdr10 }
        return .sdr
    }

    static func audioFormat(from summary: SiloOverlaySummary?) -> AudioFormat {
        let audio = (summary?.audio ?? "").lowercased()
        if audio.contains("atmos") { return .atmos }

        let channels = summary?.audioChannels ?? ""
        if isSurround(channels: channels)
            || audio.contains("truehd")
            || audio.contains("dts")
            || audio.contains("5.1")
            || audio.contains("7.1") {
            return .surround
        }
        if audio.isEmpty, channels.isEmpty { return .unknown }
        return .stereo
    }

    // MARK: - Helpers

    private static func resolution(fromLabel label: String?) -> VideoResolution? {
        guard let raw = label?.lowercased().trimmingCharacters(in: .whitespaces), !raw.isEmpty else {
            return nil
        }
        switch raw {
        case "2160p", "4k", "uhd", "4320p", "8k":
            return .fourK
        default:
            let digits = raw.prefix { $0.isNumber }
            guard let scanLines = Int(digits) else { return .sd }
            if scanLines >= 2000 { return .fourK }
            if scanLines >= 720 { return .hd }
            return .sd
        }
    }

    private static func resolution(width: Int?, height: Int?) -> VideoResolution {
        let longEdge = max(width ?? 0, height ?? 0)
        if longEdge >= 3800 { return .fourK }
        if longEdge >= 1200 { return .hd }
        if longEdge > 0 { return .sd }
        return .unknown
    }

    private static func isSurround(channels: String) -> Bool {
        if channels.contains("5.1") || channels.contains("6.1") || channels.contains("7.1") {
            return true
        }
        if let count = Int(channels.prefix { $0.isNumber }) { return count >= 6 }
        return false
    }
}
