import CoreGraphics
import Foundation

struct PlaybackStatsRow: Equatable, Sendable {
    var label: String
    var value: String
}

struct PlaybackStatsSection: Equatable, Identifiable, Sendable {
    var title: String
    var rows: [PlaybackStatsRow]
    var id: String { title }
}

struct PlaybackStatsSnapshot: Equatable, Sendable {
    var sections: [PlaybackStatsSection]
}

enum PlaybackStats {
    static func aspectName(width: CGFloat, height: CGFloat) -> String {
        guard width > 0, height > 0 else { return "—" }
        let ratio = Double(width / height)
        let named: [(name: String, value: Double)] = [
            ("16:9", 16 / 9),
            ("16:10", 16 / 10),
            ("4:3", 4 / 3),
            ("21:9", 21 / 9),
            ("1.85:1", 1.85),
            ("2.39:1", 2.39)
        ]
        if let match = named.min(by: { abs($0.value - ratio) < abs($1.value - ratio) }),
           abs(match.value - ratio) < 0.04 {
            return match.name
        }
        return String(format: "%.2f:1", ratio)
    }

    static func bitrateLabel(_ bitsPerSecond: Int64) -> String {
        guard bitsPerSecond > 0 else { return "—" }
        let megabits = Double(bitsPerSecond) / 1_000_000
        if megabits >= 10 {
            return String(format: "%.1f Mbps", megabits)
        }
        if megabits >= 1 {
            return String(format: "%.2f Mbps", megabits)
        }
        return String(format: "%.0f kbps", Double(bitsPerSecond) / 1_000)
    }

    static func bytesLabel(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "—" }
        let gigabytes = Double(bytes) / 1_073_741_824
        if gigabytes >= 1 {
            return String(format: "%.2f GB", gigabytes)
        }
        let megabytes = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", megabytes)
    }

    static func bufferedAhead(
        ranges: [ClosedRange<Double>],
        playhead: TimeInterval
    ) -> TimeInterval {
        ranges
            .filter { $0.upperBound > playhead }
            .map(\.upperBound)
            .max()
            .map { max(0, $0 - playhead) } ?? 0
    }

    static func clockLabel(_ seconds: TimeInterval) -> String {
        PlaybackTimeFormatting.elapsed(seconds)
    }
}
