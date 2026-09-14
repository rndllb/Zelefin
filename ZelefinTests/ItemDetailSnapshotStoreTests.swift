import XCTest
@testable import Zelefin

final class ItemDetailSnapshotStoreTests: XCTestCase {
    private var directory: URL!
    private var store: FileItemDetailSnapshotStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZelefinDetailTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = FileItemDetailSnapshotStore(directory: directory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        store = nil
    }

    func testRoundTripDetailSnapshot() throws {
        let server = try XCTUnwrap(URL(string: "https://jellyfin.example.com"))
        let snapshot = sampleSnapshot(userID: "user-1", itemID: "movie-1", server: server)

        try store.save(snapshot)
        let loaded = try store.load(userID: "user-1", serverURL: server, itemID: "movie-1")

        XCTAssertEqual(loaded?.item.name, "Dune")
        XCTAssertEqual(loaded?.related.map(\.id), ["rel-1"])
        XCTAssertEqual(loaded?.credits.map(\.name), ["Timothée Chalamet"])
        XCTAssertEqual(loaded?.trailers.map(\.id), ["yt-abc"])
        XCTAssertEqual(loaded?.collections.first?.collection.name, "Dune Collection")
    }

    func testUnknownTitleReturnsNil() throws {
        let server = try XCTUnwrap(URL(string: "https://jellyfin.example.com"))
        XCTAssertNil(try store.load(userID: "user-1", serverURL: server, itemID: "missing"))
    }

    func testStaleVersionIsDiscarded() throws {
        let server = try XCTUnwrap(URL(string: "https://jellyfin.example.com"))
        var snapshot = sampleSnapshot(userID: "user-1", itemID: "movie-1", server: server)
        snapshot.version = ItemDetailSnapshot.currentVersion + 1
        try store.save(snapshot)
        XCTAssertNil(try store.load(userID: "user-1", serverURL: server, itemID: "movie-1"))
    }

    func testPrunesOldestTitlesPastCap() throws {
        let server = try XCTUnwrap(URL(string: "https://jellyfin.example.com"))
        for index in 0..<(ItemDetailSnapshot.maxCachedTitles + 3) {
            try store.save(sampleSnapshot(userID: "user-1", itemID: "movie-\(index)", server: server))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, ItemDetailSnapshot.maxCachedTitles)
    }

    private func sampleSnapshot(userID: String, itemID: String, server: URL) -> ItemDetailSnapshot {
        let movie = sampleMovie(id: itemID, name: "Dune")
        return ItemDetailSnapshot(
            version: ItemDetailSnapshot.currentVersion,
            userID: userID,
            serverHost: SnapshotCoding.host(from: server),
            itemID: itemID,
            savedAt: Date(timeIntervalSince1970: 1_720_000_000),
            item: movie,
            trailers: [.youtube(id: "abc", title: "Official Trailer")],
            extras: [],
            related: [sampleMovie(id: "rel-1", name: "Dune: Part Two")],
            credits: [
                CreditPerson(id: "p1", name: "Timothée Chalamet", roleLabel: "Paul Atreides", imageTag: "tag", rank: 0)
            ],
            collections: [
                ItemCollectionMembership(
                    collection: sampleMovie(id: "col-1", name: "Dune Collection"),
                    items: [movie]
                )
            ],
            seasons: [],
            episodes: [],
            selectedSeasonID: nil
        )
    }

    private func sampleMovie(id: String, name: String) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
            officialRating: "PG-13",
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
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
