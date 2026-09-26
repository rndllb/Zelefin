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

    func testPublicConfigGatesRemoveFromContinueWatching() {
        let enabled = Data(#"{"RemoveContinueWatchingEnabled":true}"#.utf8)
        let disabled = Data(#"{"removeContinueWatchingEnabled":false}"#.utf8)
        let missing = Data(#"{}"#.utf8)
        XCTAssertTrue(JellyfinEnhancedJSON.removeContinueWatchingEnabled(from: enabled))
        XCTAssertFalse(JellyfinEnhancedJSON.removeContinueWatchingEnabled(from: disabled))
        XCTAssertFalse(JellyfinEnhancedJSON.removeContinueWatchingEnabled(from: missing))
    }

    func testRemovedContinueWatchingTitleStaysHidden() {
        let userID = "hide-test-\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: "zelefin.hidden-home.\(userID).continueWatching")
            UserDefaults.standard.removeObject(forKey: "zelefin.hidden-home.\(userID).nextUp")
        }
        HomeQueueHideStore.insert("episode-1", userID: userID, surface: .continueWatching)
        let items = [
            MediaItemTestsSupport.item(id: "episode-1", kind: .episode),
            MediaItemTestsSupport.item(id: "episode-2", kind: .episode)
        ]
        XCTAssertEqual(
            HomeQueueHideStore.filter(items, userID: userID, surface: .continueWatching).map(\.id),
            ["episode-2"]
        )
        XCTAssertEqual(
            HomeQueueHideStore.filter(items, userID: userID, surface: .nextUp).map(\.id),
            ["episode-1", "episode-2"]
        )
        HomeQueueHideStore.remove("episode-1", userID: userID)
        XCTAssertEqual(
            HomeQueueHideStore.filter(items, userID: userID, surface: .continueWatching).map(\.id),
            ["episode-1", "episode-2"]
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
        XCTAssertEqual(reviews[0].starsOutOfFive, 4)
        XCTAssertEqual(TMDBUserReview.averageStars(in: reviews), 4)
    }

    func testTMDBScoresMapOntoFiveStars() {
        XCTAssertEqual(TMDBUserReview(id: "1", author: "A", content: "", rating: 6).starsOutOfFive, 3)
        XCTAssertEqual(TMDBUserReview(id: "2", author: "B", content: "", rating: 7).starsOutOfFive, 3.5)
        XCTAssertNil(TMDBUserReview(id: "3", author: "C", content: "", rating: nil).starsOutOfFive)
        XCTAssertEqual(
            TMDBUserReview.averageStars(in: [
                TMDBUserReview(id: "1", author: "A", content: "", rating: 8),
                TMDBUserReview(id: "2", author: "B", content: "", rating: 6)
            ]),
            3.5
        )
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
        id: String = "1",
        kind: MediaKind,
        tmdbID: Int? = nil,
        videoRange: VideoRange = .sdr,
        audioFormat: AudioFormat = .unknown,
        videoResolution: VideoResolution = .unknown
    ) -> MediaItem {
        MediaItem(
            id: id,
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
