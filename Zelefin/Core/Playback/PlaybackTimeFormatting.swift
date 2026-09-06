import Foundation

/// Time labels in the same shape AVPlayerViewController uses: `m:ss` under an hour, `h:mm:ss` above.
enum PlaybackTimeFormatting {
    static func elapsed(_ seconds: TimeInterval) -> String {
        clock(max(0, seconds))
    }

    static func remaining(_ seconds: TimeInterval, duration: TimeInterval) -> String {
        guard duration > 0 else { return clock(0) }
        let leftover = max(0, duration - seconds)
        return "-\(clock(leftover))"
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.towardZero))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(secs))"
        }
        return "\(minutes):\(twoDigits(secs))"
    }

    private static func twoDigits(_ value: Int) -> String {
        String(format: "%02d", value)
    }
}

enum AVKitPlaybackSpeed {
    static let options: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]
    static let skipInterval: TimeInterval = 10
}
