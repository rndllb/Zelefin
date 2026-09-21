import XCTest
@testable import Zelefin

final class LibraryAlertTests: XCTestCase {
    func testNotificationPayloadOpensTheLibraryItem() {
        let alert = LibraryAlert.addedToLibrary(body: "Andor (2022)", itemID: "andor", id: "a1")
        XCTAssertEqual(
            LibraryAlertDestination.parse(LibraryAlertCenter.userInfo(for: alert)),
            .libraryItem("andor")
        )
    }

    func testNotificationPayloadOpensScheduledTasks() {
        let alert = LibraryAlert.scheduledTaskStarted(name: "Scan media library", id: "scan")
        XCTAssertEqual(
            LibraryAlertDestination.parse(LibraryAlertCenter.userInfo(for: alert)),
            .scheduledTasks
        )
    }

    func testNotificationPayloadReadsPushItemId() {
        let userInfo: [AnyHashable: Any] = ["itemId": "andor", "type": "ItemAdded"]
        XCTAssertEqual(LibraryAlertDestination.parse(userInfo), .libraryItem("andor"))
    }

    func testCompanionPluginNameMatches() {
        XCTAssertTrue(ZelefinCompanionPlugin.isInstalled(names: ["Zelefin"]))
        XCTAssertTrue(ZelefinCompanionPlugin.isInstalled(names: ["Jellyfin.Plugin.Zelefin"]))
        XCTAssertFalse(ZelefinCompanionPlugin.isInstalled(names: ["Intro Skipper"]))
    }
}
