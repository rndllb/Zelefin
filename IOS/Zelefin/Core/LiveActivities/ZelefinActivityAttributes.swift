#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

/// Kind of Live Activity. One activity is kept per kind so ActivityKit's per-app cap is respected.
/// `playback` / `liveTV` remain for decoding older payloads only — video no longer starts them
/// (they conflict with Picture in Picture).
enum ZelefinActivityKind: String, Codable, Sendable, Hashable {
    case download
    case playback
    case syncPlay
    case liveTV
    case request
    case catalog
    case remoteSession
}

/// Shared Live Activity contract for the app and the widget extension. Keep this file in both targets.
struct ZelefinActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var fraction: Double?
        var statusLine: String
        var isPaused: Bool
        var isFinished: Bool
        var isFailed: Bool
        /// Interface accent hex (`#RRGGBB`). Defaults to periwinkle when omitted.
        var accentHex: String
        /// Short capsule label (e.g. DOWNLOADING, SYNCPLAY, PENDING).
        var badgeLabel: String?

        init(
            fraction: Double? = nil,
            statusLine: String,
            isPaused: Bool = false,
            isFinished: Bool = false,
            isFailed: Bool = false,
            accentHex: String = Self.defaultAccentHex,
            badgeLabel: String? = nil
        ) {
            self.fraction = fraction
            self.statusLine = statusLine
            self.isPaused = isPaused
            self.isFinished = isFinished
            self.isFailed = isFailed
            self.accentHex = accentHex
            self.badgeLabel = badgeLabel
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            fraction = try container.decodeIfPresent(Double.self, forKey: .fraction)
            statusLine = try container.decode(String.self, forKey: .statusLine)
            isPaused = try container.decodeIfPresent(Bool.self, forKey: .isPaused) ?? false
            isFinished = try container.decode(Bool.self, forKey: .isFinished)
            isFailed = try container.decode(Bool.self, forKey: .isFailed)
            accentHex = try container.decodeIfPresent(String.self, forKey: .accentHex) ?? Self.defaultAccentHex
            badgeLabel = try container.decodeIfPresent(String.self, forKey: .badgeLabel)
        }

        static let defaultAccentHex = "#9996D1"

        var percentText: String? {
            guard let fraction else { return nil }
            return "\(Int((fraction * 100).rounded()))%"
        }

        var clampedFraction: Double { min(max(fraction ?? 0, 0), 1) }
    }

    var kind: ZelefinActivityKind
    var title: String
    var subtitle: String
    /// Small JPEG thumbnail carried in the payload (no shared container).
    var posterThumbnail: Data?
}

/// Back-compat alias so older call sites / docs that say downloads still compile during migration.
typealias DownloadActivityAttributes = ZelefinActivityAttributes
#endif
