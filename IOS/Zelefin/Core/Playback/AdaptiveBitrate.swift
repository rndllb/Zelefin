import Foundation

enum NetworkTransport: Equatable, Sendable {
    case wifi
    case cellular
    case wired
    case other

    var title: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .wired: "Ethernet"
        case .other: "Network"
        }
    }
}

struct NetworkPathSnapshot: Equatable, Sendable {
    var transport: NetworkTransport
    var isExpensive: Bool
    var isConstrained: Bool
    var isSatisfied: Bool

    static let unknown = NetworkPathSnapshot(
        transport: .other,
        isExpensive: false,
        isConstrained: false,
        isSatisfied: false
    )

    /// Conservative budget when we have not measured this connection yet.
    var estimatedBitsPerSecond: Int {
        if !isSatisfied { return PlaybackQuality.kbps720.rawValue }
        if isConstrained { return PlaybackQuality.kbps720.rawValue }
        switch transport {
        case .wired:
            return PlaybackQuality.auto.bitsPerSecond
        case .wifi:
            return isExpensive ? PlaybackQuality.mbps8.rawValue : PlaybackQuality.mbps20.rawValue
        case .cellular:
            return isExpensive ? PlaybackQuality.mbps3.rawValue : PlaybackQuality.mbps6.rawValue
        case .other:
            return isExpensive ? PlaybackQuality.mbps3.rawValue : PlaybackQuality.mbps10.rawValue
        }
    }
}

struct BitrateProbeResult: Equatable, Sendable {
    var bitsPerSecond: Int
    var bytes: Int
    var elapsed: TimeInterval
    var transport: NetworkTransport
    var measuredAt: Date
}

enum AdaptiveBitratePolicy {
    static let utilization = 0.7
    static let cacheTTL: TimeInterval = 90
    static let playbackSampleBytes = 750_000
    static let settingsSampleBytes = 2_500_000
    /// Headroom so a title Direct Plays when it fits the pipe.
    static let directPlayMargin = 1.2

    static func budgetBitsPerSecond(measured: Int?, path: NetworkPathSnapshot) -> Int {
        let raw = measured ?? path.estimatedBitsPerSecond
        return max(PlaybackQuality.kbps420.rawValue, Int(Double(raw) * utilization))
    }

    static func quality(
        enabled: Bool,
        selected: PlaybackQuality,
        override: PlaybackQuality?,
        budgetBitsPerSecond: Int,
        sourceBitsPerSecond: Int?
    ) -> PlaybackQuality {
        if let override, override != .auto {
            return override
        }
        let ceiling = override == .auto ? .auto : selected
        guard enabled else { return ceiling }

        let networkQuality: PlaybackQuality
        if fitsDirectPlay(sourceBitsPerSecond: sourceBitsPerSecond, budgetBitsPerSecond: budgetBitsPerSecond) {
            networkQuality = .auto
        } else {
            networkQuality = PlaybackQuality.atOrBelow(budgetBitsPerSecond)
        }
        return PlaybackQuality.stricter(networkQuality, ceiling)
    }

    static func bitsPerSecond(
        enabled: Bool,
        selected: PlaybackQuality,
        override: PlaybackQuality?,
        budgetBitsPerSecond: Int,
        sourceBitsPerSecond: Int?
    ) -> Int {
        quality(
            enabled: enabled,
            selected: selected,
            override: override,
            budgetBitsPerSecond: budgetBitsPerSecond,
            sourceBitsPerSecond: sourceBitsPerSecond
        ).bitsPerSecond
    }

    static func fitsDirectPlay(sourceBitsPerSecond: Int?, budgetBitsPerSecond: Int) -> Bool {
        guard let source = sourceBitsPerSecond, source > 0 else {
            return budgetBitsPerSecond >= PlaybackQuality.mbps40.rawValue
        }
        return Double(source) * directPlayMargin <= Double(budgetBitsPerSecond)
    }

    static func isCacheValid(result: BitrateProbeResult?, path: NetworkPathSnapshot, now: Date = Date()) -> Bool {
        guard let result else { return false }
        guard result.transport == path.transport else { return false }
        return now.timeIntervalSince(result.measuredAt) < cacheTTL
    }
}

enum LiveAdaptiveAction: Equatable, Sendable {
    case none
    case stepDown
    case stepUp
}

