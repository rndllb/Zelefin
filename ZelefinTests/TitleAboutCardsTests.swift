import XCTest
@testable import Zelefin

final class TitleAboutCardsTests: XCTestCase {
    func testOrdersSynopsisThenRatings() {
        var item = movie(
            genres: ["Action", "Crime", "Thriller"],
            overview: "As a young boy, Bruce Wayne watched in horror.",
            rating: "PG-13"
        )
        item.criticRating = 85

        let cards = TitleAboutCards.cards(for: item)
        XCTAssertEqual(cards.count, 3)
        guard case let .synopsis(title, genres, overview) = cards[0] else {
            return XCTFail("Expected synopsis first")
        }
        XCTAssertEqual(title, "Batman Begins")
        XCTAssertEqual(genres, "ACTION, CRIME, THRILLER")
        XCTAssertEqual(overview, "As a young boy, Bruce Wayne watched in horror.")

        guard case let .tomatometer(score, isFresh, meaning) = cards[1] else {
            return XCTFail("Expected tomatometer second")
        }
        XCTAssertEqual(score, 85)
        XCTAssertTrue(isFresh)
        XCTAssertTrue(meaning.contains("Fresh"))

        guard case let .commonSense(age, meaning) = cards[2] else {
            return XCTFail("Expected common sense third")
        }
        XCTAssertEqual(age, "13+")
        XCTAssertTrue(meaning.contains("13"))
    }

    func testHidesRatingCardsWithoutData() {
        let item = movie(genres: ["Drama"], overview: "A quiet story.", rating: nil)
        let cards = TitleAboutCards.cards(for: item)
        XCTAssertEqual(cards.map(\.id), ["synopsis"])
    }

    func testHidesRowWithoutAboutContent() {
        let item = movie(genres: [], overview: nil, rating: nil)
        XCTAssertTrue(TitleAboutCards.cards(for: item).isEmpty)
    }

    func testRottenTomatometerCopy() {
        XCTAssertTrue(TitleAboutCards.tomatometerMeaning(score: 42).contains("Rotten"))
        XCTAssertFalse(TitleAboutCards.tomatometerMeaning(score: 42).contains("Fresh"))
        XCTAssertTrue(TitleAboutCards.tomatometerMeaning(score: 60).contains("Fresh"))
    }

    func testCommonSenseUsesOfficialRating() {
        XCTAssertTrue(
            TitleAboutCards.commonSenseMeaning(officialRating: "R", ageGate: "17+")
                .localizedCaseInsensitiveContains("Restricted")
        )
        XCTAssertTrue(
            TitleAboutCards.commonSenseMeaning(officialRating: "TV-MA", ageGate: "17+")
                .localizedCaseInsensitiveContains("Restricted")
        )
        XCTAssertTrue(
            TitleAboutCards.commonSenseMeaning(officialRating: "G", ageGate: "All")
                .localizedCaseInsensitiveContains("all ages")
        )
    }

    private func movie(
        genres: [String],
        overview: String?,
        rating: String?
    ) -> MediaItem {
        MediaItem(
            id: "1",
            name: "Batman Begins",
            kind: .movie,
            overview: overview,
            year: 2005,
            runtime: 8_400,
            officialRating: rating,
            genres: genres,
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
            videoRange: .dolbyVision,
            audioFormat: .atmos
        )
    }
}
