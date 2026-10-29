import XCTest
@testable import Zelefin

final class HomeSnapshotStoreTests: XCTestCase {
    private var directory: URL!
    private var store: FileHomeSnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZelefinTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = FileHomeSnapshotStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        store = nil
    }

    func testRoundTripHomeAndLibraries() throws {
        let server = URL(string: "https://jellyfin.example.com")
        guard let server else {
            XCTFail("Server URL should parse")
            return
        }
        let item = sampleMovie()
        let snapshot = HomeSnapshot(
            version: HomeSnapshot.currentVersion,
            userID: "user-1",
            serverHost: HomeSnapshot.host(from: server),
            savedAt: Date(timeIntervalSince1970: 1_720_000_000),
            home: HomeLayout(
                featured: [item],
                sections: [
                    HomeSection(id: "continue", title: "Continue Watching", style: .landscape, items: [item])
                ]
            ),
            libraries: [
                MediaLibrary(id: "movies", name: "Movies", kind: .movie, libraryKind: .movies)
            ]
        )

        try store.save(snapshot)
        let loaded = try store.load(userID: "user-1", serverURL: server)

        XCTAssertEqual(loaded?.userID, "user-1")
        XCTAssertEqual(loaded?.home.sections.map(\.id), ["continue"])
        XCTAssertEqual(loaded?.home.featured.first?.name, "Dune")
        XCTAssertEqual(loaded?.libraries.map(\.name), ["Movies"])
        XCTAssertNil(loaded?.libraryPage)
    }

    func testRoundTripLibraryPageCards() throws {
        let server = try XCTUnwrap(URL(string: "https://jellyfin.example.com"))
        let movies = MediaLibrary(id: "movies", name: "Movies", kind: .movie, libraryKind: .movies)
        var page = LibraryPageCache()
        page.catalog = [movies]
        page.covers = ["movies": [sampleMovie()]]
        page.roomCounts = ["movies": LibraryRoomCounts(movies: 412, shows: 0, episodes: 0)]
        page.catalogCounts = ServerCatalogCounts(movies: 412, shows: 80, episodes: 3_100)
        page.detailedLibraryIDs = ["movies"]
        page.isLoaded = true
        let snapshot = HomeSnapshot(
            version: HomeSnapshot.currentVersion,
            userID: "user-1",
            serverHost: HomeSnapshot.host(from: server),
            savedAt: Date(timeIntervalSince1970: 1_720_000_000),
            home: HomeLayout(featured: [], sections: [
                HomeSection(id: "continue", title: "Continue Watching", style: .landscape, items: [sampleMovie()])
            ]),
            libraries: [movies],
            libraryPage: page
        )

        try store.save(snapshot)

        XCTAssertEqual(try store.load(userID: "user-1", serverURL: server)?.libraryPage, page)
    }

    func testUnknownUserReturnsNil() throws {
        let server = URL(string: "https://jellyfin.example.com")
        guard let server else {
            XCTFail("Server URL should parse")
            return
        }
        XCTAssertNil(try store.load(userID: "missing", serverURL: server))
    }

    func testStaleVersionIsDiscarded() throws {
        let server = URL(string: "https://jellyfin.example.com")
        guard let server else {
            XCTFail("Server URL should parse")
            return
        }
        let snapshot = HomeSnapshot(
            version: HomeSnapshot.currentVersion + 1,
            userID: "user-1",
            serverHost: HomeSnapshot.host(from: server),
            savedAt: Date(),
            home: HomeLayout(featured: [], sections: [
                HomeSection(id: "continue", title: "Continue Watching", style: .landscape, items: [sampleMovie()])
            ]),
            libraries: []
        )
        try store.save(snapshot)
        XCTAssertNil(try store.load(userID: "user-1", serverURL: server))
    }

    private func sampleMovie() -> MediaItem {
        MediaItem(
            id: "1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
            officialRating: "PG-13",
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 40,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: "tag",
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
            videoRange: .dolbyVision,
            audioFormat: .atmos
        )
    }
}