struct LiveAdaptiveSample: Equatable, Sendable {
    var hasFirstFrame: Bool
    var isPaused: Bool
    var isSeeking: Bool
    var isRebuffering: Bool
    var bufferedAhead: TimeInterval
    var current: PlaybackQuality
    var ceiling: PlaybackQuality
    var sourceBitsPerSecond: Int?
}

struct LiveAdaptiveTracker: Equatable, Sendable {
    static let startupGrace: TimeInterval = 8
    static let rebufferConfirm: TimeInterval = 1.8
    static let healthyBuffer: TimeInterval = 12
    static let healthyHold: TimeInterval = 20

    var startedAt: Date
    var rebufferStartedAt: Date?
    var healthySince: Date?

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
    }

    mutating func action(now: Date, sample: LiveAdaptiveSample) -> LiveAdaptiveAction {
        if !sample.hasFirstFrame || sample.isPaused {
            return .none
        }
        if sample.isSeeking {
            rebufferStartedAt = nil
            healthySince = nil
            return .none
        }
        if now.timeIntervalSince(startedAt) < Self.startupGrace {
            return .none
        }

        if sample.isRebuffering {
            healthySince = nil
            let began = rebufferStartedAt ?? now
            rebufferStartedAt = began
            guard now.timeIntervalSince(began) >= Self.rebufferConfirm else { return .none }
            guard PlaybackQuality.stepDown(
                from: sample.current,
                sourceBitsPerSecond: sample.sourceBitsPerSecond
            ) != nil else { return .none }
            rebufferStartedAt = nil
            return .stepDown
        }

        rebufferStartedAt = nil
        if sample.bufferedAhead >= Self.healthyBuffer {
            let began = healthySince ?? now
            healthySince = began
            guard now.timeIntervalSince(began) >= Self.healthyHold else { return .none }
            guard PlaybackQuality.stepUp(
                from: sample.current,
                sourceBitsPerSecond: sample.sourceBitsPerSecond,
                ceiling: sample.ceiling
            ) != nil else { return .none }
            healthySince = nil
            return .stepUp
        }

        healthySince = nil
        return .none
    }
}

extension PlaybackQuality {
    static var ladder: [PlaybackQuality] {
        allCases.filter { $0 != .auto }.sorted { $0.rawValue < $1.rawValue }
    }

    static func atOrBelow(_ bitsPerSecond: Int) -> PlaybackQuality {
        if bitsPerSecond >= mbps80.rawValue { return .auto }
        let steps = PlaybackQuality.allCases.filter { $0 != .auto }.sorted { $0.rawValue > $1.rawValue }
        return steps.first { $0.rawValue <= bitsPerSecond } ?? .kbps420
    }

    static func stricter(_ lhs: PlaybackQuality, _ rhs: PlaybackQuality) -> PlaybackQuality {
        lhs.bitsPerSecond <= rhs.bitsPerSecond ? lhs : rhs
    }

    /// Next lower rung. From Direct Play / Auto this drops below the file bitrate so Jellyfin transcodes.
    static func stepDown(from current: PlaybackQuality, sourceBitsPerSecond: Int?) -> PlaybackQuality? {
        let limit: Int
        if current == .auto || sourceBitsPerSecond.map({ current.bitsPerSecond >= $0 }) == true {
            limit = sourceBitsPerSecond.map { max($0, 1) } ?? mbps40.rawValue
            return ladder.last { $0.rawValue < limit }
        }
        return ladder.last { $0.rawValue < current.rawValue }
    }

    /// One rung up, or Auto when that rung can carry the file again.
    static func stepUp(
        from current: PlaybackQuality,
        sourceBitsPerSecond: Int?,
        ceiling: PlaybackQuality
    ) -> PlaybackQuality? {
        guard current != .auto else { return nil }
        let nextStep = ladder.first { $0.rawValue > current.rawValue } ?? .auto
        var candidate = nextStep
        if ceiling != .auto {
            candidate = stricter(candidate, ceiling)
        }
        if AdaptiveBitratePolicy.fitsDirectPlay(
            sourceBitsPerSecond: sourceBitsPerSecond,
            budgetBitsPerSecond: candidate.bitsPerSecond
        ), ceiling == .auto {
            candidate = .auto
        }
        guard candidate.bitsPerSecond > current.bitsPerSecond else { return nil }
        return candidate
    }
}
