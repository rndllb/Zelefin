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

    func testQuietHoursSameDayAndOvernight() {
        let morning = 9 * 60
        let evening = 17 * 60
        XCTAssertFalse(LibraryAlertSettings.isMinuteInQuietHours(morning - 1, start: morning, end: evening))
        XCTAssertTrue(LibraryAlertSettings.isMinuteInQuietHours(morning, start: morning, end: evening))
        XCTAssertTrue(LibraryAlertSettings.isMinuteInQuietHours(12 * 60, start: morning, end: evening))
        XCTAssertFalse(LibraryAlertSettings.isMinuteInQuietHours(evening, start: morning, end: evening))

        let night = 22 * 60
        let wake = 7 * 60
        XCTAssertFalse(LibraryAlertSettings.isMinuteInQuietHours(night - 1, start: night, end: wake))
        XCTAssertTrue(LibraryAlertSettings.isMinuteInQuietHours(night, start: night, end: wake))
        XCTAssertTrue(LibraryAlertSettings.isMinuteInQuietHours(0, start: night, end: wake))
        XCTAssertTrue(LibraryAlertSettings.isMinuteInQuietHours(wake - 1, start: night, end: wake))
        XCTAssertFalse(LibraryAlertSettings.isMinuteInQuietHours(wake, start: night, end: wake))
        XCTAssertFalse(LibraryAlertSettings.isMinuteInQuietHours(12 * 60, start: night, end: wake))
    }

    func testCompanionPluginNameMatches() {
        XCTAssertTrue(ZelefinCompanionPlugin.isInstalled(names: ["Zelefin"]))
        XCTAssertTrue(ZelefinCompanionPlugin.isInstalled(names: ["Jellyfin.Plugin.Zelefin"]))
        XCTAssertFalse(ZelefinCompanionPlugin.isInstalled(names: ["Intro Skipper"]))
    }
}
