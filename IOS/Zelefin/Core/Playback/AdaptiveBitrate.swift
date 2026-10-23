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
    /// Cellular and metered links swing more than Wi-Fi at home, so playback claims less of what
    /// was measured and lets the live monitor step up once the buffer proves the link holds.
    static let meteredUtilization = 0.5
    static let cacheTTL: TimeInterval = 90
    static let playbackSampleBytes = 750_000
    static let settingsSampleBytes = 2_500_000
    /// Headroom so a title Direct Plays when it fits the pipe.
    static let directPlayMargin = 1.2

    static func budgetBitsPerSecond(measured: Int?, path: NetworkPathSnapshot) -> Int {
        let raw = measured ?? path.estimatedBitsPerSecond
        let share = path.transport == .cellular || path.isExpensive || path.isConstrained
            ? meteredUtilization
            : utilization
        return max(PlaybackQuality.kbps420.rawValue, Int(Double(raw) * share))
    }

    /// A sample that runs out its whole timeout is itself a measurement: the link moved at most
    /// `bytes` in `timeout`. Returning nil there fell back to the optimistic path estimate, which is
    /// how a phone hotspot that reads as Wi-Fi ended up Direct Playing the original.
    /// Quick failures (an HTTP error, no route) carry no speed information and stay nil.
    static func timedOutProbe(
        bytes: Int,
        timeout: TimeInterval,
        elapsed: TimeInterval,
        transport: NetworkTransport,
        now: Date = Date()
    ) -> BitrateProbeResult? {
        guard timeout > 0, elapsed >= timeout * 0.9 else { return nil }
        return BitrateProbeResult(
            bitsPerSecond: Int(Double(bytes) * 8 / max(elapsed, timeout)),
            bytes: 0,
            elapsed: elapsed,
            transport: transport,
            measuredAt: now
        )
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

/// When a Direct Play read that has stopped receiving bytes counts as rebuffering.
/// AetherEngine keeps its audio clock running while the demuxer waits on the network, so the
/// engine never reports buffering for this; the reader is the only place that sees it.
enum ReaderStallPolicy {
    /// No bytes for this long while a read waits: the link has stalled, not just slowed.
    static let silence: TimeInterval = 3
    /// With this much video still buffered, a short silence is ridden out.
    static let comfortableBuffer: TimeInterval = 4
    /// A silence this long counts even if the engine still reports buffer ahead.
    static let hardSilence: TimeInterval = 8

    static func isStalled(secondsWithoutProgress: TimeInterval, bufferedAhead: TimeInterval) -> Bool {
        guard secondsWithoutProgress >= silence else { return false }
        return bufferedAhead < comfortableBuffer || secondsWithoutProgress >= hardSilence
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

/// Sums how long response bodies took to arrive, first byte to last, from `URLSessionTaskMetrics`.
///
/// A bitrate sample timed with a wall clock also counts DNS, TLS, the request round trip and the
/// server's time to first byte. On a 750 KB sample that latency is most of the elapsed time, so a fast
/// remote link measured as a slow one and Auto chose a server transcode over Direct Play.
final class TransferTimer: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var total: TimeInterval = 0

    var seconds: TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return total
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        guard let transfer = Self.transferSeconds(metrics.transactionMetrics.last) else { return }
        lock.lock()
        total += transfer
        lock.unlock()
    }

    /// Metrics can land just after the data call returns; wait a moment for them before falling back.
    func settledSeconds() async -> TimeInterval {
        for _ in 0..<10 where seconds == 0 {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return seconds
    }

    static func transferSeconds(_ transaction: URLSessionTaskTransactionMetrics?) -> TimeInterval? {
        guard let start = transaction?.responseStartDate, let end = transaction?.responseEndDate else { return nil }
        let seconds = end.timeIntervalSince(start)
        return seconds > 0 ? seconds : nil
    }

    /// Bits per second for `bytes`, timed by body transfer when metrics arrived, else by `wallClock`.
    static func bitsPerSecond(bytes: Int, transferSeconds: TimeInterval, wallClock: TimeInterval) -> Int {
        let elapsed = transferSeconds > 0 ? transferSeconds : wallClock
        return max(0, Int(Double(bytes) * 8 / max(elapsed, 0.02)))
    }
}
