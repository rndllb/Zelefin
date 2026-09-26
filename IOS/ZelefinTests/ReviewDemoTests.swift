import XCTest
@testable import Zelefin

final class ReviewDemoTests: XCTestCase {
    func testSessionUsesDedicatedReviewIdentity() {
        XCTAssertEqual(ReviewDemo.userID, "zelefin.review.demo")
        XCTAssertTrue(ReviewDemo.isSession(ReviewDemo.session))
        XCTAssertFalse(ReviewDemo.isSession(nil))
    }

    func testCatalogHasMoviesShowsAndPlayback() {
        XCTAssertEqual(ReviewDemoCatalog.movies.count, 6)
        XCTAssertEqual(ReviewDemoCatalog.shows.count, 3)
        XCTAssertEqual(ReviewDemoCatalog.episodes.count, 6)
        XCTAssertFalse(ReviewDemoCatalog.continueWatching.isEmpty)
        XCTAssertEqual(ReviewDemoCatalog.item(id: "demo-movie-harbor")?.name, "Harbor Lights")
        XCTAssertEqual(ReviewDemoCatalog.sampleStreamURL.host, "commondatastorage.googleapis.com")
    }

    func testSearchAndGenreBrowse() {
        XCTAssertTrue(ReviewDemoCatalog.search(term: "harbor").contains { $0.id == "demo-movie-harbor" })
        XCTAssertTrue(ReviewDemoCatalog.items(genreID: "demo-genre-drama").contains { $0.id == "demo-movie-harbor" })
        XCTAssertEqual(ReviewDemoCatalog.items(parentID: "demo-col-atlantic").count, 3)
    }

    func testArtworkURLUsesUnsplash() {
        let url = ReviewDemoCatalog.artworkURL(for: ReviewDemoCatalog.harborLights, portrait: true)
        XCTAssertEqual(url?.host, "images.unsplash.com")
        XCTAssertTrue(url?.path.contains("1489599849927") == true)
    }
}
