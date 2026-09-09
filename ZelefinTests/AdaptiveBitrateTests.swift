import XCTest
@testable import Zelefin

final class AdaptiveBitrateTests: XCTestCase {
    func testCellularEstimateIsConservative() {
        let cellular = NetworkPathSnapshot(
            transport: .cellular,
            isExpensive: false,
            isConstrained: false,
            isSatisfied: true
        )
        XCTAssertEqual(cellular.estimatedBitsPerSecond, PlaybackQuality.mbps6.rawValue)

        let constrained = NetworkPathSnapshot(
            transport: .wifi,
            isExpensive: false,
            isConstrained: true,
            isSatisfied: true
        )
        XCTAssertEqual(constrained.estimatedBitsPerSecond, PlaybackQuality.kbps720.rawValue)
    }

    func testBudgetUsesSeventyPercentOfTheMeasurement() {
        let wifi = NetworkPathSnapshot(
            transport: .wifi,
            isExpensive: false,
            isConstrained: false,
            isSatisfied: true
        )
        XCTAssertEqual(
            AdaptiveBitratePolicy.budgetBitsPerSecond(measured: 10_000_000, path: wifi),
            7_000_000
        )
    }

    func testSmallFileOnFastLinkDirectPlays() {
        let quality = AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: .auto,
            override: nil,
            budgetBitsPerSecond: 20_000_000,
            sourceBitsPerSecond: 8_000_000
        )
        XCTAssertEqual(quality, .auto)
    }

    func testLargeFileOnSlowLinkStepsDown() {
        let quality = AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: .auto,
            override: nil,
            budgetBitsPerSecond: 5_000_000,
            sourceBitsPerSecond: 40_000_000
        )
        XCTAssertEqual(quality, .mbps4)
    }

    func testSelectedQualityCapsAdaptive() {
        let quality = AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: .mbps3,
            override: nil,
            budgetBitsPerSecond: 40_000_000,
            sourceBitsPerSecond: 8_000_000
        )
        XCTAssertEqual(quality, .mbps3)
    }

    func testManualOverrideSkipsAdaptive() {
        let quality = AdaptiveBitratePolicy.quality(
            enabled: true,
            selected: .auto,
            override: .mbps2,
            budgetBitsPerSecond: 40_000_000,
            sourceBitsPerSecond: 8_000_000
        )
        XCTAssertEqual(quality, .mbps2)
    }

    func testDisabledUsesSelectedQuality() {
        let quality = AdaptiveBitratePolicy.quality(
            enabled: false,
            selected: .mbps8,
            override: nil,
            budgetBitsPerSecond: 1_000_000,
            sourceBitsPerSecond: 40_000_000
        )
        XCTAssertEqual(quality, .mbps8)
    }

    func testCacheRequiresMatchingTransportAndAge() {
        let wifi = NetworkPathSnapshot(
            transport: .wifi,
            isExpensive: false,
            isConstrained: false,
            isSatisfied: true
        )
        let probe = BitrateProbeResult(
            bitsPerSecond: 12_000_000,
            bytes: 2_500_000,
            elapsed: 1,
            transport: .wifi,
            measuredAt: Date().addingTimeInterval(-10)
        )
        XCTAssertTrue(AdaptiveBitratePolicy.isCacheValid(result: probe, path: wifi))

        let cellular = NetworkPathSnapshot(
            transport: .cellular,
            isExpensive: false,
            isConstrained: false,
            isSatisfied: true
        )
        XCTAssertFalse(AdaptiveBitratePolicy.isCacheValid(result: probe, path: cellular))

        let stale = BitrateProbeResult(
            bitsPerSecond: 12_000_000,
            bytes: 2_500_000,
            elapsed: 1,
            transport: .wifi,
            measuredAt: Date().addingTimeInterval(-120)
        )
        XCTAssertFalse(AdaptiveBitratePolicy.isCacheValid(result: stale, path: wifi))
    }

    func testAtOrBelowSnapsToAQualityStep() {
        XCTAssertEqual(PlaybackQuality.atOrBelow(7_000_000), .mbps6)
        XCTAssertEqual(PlaybackQuality.atOrBelow(80_000_000), .auto)
        XCTAssertEqual(PlaybackQuality.atOrBelow(100_000), .kbps420)
    }

    func testStepDownFromDirectPlayGoesBelowTheFile() {
        XCTAssertEqual(
            PlaybackQuality.stepDown(from: .auto, sourceBitsPerSecond: 50_000_000),
            .mbps40
        )
        XCTAssertEqual(
            PlaybackQuality.stepDown(from: .mbps10, sourceBitsPerSecond: 50_000_000),
            .mbps8
        )
        XCTAssertNil(PlaybackQuality.stepDown(from: .kbps420, sourceBitsPerSecond: 50_000_000))
    }

    func testStepUpReturnsToDirectPlayWhenTheFileFits() {
        XCTAssertEqual(
            PlaybackQuality.stepUp(from: .mbps10, sourceBitsPerSecond: 50_000_000, ceiling: .auto),
            .mbps15
        )
        XCTAssertEqual(
            PlaybackQuality.stepUp(from: .mbps40, sourceBitsPerSecond: 50_000_000, ceiling: .auto),
            .auto
        )
        XCTAssertEqual(
            PlaybackQuality.stepUp(from: .mbps4, sourceBitsPerSecond: 50_000_000, ceiling: .mbps8),
            .mbps6
        )
        XCTAssertNil(PlaybackQuality.stepUp(from: .mbps8, sourceBitsPerSecond: 50_000_000, ceiling: .mbps8))
        XCTAssertNil(PlaybackQuality.stepUp(from: .auto, sourceBitsPerSecond: 50_000_000, ceiling: .auto))
    }

    func testLiveTrackerIgnoresStartupAndShortRebuffers() {
        var tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        let stall = liveSample(isRebuffering: true, current: .auto)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 3), sample: stall), .none)
        tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 9), sample: stall), .none)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 10.2), sample: stall), .none)
    }

    func testLiveTrackerStepsDownAfterASustainedStall() {
        var tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        let stall = liveSample(isRebuffering: true, current: .mbps10)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 9), sample: stall), .none)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 11), sample: stall), .stepDown)
    }

    func testLiveTrackerDoesNotTreatSeekingAsAStall() {
        var tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        let seeking = liveSample(isSeeking: true, isRebuffering: true, current: .mbps10)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 12), sample: seeking), .none)
        let stall = liveSample(isRebuffering: true, current: .mbps10)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 13), sample: stall), .none)
    }

    func testLiveTrackerStepsUpAfterAHealthyBuffer() {
        var tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        let healthy = liveSample(bufferedAhead: 16, current: .mbps10)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 10), sample: healthy), .none)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 31), sample: healthy), .stepUp)
    }

    func testLiveTrackerDoesNotStepUpOnAThinBuffer() {
        var tracker = LiveAdaptiveTracker(startedAt: Date(timeIntervalSince1970: 0))
        let thin = liveSample(bufferedAhead: 4, current: .mbps10)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 10), sample: thin), .none)
        XCTAssertEqual(tracker.action(now: Date(timeIntervalSince1970: 40), sample: thin), .none)
    }

    private func liveSample(
        isPaused: Bool = false,
        isSeeking: Bool = false,
        isRebuffering: Bool = false,
        bufferedAhead: TimeInterval = 20,
        current: PlaybackQuality,
        ceiling: PlaybackQuality = .auto,
        sourceBitsPerSecond: Int? = 40_000_000
    ) -> LiveAdaptiveSample {
        LiveAdaptiveSample(
            hasFirstFrame: true,
            isPaused: isPaused,
            isSeeking: isSeeking,
            isRebuffering: isRebuffering,
            bufferedAhead: bufferedAhead,
            current: current,
            ceiling: ceiling,
            sourceBitsPerSecond: sourceBitsPerSecond
        )
    }
}
