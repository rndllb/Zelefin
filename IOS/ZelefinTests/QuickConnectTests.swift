import XCTest
@testable import Zelefin

final class QuickConnectTests: XCTestCase {
    func testGroupsSixCharacterCode() {
        let handshake = QuickConnectHandshake(code: "148293", secret: "secret")
        XCTAssertEqual(handshake.groupedCode, "148  293")
    }

    func testLeavesOtherCodesUngrouped() {
        let handshake = QuickConnectHandshake(code: "12", secret: "secret")
        XCTAssertEqual(handshake.groupedCode, "12")
    }

    func testReadsEnabledFlagFromJSONBoolean() {
        XCTAssertEqual(QuickConnectClient.enabledFlag(from: Data("true".utf8)), true)
        XCTAssertEqual(QuickConnectClient.enabledFlag(from: Data("false".utf8)), false)
    }

    func testQuickConnectDisabledCopy() {
        XCTAssertEqual(
            ZelefinError.quickConnectDisabled.errorDescription,
            "Quick Connect is turned off on this server."
        )
    }
}
