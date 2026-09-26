import XCTest
@testable import Zelefin

final class LibraryAdminTests: XCTestCase {
    func testDisplayPreferencesRoundTripTabOrderAndMergedHome() {
        let defaults = UserDefaults.standard
        let previousOrder = defaults.string(forKey: AppTab.orderStorageKey)
        let previousMerge = defaults.object(forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
        let previousHomeOrder = defaults.string(forKey: HomeRowKind.orderStorageKey)
        let previousHomeHidden = defaults.string(forKey: HomeRowKind.hiddenStorageKey)
        let previousHero = defaults.string(forKey: FeaturedHeroContent.storageKey)
        let previousLibraryOrder = defaults.string(forKey: LibraryLayoutPreferences.orderKey)
        let previousLibraryHidden = defaults.string(forKey: LibraryLayoutPreferences.hiddenKey)
        let previousLibraryPageHidden = defaults.string(forKey: LibraryLayoutPreferences.pageHiddenKey)
        defer {
            defaults.set(previousOrder, forKey: AppTab.orderStorageKey)
            defaults.set(previousMerge, forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
            defaults.set(previousHomeOrder, forKey: HomeRowKind.orderStorageKey)
            defaults.set(previousHomeHidden, forKey: HomeRowKind.hiddenStorageKey)
            defaults.set(previousHero, forKey: FeaturedHeroContent.storageKey)
            defaults.set(previousLibraryOrder, forKey: LibraryLayoutPreferences.orderKey)
            defaults.set(previousLibraryHidden, forKey: LibraryLayoutPreferences.hiddenKey)
            defaults.set(previousLibraryPageHidden, forKey: LibraryLayoutPreferences.pageHiddenKey)
        }

        defaults.set(AppTab.defaultOrderRaw, forKey: AppTab.orderStorageKey)
        defaults.set(false, forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
        defaults.set(HomeRowKind.defaultOrderRaw, forKey: HomeRowKind.orderStorageKey)
        defaults.set("", forKey: HomeRowKind.hiddenStorageKey)

        DisplayPreferencesSync.apply([
            DisplayPreferencesSync.tabOrderKey: "home,library,movies",
            DisplayPreferencesSync.mergeContinueKey: "true",
            DisplayPreferencesSync.homeRowOrderKey: "genres,featured",
            DisplayPreferencesSync.homeRowHiddenKey: "upcoming,collections",
            DisplayPreferencesSync.featuredHeroContentKey: FeaturedHeroContent.random.rawValue,
            DisplayPreferencesSync.libraryOrderKey: "anime,movies",
            DisplayPreferencesSync.libraryHiddenKey: "livetv",
            DisplayPreferencesSync.libraryPageHiddenKey: "collections"
        ])

        XCTAssertEqual(defaults.string(forKey: AppTab.orderStorageKey), "home,library,movies")
        XCTAssertTrue(HomeLayoutPreferences.mergeContinueAndNextUp)
        XCTAssertEqual(DisplayPreferencesSync.customPrefs()[DisplayPreferencesSync.mergeContinueKey], "true")
        XCTAssertEqual(
            HomeRowKind.ordered(from: defaults.string(forKey: HomeRowKind.orderStorageKey) ?? "").prefix(2).map(\.rawValue),
            ["genres", "featured"]
        )
        XCTAssertEqual(
            HomeRowKind.hidden(from: defaults.string(forKey: HomeRowKind.hiddenStorageKey) ?? ""),
            [.upcoming, .collections]
        )
        XCTAssertEqual(FeaturedHeroContent.current, .random)
        XCTAssertEqual(
            DisplayPreferencesSync.customPrefs()[DisplayPreferencesSync.featuredHeroContentKey],
            FeaturedHeroContent.random.rawValue
        )
        XCTAssertEqual(defaults.string(forKey: LibraryLayoutPreferences.orderKey), "anime,movies")
        XCTAssertEqual(LibraryLayoutPreferences.hiddenIDs(from: defaults.string(forKey: LibraryLayoutPreferences.hiddenKey) ?? ""), ["livetv"])
        XCTAssertEqual(
            LibraryLayoutPreferences.hiddenBlocks(from: defaults.string(forKey: LibraryLayoutPreferences.pageHiddenKey) ?? ""),
            [.collections]
        )
        XCTAssertEqual(LibraryLayoutPreferences.hiddenBlocks(from: ""), [.collections])
        XCTAssertEqual(LibraryLayoutPreferences.hiddenBlocks(from: "none"), [])
        XCTAssertEqual(LibraryLayoutPreferences.pageHiddenRaw(from: []), "none")
        XCTAssertEqual(
            LibraryRoomCounts(movies: 12, shows: 1, episodes: 40).caption,
            "12 movies · 1 show · 40 episodes"
        )
        XCTAssertNil(LibraryRoomCounts(movies: 0, shows: 0, episodes: 0).caption)
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
