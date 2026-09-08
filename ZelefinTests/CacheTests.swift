import XCTest
@testable import Zelefin

final class ArtworkCacheKeyTests: XCTestCase {
    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testDiskKeyIgnoresAccessTokenAndRevision() throws {
        // The same image behind a different session token / cache-buster must resolve to one file.
        let a = try url("https://jf.example.com/Items/42/Images/Primary?quality=90&maxHeight=900&tag=abc&api_key=TOKEN1")
        let b = try url("https://jf.example.com/Items/42/Images/Primary?maxHeight=900&quality=90&tag=abc&api_key=TOKEN2&v=3")
        XCTAssertEqual(ArtworkCache.diskKey(for: a), ArtworkCache.diskKey(for: b))
    }

    func testDiskKeyDiffersByItemAndSize() throws {
        let base = try url("https://jf.example.com/Items/42/Images/Primary?quality=90&maxHeight=900&tag=abc&api_key=T")
        let otherItem = try url("https://jf.example.com/Items/99/Images/Primary?quality=90&maxHeight=900&tag=abc&api_key=T")
        let otherSize = try url("https://jf.example.com/Items/42/Images/Primary?quality=90&maxHeight=420&tag=abc&api_key=T")
        XCTAssertNotEqual(ArtworkCache.diskKey(for: base), ArtworkCache.diskKey(for: otherItem))
        XCTAssertNotEqual(ArtworkCache.diskKey(for: base), ArtworkCache.diskKey(for: otherSize))
    }

    func testGridPostersRequestTheHomeRowSize() {
        XCTAssertEqual(ArtworkURLBuilder.posterMaxHeight, 420)
    }

    func testPosterQueryUsesMaxHeightJpegLikeSwiftfin() {
        let query = ArtworkURLBuilder.queryItems(
            quality: 90,
            format: "jpg",
            maxHeight: 420,
            maxWidth: nil,
            tag: "abc",
            token: nil
        )
        XCTAssertEqual(query, ["quality=90", "format=jpg", "maxHeight=420", "tag=abc"])
        XCTAssertFalse(query.contains { $0.hasPrefix("fillWidth=") || $0.hasPrefix("fillHeight=") })
    }

    func testMoviesAndShowsWithoutAPosterTagAreNotRequested() {
        XCTAssertFalse(ArtworkURLBuilder.requestsPrimary(kind: .movie, tag: nil))
        XCTAssertFalse(ArtworkURLBuilder.requestsPrimary(kind: .series, tag: nil))
        XCTAssertTrue(ArtworkURLBuilder.requestsPrimary(kind: .movie, tag: "abc"))
        XCTAssertTrue(ArtworkURLBuilder.requestsPrimary(kind: .collection, tag: nil))
    }
}

