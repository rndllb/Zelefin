import XCTest
@testable import Zelefin

final class TitleShareTests: XCTestCase {
    private let server = URL(string: "https://media.example.com/jellyfin")!

    func testBuildsZelefinAndJellyfinURLs() {
        let item = MediaItem.previewMovie(id: "abc-123", name: "Dune: Part Two", year: 2024)
        let share = TitleShare.make(item: item, serverURL: server, serverName: "Home")
        XCTAssertEqual(share.zelefinURL.scheme, "zelefin")
        XCTAssertEqual(share.zelefinURL.host, "item")
        XCTAssertEqual(share.jellyfinURL.absoluteString, "https://media.example.com/jellyfin/web/index.html#!/details?id=abc-123")
        XCTAssertTrue(share.shareText.contains("Dune: Part Two (2024)"))
        XCTAssertTrue(share.shareText.contains(share.zelefinURL.absoluteString))
        XCTAssertTrue(share.shareText.contains(share.jellyfinURL.absoluteString))
    }

    func testEpisodeShareUsesSeriesID() {
        let episode = MediaItem.previewEpisode(seriesID: "show-1", seriesName: "Andor")
        let share = TitleShare.make(item: episode, serverURL: server, serverName: nil)
        XCTAssertEqual(share.itemID, "show-1")
        XCTAssertEqual(share.title, "Andor")
    }

    func testParsesZelefinURL() throws {
        let item = MediaItem.previewMovie(id: "abc-123", name: "Dune", year: 2021)
        let share = TitleShare.make(item: item, serverURL: server, serverName: nil)
        let incoming = try XCTUnwrap(TitleShare.parse(share.zelefinURL))
        XCTAssertEqual(incoming.itemID, "abc-123")
        XCTAssertEqual(TitleShare.fingerprint(incoming.serverURL), TitleShare.fingerprint(server))
    }

    func testParsesJellyfinWebURL() throws {
        let url = URL(string: "https://media.example.com/jellyfin/web/#/details?id=abc-123")!
        let incoming = try XCTUnwrap(TitleShare.parse(url))
        XCTAssertEqual(incoming.itemID, "abc-123")
        XCTAssertEqual(incoming.serverURL.absoluteString, "https://media.example.com/jellyfin")
    }

    func testParsesClassicJellyfinHashbangURL() throws {
        let url = URL(string: "https://media.example.com/jellyfin/web/index.html#!/details?id=abc-123")!
        let incoming = try XCTUnwrap(TitleShare.parse(url))
        XCTAssertEqual(incoming.itemID, "abc-123")
        XCTAssertEqual(incoming.serverURL.absoluteString, "https://media.example.com/jellyfin")
    }

    func testFingerprintIgnoresTrailingSlash() {
        let a = URL(string: "https://Media.Example.com/jellyfin/")!
        let b = URL(string: "https://media.example.com/jellyfin")!
        XCTAssertEqual(TitleShare.fingerprint(a), TitleShare.fingerprint(b))
    }

    func testIgnoresUnknownSchemes() {
        XCTAssertNil(TitleShare.parse(URL(string: "mailto:hi@example.com")!))
    }
}

private extension MediaItem {
    static func previewMovie(id: String, name: String, year: Int) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .movie,
            overview: nil,
            year: year,
            runtime: 7_200,
            officialRating: nil,
            genres: [],
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
            audioFormat: .unknown
        )
    }

    static func previewEpisode(seriesID: String, seriesName: String) -> MediaItem {
        MediaItem(
            id: "ep-9",
            name: "One Way Out",
            kind: .episode,
            overview: nil,
            year: 2022,
            runtime: 2_400,
            officialRating: nil,
            genres: [],
            seriesName: seriesName,
            seasonIndex: 1,
            episodeIndex: 10,
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
            seriesID: seriesID,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }
}
