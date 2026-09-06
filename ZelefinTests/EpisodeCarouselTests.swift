import XCTest
@testable import Zelefin

final class EpisodeCarouselTests: XCTestCase {
    func testShowEpisodesFollowSeasonOrderThenEpisodeNumber() {
        let seasons = [season("s1", 1), season("s2", 2), season("s0", 0)]
        let episodes = [
            episode("s2e1", season: 2, number: 1),
            episode("s1e2", season: 1, number: 2),
            episode("s0e1", season: 0, number: 1),
            episode("s1e1", season: 1, number: 1)
        ]

        XCTAssertEqual(
            MediaItem.orderedShowEpisodes(episodes, seasons: seasons).map(\.id),
            ["s1e1", "s1e2", "s2e1", "s0e1"]
        )
    }

    func testCardsRepeatTheStripThreeTimesForLooping() {
        let seasons = [season("s1", 1), season("s2", 2)]
        let episodes = [
            episode("s1e1", season: 1, number: 1),
            episode("s2e1", season: 2, number: 1)
        ]
        let cards = EpisodeCarousel.cards(seasons: seasons, episodes: episodes)

        XCTAssertEqual(cards.count, 6)
        XCTAssertEqual(cards.map(\.copy), [0, 0, 1, 1, 2, 2])
        XCTAssertEqual(cards.map(\.episode.id), ["s1e1", "s2e1", "s1e1", "s2e1", "s1e1", "s2e1"])
        XCTAssertEqual(cards.map(\.seasonID), ["s1", "s2", "s1", "s2", "s1", "s2"])
    }

    func testHomePositionIsFirstEpisodeOfSelectedSeasonInTheMiddleCopy() {
        let seasons = [season("s1", 1), season("s2", 2)]
        let episodes = [
            episode("s1e1", season: 1, number: 1),
            episode("s1e2", season: 1, number: 2),
            episode("s2e1", season: 2, number: 1)
        ]
        let position = EpisodeCarousel.homePosition(seasonID: "s2", seasons: seasons, episodes: episodes)

        XCTAssertEqual(position?.copy, EpisodeCarousel.homeCopy)
        XCTAssertEqual(position?.episodeID, "s2e1")
    }

    func testPositionPinsASpecificEpisodeInTheMiddleCopy() {
        let id = EpisodeCarousel.position(episodeID: "s1e2")
        XCTAssertEqual(id.copy, EpisodeCarousel.homeCopy)
        XCTAssertEqual(id.episodeID, "s1e2")
    }

    func testRecenterJumpsCloneCopiesBackToTheMiddle() {
        let edge = EpisodeCarouselCard.ID(copy: 2, episodeID: "s1e1")
        let home = EpisodeCarouselCard.ID(copy: 1, episodeID: "s1e1")

        XCTAssertEqual(EpisodeCarousel.recentered(edge)?.copy, 1)
        XCTAssertEqual(EpisodeCarousel.recentered(edge)?.episodeID, "s1e1")
        XCTAssertNil(EpisodeCarousel.recentered(home))
    }

    private func season(_ id: String, _ number: Int) -> MediaItem {
        MediaItem(
            id: id,
            name: "Season \(number)",
            kind: .season,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: "Show",
            seasonIndex: number,
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
            seriesID: "show",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }

    private func episode(_ id: String, season: Int, number: Int) -> MediaItem {
        MediaItem(
            id: id,
            name: "Episode \(number)",
            kind: .episode,
            overview: nil,
            year: nil,
            runtime: 1800,
            officialRating: nil,
            genres: [],
            seriesName: "Show",
            seasonIndex: season,
            episodeIndex: number,
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
            seriesID: "show",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }
}
