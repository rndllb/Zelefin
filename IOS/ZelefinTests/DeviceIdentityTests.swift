import XCTest
@testable import Zelefin

final class DeviceIdentityTests: XCTestCase {
    func testMapsCurrentIPhoneAndIPadModels() {
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPhone18,1"), "iPhone 17 Pro")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPhone18,2"), "iPhone 17 Pro Max")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPhone18,3"), "iPhone 17")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad17,3"), "iPad Pro 13-inch (M5)")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad17,1"), "iPad Pro 11-inch (M5)")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad16,5"), "iPad Pro 13-inch (M4)")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad16,1"), "iPad mini (A17 Pro)")
    }

    func testUnknownIdentifiersKeepTheDeviceFamily() {
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPhone99,1"), "iPhone")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPad99,1"), "iPad")
        XCTAssertEqual(DeviceIdentity.marketingName(for: "iPod9,1"), "iPod touch")
    }
}
