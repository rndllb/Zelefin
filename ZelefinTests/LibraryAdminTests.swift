import XCTest
@testable import Zelefin

final class LibraryAdminTests: XCTestCase {
    func testDisplayPreferencesRoundTripTabOrderAndMergedHome() {
        let defaults = UserDefaults.standard
        let previousOrder = defaults.string(forKey: AppTab.orderStorageKey)
        let previousMerge = defaults.object(forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
        defer {
            defaults.set(previousOrder, forKey: AppTab.orderStorageKey)
            defaults.set(previousMerge, forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
        }

        defaults.set(AppTab.defaultOrderRaw, forKey: AppTab.orderStorageKey)
        defaults.set(false, forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)

        DisplayPreferencesSync.apply([
            DisplayPreferencesSync.tabOrderKey: "home,library,movies",
            DisplayPreferencesSync.mergeContinueKey: "true"
        ])

        XCTAssertEqual(defaults.string(forKey: AppTab.orderStorageKey), "home,library,movies")
        XCTAssertTrue(HomeLayoutPreferences.mergeContinueAndNextUp)
        XCTAssertEqual(DisplayPreferencesSync.customPrefs()[DisplayPreferencesSync.mergeContinueKey], "true")
    }

    func testKindLabelsCoverLibraryTypes() {
        XCTAssertEqual(MediaKind.playlist.rawValue, "playlist")
        XCTAssertEqual(MediaKind.liveTV.rawValue, "liveTV")
        XCTAssertEqual(MediaKind.book.rawValue, "book")
        XCTAssertEqual(MediaKind.photo.rawValue, "photo")
        XCTAssertTrue(MediaKind.liveTV.usesVideoPlayer)
        XCTAssertFalse(MediaKind.photo.usesVideoPlayer)
        XCTAssertFalse(MediaKind.book.usesVideoPlayer)
        XCTAssertFalse(MediaKind.playlist.usesVideoPlayer)
    }

    func testActivityLogSubtitleJoinsTypeAndDetail() {
        let item = ActivityLogItem(
            id: "1",
            title: "User signed in",
            detail: "From the living room",
            date: Date(timeIntervalSince1970: 0),
            type: "SessionStart"
        )
        XCTAssertEqual(item.subtitle, "SessionStart · From the living room")
    }
}
