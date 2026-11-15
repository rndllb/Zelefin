import XCTest
@testable import Zelefin

final class CustomHomeRowsTests: XCTestCase {
    private let storageKey = CustomHomeRows.storageKey
    private let orderKey = HomeRowKind.orderStorageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        UserDefaults.standard.removeObject(forKey: orderKey)
        super.tearDown()
    }

    func testHomeRowSlotParsesCustomTokensAndOrders() {
        let customIDs: Set = ["a", "b"]
        let slots = HomeRowSlot.ordered(
            from: "featured,custom:a,continueWatching,custom:b,recentlyAddedMovies",
            customIDs: customIDs
        )
        XCTAssertEqual(
            slots.map(\.raw),
            [
                "featured",
                "custom:a",
                "continueWatching",
                "custom:b",
                "recentlyAddedMovies",
                "nextUp",
                "upcoming",
                "recommendations",
                "recentlyAddedShows",
                "collections",
                "genres",
                "recentlyWatched",
            ]
        )
        XCTAssertEqual(
            HomeRowSlot.rawOrder(slots),
            "featured,custom:a,continueWatching,custom:b,recentlyAddedMovies,nextUp,upcoming,recommendations,recentlyAddedShows,collections,genres,recentlyWatched"
        )
    }

    func testHomeRowSlotIgnoresUnknownCustomIDs() {
        let slots = HomeRowSlot.ordered(from: "custom:missing,featured", customIDs: ["live"])
        XCTAssertFalse(slots.map(\.raw).contains("custom:missing"))
        XCTAssertEqual(slots.first?.raw, "featured")
        XCTAssertTrue(slots.contains(.custom("live")))
    }

    func testCustomHomeRowRoundTripEncoding() {
        var query = CatalogBrowseQuery.default
        query.genres = ["Sci-Fi", "Drama"]
        query.sort = .dateAdded
        query.sortAscending = false
        let row = CustomHomeRow(
            id: "row-1",
            title: "New Releases",
            scope: CustomHomeRowScope.both.rawValue,
            query: CatalogBrowseQueryDto(query),
            enabled: true
        )
        let decoded = CustomHomeRows.decode(CustomHomeRows.encode([row]))
        XCTAssertEqual(decoded, [row])
        XCTAssertEqual(decoded.first?.browseQuery.genres, query.genres)
        XCTAssertEqual(decoded.first?.browseQuery.sort, .dateAdded)
        XCTAssertFalse(decoded.first?.browseQuery.sortAscending ?? true)
    }

    func testHomeFeedInterleavesCustomRows() {
        let custom = HomeSection(
            id: CustomHomeRows.sectionID(for: "abc"),
            title: "Filtered",
            style: .portrait,
            items: [Self.movie(id: "m1")]
        )
        let movies = HomeSection(
            id: "library-movies",
            title: "Recently Added Movies",
            style: .portrait,
            items: [Self.movie(id: "m2")]
        )
        let row = CustomHomeRow(id: "abc", title: "Filtered", enabled: true)
        UserDefaults.standard.set(CustomHomeRows.encode([row]), forKey: storageKey)
        let feed = HomeLayoutPreferences.feed(
            featured: [],
            sections: [movies, custom],
            slots: [
                .builtIn(.recentlyAddedMovies),
                .custom("abc"),
            ],
            hidden: []
        )
        XCTAssertEqual(feed.map(\.id), ["library-movies", CustomHomeRows.sectionID(for: "abc")])
    }
}

private extension CustomHomeRowsTests {
    static func movie(id: String) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            kind: .movie,
            overview: nil,
            year: 2025,
            runtime: nil,
            officialRating: nil,
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
    }
}