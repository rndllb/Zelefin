import XCTest
@testable import Zelefin

final class JellyfinEnhancedPluginTests: XCTestCase {
    func testDetectsPluginName() {
        XCTAssertTrue(JellyfinEnhancedPlugin.isInstalled(names: ["Jellyfin Enhanced"]))
        XCTAssertTrue(JellyfinEnhancedPlugin.isInstalled(names: ["jellyfin-enhanced"]))
        XCTAssertFalse(JellyfinEnhancedPlugin.isInstalled(names: ["Intro Skipper", "Open Subtitles"]))
        XCTAssertFalse(JellyfinEnhancedPlugin.isInstalled(names: ["File Transformation"]))
    }

    func testHidePathUsesQueueKind() {
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.surface(queueKind: .resume),
            .continueWatching
        )
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.surface(queueKind: .nextUp),
            .nextUp
        )
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.path(itemID: "abc-def", surface: .continueWatching),
            "/JellyfinEnhanced/continue-watching/hide/abc-def"
        )
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.path(itemID: "abc def", surface: .nextUp),
            "/JellyfinEnhanced/next-up/hide/abc%20def"
        )
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.menuTitle(for: .continueWatching),
            "Remove from Continue Watching"
        )
        XCTAssertEqual(
            JellyfinEnhancedHomeHide.menuTitle(for: .nextUp),
            "Remove from Next Up"
        )
    }

    func testReviewKeyUsesMovieAndShowTMDB() {
        var movie = MediaItemTestsSupport.item(kind: .movie, tmdbID: 27205)
        XCTAssertEqual(JellyfinEnhancedReviewKey.target(for: movie)?.mediaType, "movie")
        XCTAssertEqual(JellyfinEnhancedReviewKey.target(for: movie)?.tmdbID, "27205")

        movie.tmdbID = nil
        XCTAssertNil(JellyfinEnhancedReviewKey.target(for: movie))

        let show = MediaItemTestsSupport.item(kind: .series, tmdbID: 1396)
        XCTAssertEqual(JellyfinEnhancedReviewKey.target(for: show)?.mediaType, "tv")
    }

    func testReviewPayloadValidation() {
        XCTAssertTrue(JellyfinEnhancedReviewPayload.isValid(content: "Great", rating: nil))
        XCTAssertTrue(JellyfinEnhancedReviewPayload.isValid(content: "", rating: 4.5))
        XCTAssertTrue(JellyfinEnhancedReviewPayload.isValid(content: "Great", rating: 5))
        XCTAssertFalse(JellyfinEnhancedReviewPayload.isValid(content: "", rating: nil))
        XCTAssertFalse(JellyfinEnhancedReviewPayload.isValid(content: "", rating: 4.3))
        XCTAssertFalse(JellyfinEnhancedReviewPayload.isValid(content: "", rating: 0))
        XCTAssertFalse(JellyfinEnhancedReviewPayload.isValid(content: String(repeating: "a", count: 2001), rating: 5))
    }

    func testDecodesCamelCaseReviews() throws {
        let data = """
        {"reviews":[{"userId":"abc","userName":"Ada","content":"Loved it","rating":4.5,"createdAt":"2026-01-03T12:00:00.000Z"}]}
        """.data(using: .utf8)!
        let reviews = JellyfinEnhancedJSON.reviews(from: data)
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].userName, "Ada")
        XCTAssertEqual(reviews[0].rating, 4.5)
        XCTAssertTrue(reviews[0].isAuthored(by: "ABC"))
        XCTAssertEqual(JellyfinEnhancedReview.averageRating(in: reviews), 4.5)
    }

    func testDecodesPascalCaseAwards() throws {
        let data = """
        {"Found":true,"Wins":2,"Nominations":1,"Awards":[{"Name":"Academy Awards","Result":"Won","Year":2024,"Recipients":["Jane Doe"]}]}
        """.data(using: .utf8)!
        let awards = JellyfinEnhancedJSON.awards(from: data)
        XCTAssertFalse(awards.isEmpty)
        XCTAssertEqual(awards.summary, "2 wins · 1 nomination")
        XCTAssertEqual(awards.awards.first?.detailLine, "Jane Doe")
        XCTAssertTrue(awards.awards.first?.isWin == true)
    }

    func testDecodesTMDBReviews() {
        let data = """
        {"results":[{"id":"1","author":"Chris","content":"A landmark film.","author_details":{"rating":8}}]}
        """.data(using: .utf8)!
        let reviews = JellyfinEnhancedJSON.tmdbReviews(from: data)
        XCTAssertEqual(reviews.count, 1)
        XCTAssertEqual(reviews[0].author, "Chris")
        XCTAssertEqual(reviews[0].rating, 8)
    }
}

final class PosterQualityBadgesTests: XCTestCase {
    func testShowsFourKHDRAndAtmos() {
        let item = MediaItemTestsSupport.item(
            kind: .movie,
            videoRange: .dolbyVision,
            audioFormat: .atmos,
            videoResolution: .fourK
        )
        XCTAssertEqual(
            PosterQualityBadges.badges(for: item),
            [.fourK, .hdr("DV"), .atmos]
        )
    }

    func testShowsHDForCommon1080p() {
        let item = MediaItemTestsSupport.item(
            kind: .movie,
            videoRange: .sdr,
            audioFormat: .surround,
            videoResolution: .hd
        )
        XCTAssertEqual(PosterQualityBadges.badges(for: item), [.hd])
    }

    func testHidesUnknownSDR() {
        let item = MediaItemTestsSupport.item(
            kind: .movie,
            videoRange: .sdr,
            audioFormat: .stereo,
            videoResolution: .unknown
        )
        XCTAssertTrue(PosterQualityBadges.badges(for: item).isEmpty)
    }

    func testMapsWidthToFourK() {
        XCTAssertEqual(ItemMapper.videoResolution(width: 3840, height: 2160), .fourK)
        XCTAssertEqual(ItemMapper.videoResolution(width: 1920, height: 1080), .hd)
        XCTAssertEqual(ItemMapper.videoResolution(width: nil, height: nil), .unknown)
    }
}

private enum MediaItemTestsSupport {
    static func item(
        kind: MediaKind,
        tmdbID: Int? = nil,
        videoRange: VideoRange = .sdr,
        audioFormat: AudioFormat = .unknown,
        videoResolution: VideoResolution = .unknown
    ) -> MediaItem {
        MediaItem(
            id: "1",
            name: "Title",
            kind: kind,
            overview: nil,
            year: 2024,
            runtime: nil,
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
            videoRange: videoRange,
            audioFormat: audioFormat,
            videoResolution: videoResolution,
            tmdbID: tmdbID
        )
    }
}
