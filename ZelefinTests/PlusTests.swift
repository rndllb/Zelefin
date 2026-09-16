import XCTest
@testable import Zelefin

final class PlusStatusResolverTests: XCTestCase {
    func testReviewDemoUnlocksEvenWhenStoreIsEmpty() {
        let status = PlusStatusResolver.status(
            isReviewDemo: true,
            debugOverride: .free,
            hasLifetime: false,
            hasAnnual: false,
            annualIsTrial: false
        )
        XCTAssertEqual(status, .lifetime)
        XCTAssertTrue(status.isUnlocked)
    }

    func testStoreWithNoEntitlementsIsLocked() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .store,
            hasLifetime: false,
            hasAnnual: false,
            annualIsTrial: false
        )
        XCTAssertEqual(status, .locked)
        XCTAssertFalse(status.isUnlocked)
    }

    func testLifetimeBeatsAnnual() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .store,
            hasLifetime: true,
            hasAnnual: true,
            annualIsTrial: true
        )
        XCTAssertEqual(status, .lifetime)
    }

    func testAnnualTrialIsTrial() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .store,
            hasLifetime: false,
            hasAnnual: true,
            annualIsTrial: true
        )
        XCTAssertEqual(status, .trial)
        XCTAssertTrue(status.isUnlocked)
    }

    func testPaidAnnualIsPlus() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .store,
            hasLifetime: false,
            hasAnnual: true,
            annualIsTrial: false
        )
        XCTAssertEqual(status, .plus)
    }

    func testDebugOverrideFreeLocks() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .free,
            hasLifetime: true,
            hasAnnual: true,
            annualIsTrial: false
        )
        XCTAssertEqual(status, .locked)
    }

    func testDebugOverridePlusUnlocksWithoutStore() {
        let status = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: .plus,
            hasLifetime: false,
            hasAnnual: false,
            annualIsTrial: false
        )
        XCTAssertEqual(status, .plus)
    }

    func testNilOverrideUsesStore() {
        let locked = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: nil,
            hasLifetime: false,
            hasAnnual: false,
            annualIsTrial: false
        )
        let unlocked = PlusStatusResolver.status(
            isReviewDemo: false,
            debugOverride: nil,
            hasLifetime: false,
            hasAnnual: true,
            annualIsTrial: false
        )
        XCTAssertEqual(locked, .locked)
        XCTAssertEqual(unlocked, .plus)
    }
}

final class PlusProductTests: XCTestCase {
    func testProductIDs() {
        XCTAssertEqual(PlusProductID.annual.rawValue, "app.zelefin.plus.annual")
        XCTAssertEqual(PlusProductID.lifetime.rawValue, "app.zelefin.plus.lifetime")
        XCTAssertEqual(PlusProductID.allCases.count, 2)
        XCTAssertEqual(PlusProductID.annual.fallbackPrice, "$9.99/year")
        XCTAssertEqual(PlusProductID.lifetime.fallbackPrice, "$24.99")
        XCTAssertFalse(PlusProductID.annual.subtitle.isEmpty)
        XCTAssertFalse(PlusProductID.lifetime.subtitle.isEmpty)
    }

    func testFeaturesHaveCopy() {
        for feature in PlusFeature.allCases {
            XCTAssertFalse(feature.paywallTitle.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.paywallMessage.isEmpty, feature.rawValue)
            XCTAssertFalse(feature.systemImage.isEmpty, feature.rawValue)
            XCTAssertTrue(feature.lockMessage.contains("Plus"), feature.rawValue)
        }
    }

    func testStatusLabels() {
        XCTAssertEqual(PlusStatus.locked.settingsLabel, "Not included")
        XCTAssertEqual(PlusStatus.trial.settingsLabel, "Free trial")
        XCTAssertEqual(PlusStatus.plus.settingsLabel, "Annual")
        XCTAssertEqual(PlusStatus.lifetime.settingsLabel, "Lifetime")
    }
}