final class CatalogSnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CatalogSnapshotTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func snapshot(userID: String, kind: LibraryKind, items: [MediaItem]) -> CatalogSnapshot {
        CatalogSnapshot(
            version: CatalogSnapshot.currentVersion,
            userID: userID,
            serverHost: "jf.example.com",
            libraryKind: kind,
            savedAt: Date(),
            items: items
        )
    }

    private func item(_ id: String, _ name: String) -> MediaItem {
        MediaItem(
            id: id, name: name, kind: .movie, overview: nil, year: 2020, runtime: nil,
            officialRating: nil, genres: [], seriesName: nil, seasonIndex: nil, episodeIndex: nil,
            playbackPosition: 0, unplayedCount: nil, isPlayed: false, primaryImageTag: "tag",
            thumbImageTag: nil, backdropImageTag: nil, backdropImageTags: [], logoImageTag: nil,
            parentBackdropItemID: nil, parentThumbItemID: nil, parentThumbImageTag: nil,
            parentLogoItemID: nil, parentLogoImageTag: nil, seriesThumbImageTag: nil, seriesID: nil,
            imageItemID: nil, queueKind: .nextUp, videoRange: .sdr, audioFormat: .unknown
        )
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = FileCatalogSnapshotStore(directory: directory)
        let server = try XCTUnwrap(URL(string: "https://jf.example.com"))
        let items = [item("1", "Arrival"), item("2", "Dune")]
        store.save(snapshot(userID: "u1", kind: .movies, items: items))

        let loaded = store.load(userID: "u1", serverURL: server, kind: .movies)
        XCTAssertEqual(loaded?.items, items)
    }

    func testLoadRejectsWrongUserOrKind() throws {
        let store = FileCatalogSnapshotStore(directory: directory)
        let server = try XCTUnwrap(URL(string: "https://jf.example.com"))
        store.save(snapshot(userID: "u1", kind: .movies, items: [item("1", "Arrival")]))

        XCTAssertNil(store.load(userID: "u2", serverURL: server, kind: .movies))
        XCTAssertNil(store.load(userID: "u1", serverURL: server, kind: .shows))
    }

    func testPosterPrefetchCoversEveryLibraryTab() {
        XCTAssertEqual(PosterPrefetcher.prefetchedKinds, [.movies, .shows, .collections])
    }

    func testPrefetchOrdersSmallestLibraryFirst() {
        XCTAssertEqual(
            PosterPrefetcher.orderedKinds(counts: [
                .movies: 800,
                .shows: 40,
                .collections: 12
            ]),
            [.collections, .shows, .movies]
        )
    }

    func testPrefetchLeavesCollectionCoversForOnScreenLoad() {
        XCTAssertFalse(PosterPrefetcher.prefetchesPosters(for: .collections))
        XCTAssertTrue(PosterPrefetcher.prefetchesPosters(for: .movies))
        XCTAssertTrue(PosterPrefetcher.prefetchesPosters(for: .shows))
        XCTAssertEqual(PosterPrefetcher.maxConcurrentDownloads, 2)
        XCTAssertEqual(ArtworkNetworkGate.maxPrefetch, 2)
    }

    func testIndexProgressReportsListingFraction() {
        let progress = CatalogIndexProgress.listing(loaded: 48, total: 240)
        XCTAssertEqual(progress.phase, .listing)
        XCTAssertEqual(progress.label, "Indexing")
        XCTAssertEqual(progress.fraction, 0.2, accuracy: 0.0001)
        XCTAssertFalse(progress.isFinished)
        XCTAssertTrue(CatalogIndexProgress.listing(loaded: 240, total: 240).isFinished)
    }

    func testPrefetchAcceptsJPEGAndPNGMagic() {
        XCTAssertTrue(ArtworkCache.isLikelyImage(Data([0xFF, 0xD8, 0xFF, 0xE0] + [UInt8](repeating: 0, count: 12))))
        XCTAssertTrue(ArtworkCache.isLikelyImage(Data([0x89, 0x50, 0x4E, 0x47] + [UInt8](repeating: 0, count: 12))))
        XCTAssertFalse(ArtworkCache.isLikelyImage(Data([UInt8](repeating: 0, count: 12))))
        XCTAssertFalse(ArtworkCache.isLikelyImage(Data()))
    }

    func testMissingPosterIsSettledSoProgressCanFinish() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkMissing-\(UUID().uuidString)", isDirectory: true)
        let cache = ArtworkCache(directory: directory)
        let url = try XCTUnwrap(URL(string: "https://jf.example.com/Items/1/Images/Primary?maxHeight=420"))
        XCTAssertFalse(cache.isSettled(for: url))
        cache.markMissing(url)
        XCTAssertTrue(cache.isSettled(for: url))
        XCTAssertEqual(cache.settledCount(in: [url]), 1)
        try? FileManager.default.removeItem(at: directory)
    }

    func testArtworkKindClassifiesJellyfinImagePaths() {
        XCTAssertEqual(
            ArtworkImageKind.classify(path: "/Items/1/Images/Primary"),
            .poster
        )
        XCTAssertEqual(
            ArtworkImageKind.classify(path: "/Items/1/Images/Thumb"),
            .poster
        )
        XCTAssertEqual(
            ArtworkImageKind.classify(path: "/Items/1/Images/Backdrop"),
            .backdrop
        )
        XCTAssertEqual(
            ArtworkImageKind.classify(path: "/Items/1/Images/Logo"),
            .logo
        )
        XCTAssertEqual(
            ArtworkImageKind.classify(path: "/Users/abc/Images/Primary"),
            .other
        )
    }

    func testArtworkUsageGroupsTaggedFilesAndSkipsMissingMarkers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtworkUsage-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 40).write(to: directory.appendingPathComponent("poster-aa"))
        try Data(repeating: 1, count: 25).write(to: directory.appendingPathComponent("backdrop-bb"))
        try Data(repeating: 1, count: 10).write(to: directory.appendingPathComponent("logo-cc"))
        try Data(repeating: 1, count: 7).write(to: directory.appendingPathComponent("legacyhash"))
        try Data().write(to: directory.appendingPathComponent("poster-aa.missing"))

        let usage = CacheInventory.artworkUsage(at: directory)
        XCTAssertEqual(usage.posters.bytes, 40)
        XCTAssertEqual(usage.backdrops.bytes, 25)
        XCTAssertEqual(usage.logos.bytes, 10)
        XCTAssertEqual(usage.other.bytes, 7)
        XCTAssertEqual(usage.total.fileCount, 4)

        CacheInventory.removeArtwork(.poster, from: directory)
        let after = CacheInventory.artworkUsage(at: directory)
        XCTAssertEqual(after.posters.bytes, 0)
        XCTAssertEqual(after.backdrops.bytes, 25)
        try? FileManager.default.removeItem(at: directory)
    }

    func testPrefetchKeepsDeclaredOrderWhenCountsTie() {
        XCTAssertEqual(
            PosterPrefetcher.orderedKinds(counts: [
                .movies: 10,
                .shows: 10,
                .collections: 10
            ]),
            [.movies, .shows, .collections]
        )
    }

    func testRemoveAllClearsEveryKind() throws {
        let store = FileCatalogSnapshotStore(directory: directory)
        let server = try XCTUnwrap(URL(string: "https://jf.example.com"))
        store.save(snapshot(userID: "u1", kind: .movies, items: [item("1", "Arrival")]))
        store.save(snapshot(userID: "u1", kind: .shows, items: [item("2", "Severance")]))

        store.removeAll(userID: "u1", serverURL: server)

        XCTAssertNil(store.load(userID: "u1", serverURL: server, kind: .movies))
        XCTAssertNil(store.load(userID: "u1", serverURL: server, kind: .shows))
    }
}
