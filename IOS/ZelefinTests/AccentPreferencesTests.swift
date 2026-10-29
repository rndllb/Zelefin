import SwiftUI
import XCTest
@testable import Zelefin

final class AccentPreferencesTests: XCTestCase {
    func testDefaultPresetIsTheSignInPeriwinkle() {
        XCTAssertEqual(AccentPreferences.defaultId, "periwinkle")
        XCTAssertEqual(AccentPreferences.periwinkle.hex, "#9996D1")
        XCTAssertEqual(AccentPreferences.hex(from: LoginPalette.periwinkle), AccentPreferences.periwinkle.hex)
        XCTAssertEqual(AccentPreferences.preset(id: "missing").id, "periwinkle")
        XCTAssertEqual(AccentPreferences.preset(id: "cyan").hex, "#2AD4FC")
    }

    func testNormalizedHexAcceptsWithAndWithoutHash() {
        XCTAssertEqual(AccentPreferences.normalizedHex("#2ad4fc"), "#2AD4FC")
        XCTAssertEqual(AccentPreferences.normalizedHex("2AD4FC"), "#2AD4FC")
        XCTAssertNil(AccentPreferences.normalizedHex("#FFF"))
        XCTAssertNil(AccentPreferences.normalizedHex("not-a-color"))
    }

    func testColorRoundTripFromHex() {
        let color = AccentPreferences.color(fromHex: "#2AD4FC")
        XCTAssertNotNil(color)
        XCTAssertEqual(AccentPreferences.hex(from: color!), "#2AD4FC")
    }

    func testCustomPresetUsesHex() {
        let preset = AccentPreferences.preset(id: AccentPreferences.customId, customHex: "#FA2D48")
        XCTAssertEqual(preset.id, "custom")
        XCTAssertEqual(preset.hex, "#FA2D48")
        XCTAssertEqual(AccentPreferences.hex(from: preset.color), "#FA2D48")
    }

    func testNamedPresetResolvesById() {
        let red = AccentPreferences.preset(id: "red")
        XCTAssertEqual(red.name, "Red")
        XCTAssertEqual(red.hex, "#FA2D48")
    }
}
