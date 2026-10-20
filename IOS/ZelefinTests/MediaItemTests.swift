import JellyfinAPI
import UIKit
import XCTest
@testable import Zelefin

final class TickClockTests: XCTestCase {
    func testSecondsRoundTrip() {
        let ticks: Int64 = 90 * TickClock.ticksPerSecond
        XCTAssertEqual(TickClock.seconds(from: ticks), 90, accuracy: 0.001)
        XCTAssertEqual(TickClock.ticks(from: 90), ticks)
    }
}

final class PosterRatingBadgeTests: XCTestCase {
    func testStarScoreAcceptsTenPointScale() {
        XCTAssertEqual(PosterRatingBadge.starScore(from: 7.5), 7.5)
        XCTAssertEqual(PosterRatingBadge.starScore(from: 10), 10)
    }

    func testStarScoreRejectsMissingZeroOrPercentage() {
        XCTAssertNil(PosterRatingBadge.starScore(from: nil))
        XCTAssertNil(PosterRatingBadge.starScore(from: 0))
        // RT-style percentages can land in communityRating; never shown as "/10".
        XCTAssertNil(PosterRatingBadge.starScore(from: 85))
    }
}

final class MediaItemProgressTests: XCTestCase {
    func testProgressClamps() {
        let item = MediaItem(
            id: "1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
            officialRating: "PG-13",
            genres: ["Action", "Adventure"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 40,
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

        XCTAssertEqual(item.progress, 0.4, accuracy: 0.001)
        XCTAssertEqual(item.videoRange.displayName, "Dolby Vision")
        XCTAssertEqual(item.audioFormat.displayName, "Dolby Atmos")
        XCTAssertEqual(item.heroMetadataLine, "Movie  ·  Action  ·  Adventure")
        XCTAssertEqual(item.searchListSubtitle, "Movie · Action · 2024")
        XCTAssertEqual(item.playActionDurationLabel, "1m")
        XCTAssertEqual(item.ageGateLabel, "13+")
        XCTAssertEqual(item.runtimeLabel, "2m")
    }

    func testPlayActionDurationLabelUsesRemainingWhenInProgress() {
        let item = MediaItem(
            id: "1",
            name: "Batman Begins",
            kind: .movie,
            overview: "As a young boy, Bruce Wayne watched in horror.",
            year: 2005,
            runtime: 8400,
            officialRating: "PG-13",
            genres: ["Action", "Crime"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 600,
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
            audioFormat: .surround
        )

        XCTAssertEqual(item.playActionDurationLabel, "2h 10m")
        XCTAssertEqual(item.kindLabel, "Movie")
        XCTAssertEqual(item.runtimeLabel, "2h 20m")
        XCTAssertEqual(item.ageGateLabel, "13+")
    }

    func testPlayActionDurationLabelUsesRuntimeWhenUnwatched() {
        let item = MediaItem(
            id: "1",
            name: "Batman Begins",
            kind: .movie,
            overview: nil,
            year: 2005,
            runtime: 8400,
            officialRating: "PG-13",
            genres: ["Action", "Crime"],
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
            queueKind: .nextUp,
            videoRange: .sdr,
            audioFormat: .surround
        )

        XCTAssertEqual(item.playActionDurationLabel, "2h 20m")
    }

    func testPlayActionDurationLabelKeepsRemainingWhenUnderAMinute() {
        let item = MediaItem(
            id: "1",
            name: "Batman Begins",
            kind: .movie,
            overview: nil,
            year: 2005,
            runtime: 8400,
            officialRating: "PG-13",
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 8360,
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
            audioFormat: .surround
        )

        XCTAssertEqual(item.playActionDurationLabel, "1m")
    }

    func testPlayActionDurationLabelFloorsRemainingMinutes() {
        let item = MediaItem(
            id: "1",
            name: "Batman Begins",
            kind: .movie,
            overview: nil,
            year: 2005,
            runtime: 8400,
            officialRating: "PG-13",
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 7764,
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
            audioFormat: .surround
        )

        // 10.6 minutes left should not round up to 11m.
        XCTAssertEqual(item.playActionDurationLabel, "10m")
    }

    func testHeroPlaybackItemUsesInProgressEpisode() {
        let show = MediaItem(
            id: "show",
            name: "Silo",
            kind: .series,
            overview: nil,
            year: 2023,
            runtime: 79_200,
            officialRating: "TV-MA",
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: 8,
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
            audioFormat: .surround
        )
        let watched = MediaItem(
            id: "e1",
            name: "Freedom Day",
            kind: .episode,
            overview: nil,
            year: 2023,
            runtime: 2400,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 1,
            playbackPosition: 2400,
            unplayedCount: nil,
            isPlayed: true,
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
            audioFormat: .surround
        )
        let current = MediaItem(
            id: "e2",
            name: "Holston's Pick",
            kind: .episode,
            overview: nil,
            year: 2023,
            runtime: 2400,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 2,
            playbackPosition: 600,
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
            audioFormat: .surround
        )

        let target = MediaItem.heroPlaybackItem(title: show, episodes: [watched, current])
        XCTAssertEqual(target.id, "e2")
        XCTAssertEqual(target.playActionDurationLabel, "30m")
        XCTAssertEqual(show.playActionDurationLabel, "22h")
        XCTAssertEqual(
            MediaItem.heroPlaybackItem(
                title: MediaItem(
                    id: "season-1",
                    name: "Season 1",
                    kind: .season,
                    overview: nil,
                    year: 2023,
                    runtime: nil,
                    officialRating: nil,
                    genres: [],
                    seriesName: "Silo",
                    seasonIndex: 1,
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
                    audioFormat: .surround
                ),
                episodes: [watched, current]
            ).id,
            "e2"
        )
    }

    func testEpisodeLabel() {
        let episode = MediaItem(
            id: "e1",
            name: "The Gift",
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 2,
            playbackPosition: 600,
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
            seriesID: "silo",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .hdr10,
            audioFormat: .surround
        )

        XCTAssertEqual(episode.episodeLabel, "S1, E2 · 50m")
        XCTAssertEqual(episode.continueWatchingCaption, "S1, E2 · 50m")
        XCTAssertEqual(episode.continueWatchingTitle, "Silo")
        XCTAssertEqual(episode.continueWatchingListSubtitle, "CONTINUE  ·  S1, E2  ·  50M LEFT")
        XCTAssertEqual(episode.recentlyWatchedCaption, "S1, E2  ·  1h")
        XCTAssertEqual(episode.recentlyWatchedListSubtitle, "S1, E2  ·  1H")
        XCTAssertTrue(episode.showsResumeProgress)
        XCTAssertFalse(episode.isWatched)
        XCTAssertEqual(episode.episodeOrdinalLabel, "EPISODE 2")
    }

    func testPlayedEpisodeIsWatched() {
        let episode = MediaItem(
            id: "e1",
            name: "The One Where Monica Gets a Roommate",
            kind: .episode,
            overview: nil,
            year: 1994,
            runtime: 1362,
            officialRating: nil,
            genres: [],
            seriesName: "Friends",
            seasonIndex: 1,
            episodeIndex: 1,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: true,
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
            seriesID: "friends",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
        XCTAssertTrue(episode.isWatched)
        XCTAssertFalse(episode.showsResumeProgress)
    }

    func testEpisodePlayedToTheEndIsWatchedWithoutPlayedFlag() {
        let episode = MediaItem(
            id: "e2",
            name: "The One with the Sonogram at the End",
            kind: .episode,
            overview: nil,
            year: 1994,
            runtime: 100,
            officialRating: nil,
            genres: [],
            seriesName: "Friends",
            seasonIndex: 1,
            episodeIndex: 2,
            playbackPosition: 99,
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
            seriesID: "friends",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
        XCTAssertTrue(episode.isWatched)
        XCTAssertFalse(episode.showsResumeProgress)
    }

    func testSeasonMenuTitleAndOrdering() {
        let specials = MediaItem(
            id: "s0",
            name: "Specials",
            kind: .season,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: "Ted Lasso",
            seasonIndex: 0,
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
            seriesID: "ted",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
        let season2 = MediaItem(
            id: "s2",
            name: "Season 2",
            kind: .season,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: "Ted Lasso",
            seasonIndex: 2,
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
            seriesID: "ted",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
        let season1FromLegacySnapshot = MediaItem(
            id: "s1",
            name: "Season 1",
            kind: .season,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: "Ted Lasso",
            seasonIndex: nil,
            episodeIndex: 1,
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
            seriesID: "ted",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )

        XCTAssertEqual(specials.seasonMenuTitle, "Specials")
        XCTAssertEqual(season2.seasonMenuTitle, "Season 2")
        XCTAssertEqual(season1FromLegacySnapshot.seasonMenuTitle, "Season 1")
        XCTAssertEqual(
            MediaItem.orderedSeasons([specials, season2, season1FromLegacySnapshot]).map(\.id),
            ["s1", "s2", "s0"]
        )
        XCTAssertEqual(
            MediaItem.orderedEpisodes([
                MediaItem(
                    id: "e2",
                    name: "Biscuits",
                    kind: .episode,
                    overview: nil,
                    year: nil,
                    runtime: 1740,
                    officialRating: nil,
                    genres: [],
                    seriesName: "Ted Lasso",
                    seasonIndex: 1,
                    episodeIndex: 2,
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
                    seriesID: "ted",
                    imageItemID: nil,
                    queueKind: .resume,
                    videoRange: .sdr,
                    audioFormat: .unknown
                ),
                MediaItem(
                    id: "e1",
                    name: "Pilot",
                    kind: .episode,
                    overview: nil,
                    year: nil,
                    runtime: 1800,
                    officialRating: nil,
                    genres: [],
                    seriesName: "Ted Lasso",
                    seasonIndex: 1,
                    episodeIndex: 1,
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
                    seriesID: "ted",
                    imageItemID: nil,
                    queueKind: .resume,
                    videoRange: .sdr,
                    audioFormat: .unknown
                )
            ]).map(\.id),
            ["e1", "e2"]
        )
    }

    func testNextUpListSubtitle() {
        let episode = MediaItem(
            id: "e2",
            name: "The Janitor's Boy",
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 3,
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
            seriesID: "silo",
            imageItemID: nil,
            queueKind: .nextUp,
            videoRange: .hdr10,
            audioFormat: .surround
        )

        XCTAssertEqual(episode.continueWatchingListSubtitle, "NEXT  ·  S1, E3  ·  1H LEFT")
        XCTAssertFalse(episode.showsResumeProgress)
    }

    func testEpisodeOpensSeriesDetailNotItsOwnPage() {
        let episode = MediaItem(
            id: "e3",
            name: "The Janitor's Boy",
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 3,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: "silo",
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: "silo",
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: "silo",
            imageItemID: nil,
            queueKind: .nextUp,
            videoRange: .sdr,
            audioFormat: .unknown
        )

        XCTAssertEqual(episode.seriesDetailItemID, "silo")
        let preview = episode.seriesShowcasePreview()
        XCTAssertEqual(preview.id, "silo")
        XCTAssertEqual(preview.kind, .series)
        XCTAssertEqual(preview.name, "Silo")
        XCTAssertNil(preview.episodeIndex)
    }

    func testMovieHasNoSeriesDetailRedirect() {
        let movie = MediaItem(
            id: "m1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
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

        XCTAssertNil(movie.seriesDetailItemID)
    }

    func testCollectionCardTitleDropsCollectionSuffix() {
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("The Accountant Collection"), "The Accountant")
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("101 Dalmatians (Animated) Collection"), "101 Dalmatians (Animated)")
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("Action"), "Action")
    }
}

final class PlaybackQueueMenuLayoutTests: XCTestCase {
    func testContinueWatchingMenuOrder() {
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .continueWatching, kind: .episode),
            [.play, .goToShow, .markWatched, .download, .removeFromHomeQueue]
        )
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: .episode), "Play Episode")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: .episode), "Go to Show")
    }

    func testMovieUsesPlayAndGoToMovie() {
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: .movie), "Play")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: .movie), "Go to Movie")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToSymbol(for: .movie), "film")
    }

    func testSeriesUsesGoToShow() {
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: .series), "Go to Show")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToSymbol(for: .series), "tv")
    }

    func testFeaturedMenuOmitsHomeHide() {
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .featured, kind: .movie),
            [.play, .goToShow, .markWatched, .download]
        )
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .featured, kind: .series),
            [.play, .goToShow, .markWatched, .download]
        )
    }

    func testRecentlyWatchedAddsRemove() {
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .recentlyWatched, kind: .episode),
            [.play, .goToShow, .markWatched, .download, .removeFromRecentlyWatched]
        )
    }

    func testEpisodeMenuOmitsGoToShow() {
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .episode, kind: .episode),
            [.play, .markWatched, .download]
        )
        XCTAssertEqual(PlaybackQueueMenuLayout.watchedTitle(isWatched: false), "Mark as Watched")
        XCTAssertEqual(PlaybackQueueMenuLayout.watchedTitle(isWatched: true), "Mark as Unwatched")
    }

    func testYouTubeMenuCopy() {
        var video = MediaItem(
            id: "v1",
            name: "A Video",
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: [],
            seriesName: "Channel One",
            seasonIndex: 1,
            episodeIndex: 1,
            playbackPosition: 600,
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
            seriesID: "c1",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            youTubeID: "dQw4w9wg"
        )
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: video), "Resume")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: video), "Go to Channel")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToSymbol(for: video), "person.crop.circle")
        XCTAssertEqual(PlaybackQueueMenuLayout.watchedTitle(for: video), "Mark as Watched")

        video.playbackPosition = 0
        let channel = MediaItem(
            id: "c1",
            name: "Channel One",
            kind: .series,
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
            videoRange: .sdr,
            audioFormat: .unknown,
            youTubeID: "UCchannel"
        )
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: channel), "Play Latest")
        XCTAssertEqual(PlaybackQueueMenuLayout.watchedTitle(for: channel), "Mark Channel as Watched")
    }
}

final class YouTubeMediaTests: XCTestCase {
    func testYouTubeLabelsAndURL() {
        var video = Self.video(id: "v1", name: "A Video", seriesName: "A Channel")
        video.youTubeID = "abc123"
        video.playbackPosition = 120
        video.premiereDate = Calendar.current.date(byAdding: .day, value: -3, to: Date())
        XCTAssertTrue(video.isYouTube)
        XCTAssertEqual(video.kindLabel, "Video")
        XCTAssertEqual(video.continueWatchingTitle, "A Video")
        XCTAssertEqual(video.youTubeURL, URL(string: "https://www.youtube.com/watch?v=abc123"))
        XCTAssertEqual(video.continueWatchingCaption, "A Channel · 58m")

        let channel = Self.channel(id: "c1", name: "A Channel", youTubeID: "UCabc")
        XCTAssertEqual(channel.kindLabel, "Channel")
        XCTAssertEqual(channel.youTubeURL, URL(string: "https://www.youtube.com/channel/UCabc"))
    }

    func testYouTubeMapperAndCounts() {
        XCTAssertEqual(ItemMapper.youTubeID(from: ["TubeArchivist": "abc"]), "abc")
        XCTAssertEqual(ItemMapper.youTubeID(from: ["tubearchivist": "xyz"]), "xyz")
        XCTAssertNil(ItemMapper.youTubeID(from: ["Tmdb": "11"]))

        let raw = ServerCatalogCounts(movies: 10, shows: 8, episodes: 40)
        let split = raw.separatingYouTube(ServerCatalogCounts(movies: 0, shows: 0, episodes: 0, channels: 3, videos: 12))
        XCTAssertEqual(split.shows, 5)
        XCTAssertEqual(split.episodes, 28)
        XCTAssertEqual(split.channels, 3)
        XCTAssertEqual(split.videos, 12)
        XCTAssertTrue(split.showsHeaderStats)
        XCTAssertTrue(ServerCatalogCounts(movies: 0, shows: 0, episodes: 0, videos: 4).showsHeaderStats)
        XCTAssertFalse(ServerCatalogCounts(movies: 0, shows: 0, episodes: 0).showsHeaderStats)
        XCTAssertEqual(
            LibraryRoomCounts(movies: 0, shows: 0, episodes: 0, channels: 2, videos: 1).caption,
            "2 channels · 1 video"
        )
    }

    func testYouTubeTextHelpers() {
        XCTAssertEqual(YouTubeText.videoLengthLabel(62), "1:02")
        XCTAssertEqual(YouTubeText.videoLengthLabel(3723), "1:02:03")
        XCTAssertNil(YouTubeText.videoLengthLabel(0))
        XCTAssertEqual(YouTubeText.videoCountLabel(1), "1 video")
        XCTAssertEqual(YouTubeText.videoCountLabel(4), "4 videos")
        XCTAssertEqual(YouTubeText.plainDescription("Hello<br>world"), "Hello\nworld")
        XCTAssertEqual(YouTubeText.plainDescription("<p>A &amp; B</p>"), "A & B")

        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
        let threeDays = calendar.date(byAdding: .day, value: -3, to: now)
        let twoWeeks = calendar.date(byAdding: .day, value: -14, to: now)
        XCTAssertEqual(YouTubeText.publishedAgo(now, now: now), "Today")
        XCTAssertEqual(YouTubeText.publishedAgo(threeDays, now: now), "3 days ago")
        XCTAssertEqual(YouTubeText.publishedAgo(twoWeeks, now: now), "2 weeks ago")
    }

    func testYouTubeVideosSortNewestFirst() {
        let older = Self.video(id: "old", name: "Old", premiere: Date(timeIntervalSince1970: 1))
        let newer = Self.video(id: "new", name: "New", premiere: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(MediaItem.orderedYouTubeVideos([older, newer]).map(\.id), ["new", "old"])
    }

    func testYouTubeChannelStaysOnItsOwnDetailPage() {
        let video = Self.video(id: "v1", name: "Clip", seriesName: "Channel")
        XCTAssertNotNil(video.seriesDetailItemID)
        XCTAssertTrue(video.isYouTube)
    }

    private static func video(
        id: String,
        name: String,
        seriesName: String? = nil,
        premiere: Date? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .episode,
            overview: "<p>Hello<br>there</p>",
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: [],
            seriesName: seriesName,
            seasonIndex: 1,
            episodeIndex: 1,
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
            seriesID: "channel",
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            premiereDate: premiere,
            youTubeID: "yt"
        )
    }

    private static func channel(id: String, name: String, youTubeID: String) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .series,
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
            videoRange: .sdr,
            audioFormat: .unknown,
            youTubeID: youTubeID
        )
    }
}

final class HomeLayoutPreferencesTests: XCTestCase {
    func testGenreSymbolsMatchAppleTVLibraryRows() {
        XCTAssertEqual(GenreSymbol.systemImage(for: "Action & Adventure"), "burst.fill")
        XCTAssertEqual(GenreSymbol.systemImage(for: "Documentary"), "photo.on.rectangle.angled")
        XCTAssertEqual(GenreSymbol.systemImage(for: "Horror"), "theatermasks.fill")
        XCTAssertEqual(GenreSymbol.systemImage(for: "Kids & Family"), "balloon.2.fill")
        XCTAssertEqual(GenreSymbol.systemImage(for: "Comedy"), "face.smiling")
        XCTAssertEqual(GenreSymbol.systemImage(for: "Crime"), "lock.shield.fill")
        XCTAssertEqual(GenreSymbol.systemImage(for: "True Crime"), "lock.shield.fill")
    }

    func testCommonGenresUseDistinctSymbols() {
        let names = [
            "Action", "Adventure", "Animation", "Anime", "Biography", "Comedy", "Crime",
            "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Kids",
            "Music", "Musical", "Mystery", "News", "Reality", "Romance", "Science Fiction",
            "Sport", "Talk", "Thriller", "War", "Western"
        ]
        let symbols = names.map(GenreSymbol.systemImage)
        XCTAssertEqual(Set(symbols).count, names.count, "Shared icons: \(Dictionary(grouping: zip(names, symbols), by: \.1).filter { $0.value.count > 1 })")
        XCTAssertNotEqual(GenreSymbol.systemImage(for: "Action"), GenreSymbol.systemImage(for: "Adventure"))
        XCTAssertNotEqual(GenreSymbol.systemImage(for: "Drama"), GenreSymbol.systemImage(for: "Horror"))
        XCTAssertNotEqual(GenreSymbol.systemImage(for: "Kids"), GenreSymbol.systemImage(for: "Family"))
        XCTAssertNotEqual(GenreSymbol.systemImage(for: "Unknown Shelf"), GenreSymbol.systemImage(for: "Custom Mix"))
        XCTAssertNotEqual(GenreSymbol.systemImage(for: "Unknown Shelf"), "square.grid.2x2")
    }

    func testCatalogPagingContinuesUntilTheServerIsExhausted() {
        XCTAssertEqual(CatalogPaging.firstPaintSize, 48)
        XCTAssertEqual(
            CatalogPaging.nextStartIndex(fetchedCount: 48, currentStart: 0, totalCount: 2000, pageSize: 48),
            48
        )
        XCTAssertEqual(
            CatalogPaging.nextStartIndex(fetchedCount: 200, currentStart: 0, totalCount: 450),
            200
        )
        XCTAssertEqual(
            CatalogPaging.nextStartIndex(fetchedCount: 200, currentStart: 200, totalCount: 450),
            400
        )
        XCTAssertEqual(
            CatalogPaging.nextStartIndex(fetchedCount: 200, currentStart: 200, totalCount: 600),
            400
        )
        XCTAssertNil(CatalogPaging.nextStartIndex(fetchedCount: 50, currentStart: 400, totalCount: 450))
        XCTAssertNil(CatalogPaging.nextStartIndex(fetchedCount: 200, currentStart: 400, totalCount: 600))
        XCTAssertNil(CatalogPaging.nextStartIndex(fetchedCount: 0, currentStart: 0, totalCount: 100))
        XCTAssertEqual(
            CatalogPaging.nextStartIndex(fetchedCount: 200, currentStart: 0, totalCount: nil),
            200
        )
    }

    func testSeparateKeepsTwoRows() {
        let resume = [Self.item(id: "r1", queueKind: .resume)]
        let nextUp = [Self.item(id: "n1", queueKind: .nextUp)]
        let sections = HomeLayoutPreferences.playbackQueueSections(resume: resume, nextUp: nextUp, merge: false)

        XCTAssertEqual(sections.map(\.id), ["continue", "next-up"])
        XCTAssertEqual(sections[0].items.map(\.id), ["r1"])
        XCTAssertEqual(sections[1].items.map(\.id), ["n1"])
    }

    func testReplacingUpdatesMatchingHomeArtwork() {
        let stale = Self.item(id: "r1", primaryImageTag: "old")
        let fresh = Self.item(id: "r1", primaryImageTag: "new")
        let other = Self.item(id: "n1", primaryImageTag: "keep")
        let layout = HomeLayout(
            featured: [stale],
            sections: [
                HomeSection(id: "continue", title: "Continue", style: .landscape, items: [stale, other])
            ]
        )
        let next = layout.replacing(fresh)
        XCTAssertEqual(next.featured.first?.primaryImageTag, "new")
        XCTAssertEqual(next.sections.first?.items.map(\.primaryImageTag), ["new", "keep"])
    }

    func testHomeLayoutPlayUsesContinueWatchingEpisodeForThatShow() {
        let resume = Self.item(id: "ep-resume", queueKind: .resume)
        let other = Self.item(id: "ep-other", queueKind: .nextUp)
        let layout = HomeLayout(
            featured: [],
            sections: HomeLayoutPreferences.playbackQueueSections(
                resume: [resume],
                nextUp: [other],
                merge: false
            )
        )
        XCTAssertEqual(layout.episode(forSeriesID: "silo")?.id, "ep-resume")
        XCTAssertNil(layout.episode(forSeriesID: "adventure-time"))
    }

    func testRemovingAContinueWatchingTitleDropsEmptyQueueRows() {
        let layout = HomeLayout(
            featured: [Self.item(id: "r1", queueKind: .resume)],
            sections: HomeLayoutPreferences.playbackQueueSections(
                resume: [Self.item(id: "r1", queueKind: .resume)],
                nextUp: [Self.item(id: "n1", queueKind: .nextUp)],
                merge: false
            )
        )
        let next = HomeLayoutPreferences.removing("r1", from: layout)
        XCTAssertEqual(next.featured.map(\.id), ["r1"])
        XCTAssertEqual(next.sections.map(\.id), ["next-up"])
        XCTAssertEqual(next.sections.first?.items.map(\.id), ["n1"])
    }

    func testQueueMenuContextMatchesHomeSectionIDs() {
        XCTAssertEqual(HomeLayoutPreferences.menuContext(forSectionID: "continue"), .continueWatching)
        XCTAssertEqual(HomeLayoutPreferences.menuContext(forSectionID: "next-up"), .nextUp)
        XCTAssertEqual(HomeLayoutPreferences.menuContext(forSectionID: "recently-watched"), .recentlyWatched)
        XCTAssertNil(HomeLayoutPreferences.menuContext(forSectionID: "library-movies"))
    }

    func testMergePutsNextUpAfterResumeAndDropsDuplicates() {
        let resume = [Self.item(id: "shared", queueKind: .resume)]
        let nextUp = [
            Self.item(id: "shared", queueKind: .nextUp),
            Self.item(id: "n1", queueKind: .nextUp)
        ]
        let sections = HomeLayoutPreferences.playbackQueueSections(resume: resume, nextUp: nextUp, merge: true)

        XCTAssertEqual(sections.map(\.id), ["continue"])
        XCTAssertEqual(sections[0].items.map(\.id), ["shared", "n1"])
        XCTAssertEqual(sections[0].items.map(\.queueKind), [.resume, .nextUp])
    }

    func testFeaturedInterleavesLatestMoviesAndShows() {
        let featured = HomeLayoutPreferences.featured(
            latestMovies: [
                Self.title(id: "m1", kind: .movie),
                Self.title(id: "m2", kind: .movie)
            ],
            latestShows: [
                Self.title(id: "s1", kind: .series),
                Self.title(id: "s2", kind: .series)
            ]
        )
        XCTAssertEqual(featured.map(\.id), ["m1", "s1", "m2", "s2"])
    }

    func testFeaturedPrefersUnwatchedTitlesWithBackdrops() {
        let featured = HomeLayoutPreferences.featured(
            latestMovies: [
                Self.title(id: "watched", kind: .movie, played: true),
                Self.title(id: "no-art", kind: .movie, backdrop: nil),
                Self.title(id: "fresh", kind: .movie)
            ],
            latestShows: []
        )
        XCTAssertEqual(featured.map(\.id), ["fresh", "watched"])
    }

    func testHeroUsesTheSelectedHomeSource() {
        let added = [Self.title(id: "a1", kind: .movie)]
        let resume = [Self.title(id: "r1", kind: .movie)]
        let next = [Self.title(id: "n1", kind: .episode)]
        let watched = [Self.title(id: "w1", kind: .movie)]
        let recommend = [
            HomeSection(
                id: "recommend-1",
                title: "Because You Watched Heat",
                style: .portrait,
                items: [Self.title(id: "rec1", kind: .movie)]
            )
        ]
        XCTAssertEqual(
            HomeLayoutPreferences.hero(
                recentlyAdded: added,
                continueWatching: resume,
                nextUp: next,
                recentlyWatched: watched,
                recommendations: recommend,
                source: .continueWatching
            ).map(\.id),
            ["r1"]
        )
        XCTAssertEqual(
            HomeLayoutPreferences.hero(
                recentlyAdded: added,
                continueWatching: resume,
                nextUp: next,
                recentlyWatched: watched,
                recommendations: recommend,
                source: .recommendations
            ).map(\.id),
            ["rec1"]
        )
        XCTAssertEqual(
            FeaturedHeroContent(rawValue: "moviesAndShows") ?? .recentlyAdded,
            .recentlyAdded
        )
    }

    func testFeaturedCapsAtEightTitles() {
        let movies = (1...6).map { Self.title(id: "m\($0)", kind: .movie) }
        let shows = (1...6).map { Self.title(id: "s\($0)", kind: .series) }
        let featured = HomeLayoutPreferences.featured(latestMovies: movies, latestShows: shows)
        XCTAssertEqual(featured.count, 8)
        XCTAssertEqual(featured.map(\.id), ["m1", "s1", "m2", "s2", "m3", "s3", "m4", "s4"])
    }

    func testFeaturedKeepsHomeFeedHeroArtwork() {
        var catalog = Self.title(id: "m1", kind: .movie)
        catalog.backdropURL = URL(string: "https://example.com/card.jpg")
        var home = Self.title(id: "m1", kind: .movie)
        home.backdropURL = URL(string: "https://example.com/hero.jpg")
        home.logoURL = URL(string: "https://example.com/logo.png")
        let merged = HomeLayoutPreferences.replacingHeroArtwork(on: [catalog], with: [home])
        XCTAssertEqual(merged.first?.backdropURL?.absoluteString, "https://example.com/hero.jpg")
        XCTAssertEqual(merged.first?.logoURL?.absoluteString, "https://example.com/logo.png")
    }

    func testHeroSwipeTurnsThePageWithoutOpeningDetails() {
        XCTAssertEqual(FeaturedHeroPaging.selectionDelta(translation: CGSize(width: -80, height: 6)), 1)
        XCTAssertEqual(FeaturedHeroPaging.selectionDelta(translation: CGSize(width: 80, height: -4)), -1)
        XCTAssertNil(FeaturedHeroPaging.selectionDelta(translation: CGSize(width: -20, height: 4)))
        XCTAssertNil(FeaturedHeroPaging.selectionDelta(translation: CGSize(width: -80, height: 90)))
        XCTAssertFalse(FeaturedHeroPaging.opensDetail(translation: CGSize(width: -80, height: 6)))
        XCTAssertTrue(FeaturedHeroPaging.opensDetail(translation: CGSize(width: 2, height: -3)))
        XCTAssertFalse(FeaturedHeroPaging.opensDetail(translation: CGSize(width: 0, height: 40)))
        XCTAssertTrue(FeaturedHeroPaging.shouldClaimPan(velocity: CGSize(width: -240, height: 20)))
        XCTAssertFalse(FeaturedHeroPaging.shouldClaimPan(velocity: CGSize(width: 12, height: 180)))
    }

    func testAssemblePutsBrowseAndWatchedAtTheBottom() {
        let libraries = [
            HomeSection(id: "library-movies", title: "Recently Added Movies", style: .portrait, items: [Self.item(id: "m1", queueKind: .resume)])
        ]
        let collections = HomeSection(id: "collections", title: "Browse by Collection", style: .labeledPortrait, items: [Self.item(id: "c1", queueKind: .resume)])
        let genres = HomeSection(id: "genres", title: "Browse by Genre", style: .labeledPortrait, items: [Self.item(id: "g1", queueKind: .resume)])
        let watched = [Self.item(id: "w1", queueKind: .resume)]
        let sections = HomeLayoutPreferences.assemble(
            resume: [Self.item(id: "r1", queueKind: .resume)],
            nextUp: [],
            merge: false,
            libraries: libraries,
            collections: collections,
            genres: genres,
            recentlyWatched: watched
        )
        XCTAssertEqual(
            sections.map(\.id),
            ["continue", "library-movies", "collections", "genres", "recently-watched"]
        )
    }

    func testHomeFeedHidesAndReordersRows() {
        let featured = [Self.item(id: "f1", queueKind: .resume)]
        let continueRow = HomeSection(
            id: "continue",
            title: "Continue Watching",
            style: .landscape,
            items: [Self.item(id: "r1", queueKind: .resume)]
        )
        let movies = HomeSection(
            id: "library-abc",
            title: "Recently Added Movies",
            style: .portrait,
            items: [Self.item(id: "m1", queueKind: .resume)]
        )
        let shows = HomeSection(
            id: "library-shows",
            title: "Recently Added Shows",
            style: .portrait,
            items: [Self.item(id: "s1", queueKind: .resume)]
        )
        let recommended = HomeSection(
            id: "recommend-1",
            title: "Because You Watched Dune",
            style: .portrait,
            items: [Self.item(id: "x1", queueKind: .resume)]
        )
        let feed = HomeLayoutPreferences.feed(
            featured: featured,
            sections: [continueRow, movies, shows, recommended],
            order: [.recentlyAddedShows, .featured, .recommendations, .continueWatching],
            hidden: [.recentlyAddedMovies]
        )
        XCTAssertEqual(feed.map(\.id), ["library-shows", "featured", "recommend-1", "continue"])
    }

    func testHomeFeedSkipsEmptyFeaturedAndKeepsUnknownRowsLast() {
        let extra = HomeSection(
            id: "custom-row",
            title: "Custom",
            style: .portrait,
            items: [Self.item(id: "c1", queueKind: .resume)]
        )
        let continueRow = HomeSection(
            id: "continue",
            title: "Continue Watching",
            style: .landscape,
            items: [Self.item(id: "r1", queueKind: .resume)]
        )
        let feed = HomeLayoutPreferences.feed(
            featured: [],
            sections: [continueRow, extra],
            order: HomeRowKind.allCases,
            hidden: [.featured, .continueWatching]
        )
        XCTAssertEqual(feed.map(\.id), ["custom-row"])
    }

    func testHomeRowKindParsesLegacyOrderAndHiddenLists() {
        XCTAssertEqual(
            HomeRowKind.ordered(from: "genres,continueWatching").map(\.rawValue).prefix(3),
            ["genres", "continueWatching", "featured"]
        )
        XCTAssertEqual(
            HomeRowKind.hidden(from: "featured,unknown,genres"),
            [.featured, .genres]
        )
    }

    func testCollapseRecentlyWatchedKeepsOneEpisodePerShow() {
        let first = Self.item(id: "e1", queueKind: .resume)
        let second = Self.item(id: "e2", queueKind: .resume)
        let movie = MediaItem(
            id: "m1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 9300,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: true,
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
        let collapsed = HomeLayoutPreferences.collapseRecentlyWatched([first, second, movie])
        XCTAssertEqual(collapsed.map(\.id), ["e1", "m1"])
    }

    func testHomeHidesMusicAndBooksLibraries() {
        let libraries = [
            MediaLibrary(id: "m", name: "Movies", kind: .movie, libraryKind: .movies),
            MediaLibrary(id: "music", name: "Music", kind: .collection, libraryKind: .music),
            MediaLibrary(id: "books", name: "Books", kind: .collection, libraryKind: .books),
            MediaLibrary(id: "s", name: "Shows", kind: .series, libraryKind: .shows),
            MediaLibrary(id: "cols", name: "Collections", kind: .collection, libraryKind: .collections),
            MediaLibrary(id: "home", name: "Cameras", kind: .collection, libraryKind: .homeVideos),
            MediaLibrary(id: "tv", name: "Live TV", kind: .collection, libraryKind: .liveTV),
            MediaLibrary(id: "mix", name: "Trailers", kind: .collection, libraryKind: .other)
        ]
        XCTAssertEqual(
            HomeLayoutPreferences.orderedHomeLibraries(libraries).map(\.id),
            ["m", "s"]
        )
        XCTAssertEqual(LibraryKind.movies.recentlyAddedTitle(libraryName: "Movies"), "Recently Added Movies")
        XCTAssertEqual(LibraryKind.shows.recentlyAddedTitle(libraryName: "TV"), "Recently Added Shows")
        XCTAssertEqual(LibraryKind.inferred(fromName: "TV Shows"), .shows)
        XCTAssertFalse(LibraryKind.collections.appearsOnHome)
        XCTAssertFalse(LibraryKind.favorites.appearsOnHome)
        XCTAssertEqual(
            HomeLayoutPreferences.libraryTabLibraries(libraries).map(\.id),
            ["m", "s", "cols", "home", "tv", "mix"]
        )
        XCTAssertEqual(
            HomeLayoutPreferences.libraries(libraries, matching: .movies).map(\.id),
            ["m"]
        )
        XCTAssertEqual(
            HomeLayoutPreferences.libraries(libraries, matching: .shows).map(\.id),
            ["s"]
        )
        XCTAssertTrue(LibraryKind.liveTV.appearsInLibrary)
        XCTAssertTrue(LibraryKind.movies.appearsInLibrary)
        XCTAssertTrue(LibraryKind.shows.appearsInLibrary)
        XCTAssertTrue(LibraryKind.youTube.appearsInLibrary)
        XCTAssertFalse(LibraryKind.youTube.appearsOnHome)
        XCTAssertEqual(LibraryKind.youTube.browseLabel, "YouTube")
        XCTAssertEqual(LibraryKind.inferred(fromName: "YouTube"), .youTube)
        XCTAssertEqual(LibraryKind.inferred(fromName: "TubeArchivist"), .youTube)
        XCTAssertTrue(LibraryKind.other.appearsInLibrary)
        XCTAssertTrue(LibraryKind.photos.appearsInLibrary)
        XCTAssertTrue(LibraryKind.homeVideos.appearsInLibrary)
        XCTAssertTrue(LibraryKind.collections.appearsInLibrary)
        XCTAssertFalse(LibraryKind.books.appearsInLibrary)
        XCTAssertFalse(LibraryKind.music.appearsInLibrary)
        XCTAssertFalse(LibraryKind.playlists.appearsInLibrary)
        XCTAssertFalse(LibraryKind.favorites.appearsInLibrary)
        XCTAssertEqual(LibraryKind.other.systemImage, "rectangle.stack")
        let catalog = libraries.filter(\.libraryKind.appearsInLibrary)
        XCTAssertEqual(
            LibraryLayoutPreferences.displayed(
                catalog,
                orderRaw: "mix,m,s",
                hiddenRaw: "tv"
            ).map(\.id),
            ["mix", "m", "s", "cols", "home"]
        )
        XCTAssertEqual(
            LibraryLayoutPreferences.arranged(catalog, orderRaw: "").map(\.id),
            ["cols", "m", "s", "mix", "home", "tv"]
        )
        XCTAssertEqual(
            LibraryLayoutPreferences.displayed(catalog, orderRaw: "", hiddenRaw: "").map(\.id),
            ["cols", "m", "s", "mix"]
        )
        XCTAssertEqual(
            LibraryLayoutPreferences.resolvedHidden(from: "", libraries: catalog),
            ["home", "tv"]
        )
        XCTAssertEqual(
            LibraryLayoutPreferences.resolvedHidden(from: "none", libraries: catalog),
            []
        )
        XCTAssertEqual(LibraryLayoutPreferences.hiddenRaw(from: []), "none")
        let recordings = MediaLibrary(id: "rec", name: "Recordings", kind: .collection, libraryKind: .other)
        XCTAssertTrue(recordings.isHiddenOnLibraryByDefault)
        XCTAssertEqual(recordings.libraryCardRank, 4)
        XCTAssertEqual(
            LibraryLayoutPreferences.hiddenBlocks(from: "favorites,collections"),
            [.favorites, .collections]
        )
        XCTAssertTrue(LibraryKind.movies.appearsOnHome)
        XCTAssertTrue(LibraryKind.shows.appearsOnHome)
        XCTAssertFalse(LibraryKind.homeVideos.appearsOnHome)
        XCTAssertFalse(LibraryKind.other.appearsOnHome)

        let collectionRow = HomeSection(
            id: "library-cols",
            title: "Recently Added Collections",
            style: .portrait,
            items: [Self.item(id: "c1", queueKind: .resume)]
        )
        XCTAssertTrue(collectionRow.isRecentlyAddedCollections)
        XCTAssertEqual(
            HomeLayoutPreferences.librarySectionsExcludingCollections([collectionRow]).map(\.id),
            []
        )
    }

    func testGenreCoversUseAMatchingTitleBackdrop() {
        let action = Self.genre(id: "g-action", name: "Action", imageTag: "old-genre-art")
        let comedy = Self.genre(id: "g-comedy", name: "Comedy")
        let empty = Self.genre(id: "g-empty", name: "Documentary")
        let madMax = Self.cover(id: "mad-max", name: "Mad Max", genres: ["Action"], backdropTags: ["mad-max-cover"])
        let batman = Self.cover(id: "batman", name: "Batman", genres: ["Action"], backdropTags: ["batman-cover"])
        let superbad = Self.cover(id: "superbad", name: "Superbad", genres: ["Comedy"], backdropTags: ["superbad-cover"])

        let result = HomeLayoutPreferences.applyGenreCovers(
            [action, comedy, empty],
            covers: [madMax, batman, superbad]
        )

        XCTAssertEqual(result[0].id, "g-action")
        XCTAssertTrue(["mad-max", "batman"].contains(result[0].imageItemID))
        XCTAssertTrue(["mad-max-cover", "batman-cover"].contains(result[0].backdropImageTag))
        XCTAssertEqual(result[1].imageItemID, "superbad")
        XCTAssertEqual(result[1].backdropImageTag, "superbad-cover")
        XCTAssertNil(result[2].backdropImageTag)
        XCTAssertNil(result[2].imageItemID)
    }

    func testGenreCoversPreferUniqueTitles() {
        let action = Self.genre(id: "g-action", name: "Action")
        let adventure = Self.genre(id: "g-adventure", name: "Adventure")
        let madMax = Self.cover(id: "mad-max", name: "Mad Max", genres: ["Action"], backdropTags: ["mad-max-cover"])
        let moana = Self.cover(id: "moana", name: "Moana", genres: ["Adventure"], backdropTags: ["moana-cover"])

        let result = HomeLayoutPreferences.applyGenreCovers(
            [action, adventure],
            covers: [madMax, moana]
        )

        XCTAssertEqual(Set(result.compactMap(\.imageItemID)), ["mad-max", "moana"])
        XCTAssertEqual(Set(result.compactMap(\.backdropImageTag)), ["mad-max-cover", "moana-cover"])
    }

    func testGenreCoverPicksABackdropFromTheTitle() {
        let tags = ["cover-a", "cover-b", "cover-c"]
        let action = Self.genre(id: "g-action", name: "Action")
        let dune = Self.cover(id: "dune", name: "Dune", genres: ["Action"], backdropTags: tags)

        let result = HomeLayoutPreferences.applyGenreCovers([action], covers: [dune])

        XCTAssertEqual(result[0].imageItemID, "dune")
        XCTAssertTrue(tags.contains(result[0].backdropImageTag ?? ""))
        XCTAssertEqual(result[0].primaryImageTag, "unused-poster")
    }

    func testGenreCoversFallBackToPrimaryWhenNoBackdrop() {
        let action = Self.genre(id: "g-action", name: "Action")
        let cover = MediaItem(
            id: "poster-only",
            name: "Poster Only",
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: nil,
            officialRating: nil,
            genres: ["Action"],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: "poster-tag",
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

        let result = HomeLayoutPreferences.applyGenreCovers([action], covers: [cover])

        XCTAssertEqual(result[0].imageItemID, "poster-only")
        XCTAssertEqual(result[0].primaryImageTag, "poster-tag")
        XCTAssertTrue(cover.hasGenreCoverArt)
    }

    private static func genre(id: String, name: String, imageTag: String? = nil) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .genre,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [name],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: imageTag,
            thumbImageTag: nil,
            backdropImageTag: imageTag,
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

    private static func cover(id: String, name: String, genres: [String], backdropTags: [String]) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: nil,
            officialRating: nil,
            genres: genres,
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: "unused-poster",
            thumbImageTag: nil,
            backdropImageTag: backdropTags.first,
            backdropImageTags: backdropTags,
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

    private static func title(
        id: String,
        kind: MediaKind,
        played: Bool = false,
        backdrop: String? = "bd"
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            kind: kind,
            overview: nil,
            year: 2024,
            runtime: 7200,
            officialRating: nil,
            genres: ["Drama"],
            seriesName: kind == .series ? id : nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: played,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: backdrop,
            backdropImageTags: backdrop.map { [$0] } ?? [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: kind == .series ? id : nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .stereo
        )
    }

    private static func item(id: String, queueKind: PlaybackQueueKind) -> MediaItem {
        MediaItem(
            id: id,
            name: id,
            kind: .episode,
            overview: nil,
            year: 2024,
            runtime: 3600,
            officialRating: nil,
            genres: [],
            seriesName: "Silo",
            seasonIndex: 1,
            episodeIndex: 1,
            playbackPosition: queueKind == .resume ? 600 : 0,
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
            seriesID: "silo",
            imageItemID: nil,
            queueKind: queueKind,
            videoRange: .sdr,
            audioFormat: .stereo
        )
    }

    private static func item(id: String, primaryImageTag: String? = nil) -> MediaItem {
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
            primaryImageTag: primaryImageTag,
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

final class SearchHistoryStoreTests: XCTestCase {
    func testInsertMovesExistingItemToFront() {
        let first = Self.item(id: "1")
        let second = Self.item(id: "2")
        let again = Self.item(id: "1")
        let result = SearchHistoryStore.inserting(again, into: [first, second])
        XCTAssertEqual(result.map(\.id), ["1", "2"])
    }

    func testInsertCapsAtLimit() {
        let items = (0..<3).map { Self.item(id: "\($0)") }
        let extra = Self.item(id: "new")
        let result = SearchHistoryStore.inserting(extra, into: items, limit: 3)
        XCTAssertEqual(result.map(\.id), ["new", "0", "1"])
    }

    private static func item(id: String, primaryImageTag: String? = nil) -> MediaItem {
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
            primaryImageTag: primaryImageTag,
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

final class NowPlayingStoreTests: XCTestCase {
    func testSavesAndRestoresLastPlayedItemPerAccount() {
        let defaults = UserDefaults(suiteName: "zelefin.now-playing.tests")!
        defaults.removePersistentDomain(forName: "zelefin.now-playing.tests")
        var item = Self.item(id: "dune", name: "Dune")
        item.playbackPosition = 42

        NowPlayingStore.save(item, for: "acct-a", defaults: defaults)
        NowPlayingStore.save(Self.item(id: "other", name: "Other"), for: "acct-b", defaults: defaults)

        let restored = NowPlayingStore.item(for: "acct-a", defaults: defaults)
        XCTAssertEqual(restored?.id, "dune")
        XCTAssertEqual(restored?.name, "Dune")
        XCTAssertEqual(restored?.playbackPosition, 42)
        XCTAssertEqual(NowPlayingStore.item(for: "acct-b", defaults: defaults)?.id, "other")
    }

    func testClearingRemovesPersistedItem() {
        let defaults = UserDefaults(suiteName: "zelefin.now-playing.clear")!
        defaults.removePersistentDomain(forName: "zelefin.now-playing.clear")
        NowPlayingStore.save(Self.item(id: "dune", name: "Dune"), for: "acct-a", defaults: defaults)
        NowPlayingStore.save(nil, for: "acct-a", defaults: defaults)
        XCTAssertNil(NowPlayingStore.item(for: "acct-a", defaults: defaults))
    }

    private static func item(id: String, name: String) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .movie,
            overview: nil,
            year: 2024,
            runtime: 100,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: "art",
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

final class TrailerLinkParserTests: XCTestCase {
    func testParsesYouTubeURLVariants() {
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://www.youtube.com/watch?v=YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://youtu.be/YoHD9XEInc0?t=12"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://www.youtube.com/embed/YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://www.youtube-nocookie.com/embed/YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://www.youtube.com/shorts/YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "https://www.youtube.com/watch?feature=share&v=YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(TrailerLinkParser.youtubeVideoID(from: "YoHD9XEInc0"), "YoHD9XEInc0")
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "plugin://plugin.video.youtube/?action=play_video&videoid=YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "plugin://plugin.video.youtube/play/?video_id=YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertEqual(
            TrailerLinkParser.youtubeVideoID(from: "plugin://plugin.video.youtube/?action=play_video&amp;videoid=YoHD9XEInc0"),
            "YoHD9XEInc0"
        )
        XCTAssertNil(TrailerLinkParser.youtubeVideoID(from: "https://vimeo.com/123456789"))
        XCTAssertNil(TrailerLinkParser.youtubeVideoID(from: "not a trailer"))
        XCTAssertNil(TrailerLinkParser.youtubeVideoID(from: "short"))
    }

    func testParsesVimeoURLVariants() {
        XCTAssertEqual(TrailerLinkParser.vimeoVideoID(from: "https://vimeo.com/123456789"), "123456789")
        XCTAssertEqual(
            TrailerLinkParser.vimeoVideoID(from: "https://player.vimeo.com/video/123456789"),
            "123456789"
        )
        XCTAssertNil(TrailerLinkParser.vimeoVideoID(from: "https://www.youtube.com/watch?v=YoHD9XEInc0"))
    }

    func testYouTubeTrailerBuildsWatchURLAndThumbnail() {
        let trailer = TitleTrailer.youtube(id: "YoHD9XEInc0", title: "Official Trailer")
        XCTAssertEqual(trailer.thumbnailURL?.absoluteString, "https://i.ytimg.com/vi/YoHD9XEInc0/mqdefault.jpg")
        XCTAssertEqual(
            trailer.externalWatchURL?.absoluteString,
            "https://www.youtube.com/watch?v=YoHD9XEInc0"
        )
        XCTAssertEqual(trailer.caption, "Trailer")
        XCTAssertEqual(trailer.trailerRank, 0)
    }

    func testOnlyOfficialTrailersPassFilter() {
        XCTAssertTrue(TitleTrailer.isOfficialTrailer(title: "Official Trailer"))
        XCTAssertTrue(TitleTrailer.isOfficialTrailer(title: "Trailer"))
        XCTAssertTrue(TitleTrailer.isOfficialTrailer(title: "Final Trailer"))
        XCTAssertTrue(TitleTrailer.isOfficialTrailer(title: "International Trailer"))
        XCTAssertTrue(TitleTrailer.isOfficialTrailer(title: "Official Trailer", type: "Trailer"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Official Teaser"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Teaser Trailer"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Official Trailer", type: "Teaser"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Clip"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Behind the Scenes"))
        XCTAssertFalse(TitleTrailer.isOfficialTrailer(title: "Official Trailer", official: false))
    }

    func testCatalogPagesUseTMDBAndIMDb() {
        let tmdb = TitleTrailer.tmdbPage(id: 27205, isSeries: false)
        XCTAssertEqual(tmdb.externalWatchURL?.absoluteString, "https://www.themoviedb.org/movie/27205")
        XCTAssertEqual(tmdb.caption, "TMDB")

        let imdb = TitleTrailer.imdbPage(id: "tt1375666")
        XCTAssertEqual(imdb.externalWatchURL?.absoluteString, "https://www.imdb.com/title/tt1375666/")
        XCTAssertEqual(imdb.caption, "IMDb")
    }

    func testJellyfinRemoteTrailersUseServerMetadata() {
        let youtube = TitleTrailer.jellyfinRemote(
            url: "https://www.youtube.com/watch?v=YoHD9XEInc0",
            title: "Official Trailer"
        )
        XCTAssertEqual(youtube?.id, "yt-YoHD9XEInc0")
        XCTAssertEqual(youtube?.externalWatchURL?.absoluteString, "https://www.youtube.com/watch?v=YoHD9XEInc0")

        let kodi = TitleTrailer.jellyfinRemote(
            url: "plugin://plugin.video.youtube/play/?video_id=YoHD9XEInc0",
            title: "Trailer"
        )
        XCTAssertEqual(kodi?.id, "yt-YoHD9XEInc0")

        let remotes = JellyfinTrailers.remotes(from: [
            MediaURL(name: "Official Trailer", url: "https://www.youtube.com/watch?v=YoHD9XEInc0"),
            MediaURL(name: "Duplicate", url: "https://youtu.be/YoHD9XEInc0"),
            MediaURL(name: "Vimeo Cut", url: "https://vimeo.com/123456789")
        ])
        XCTAssertEqual(remotes.map(\.id), ["yt-YoHD9XEInc0", "vimeo-123456789"])
        XCTAssertEqual(JellyfinTrailers.displayTitle(nil), "Trailer")
        XCTAssertEqual(JellyfinTrailers.displayTitle("  Official Trailer  "), "Official Trailer")
    }
}

final class LibraryDiscoveryMappingTests: XCTestCase {
    func testSearchHintsDropMusicAndKeepTitles() {
        let movie = ItemMapper.searchHit(
            from: SearchHint(id: "m1", name: "Dune", productionYear: 2021, type: .movie)
        )
        XCTAssertEqual(movie?.id, "m1")
        XCTAssertEqual(movie?.kind, .title(.movie))
        XCTAssertEqual(movie?.subtitle, "Movie · 2021")

        let person = ItemMapper.searchHit(
            from: SearchHint(id: "p1", name: "Timothée Chalamet", type: .person)
        )
        XCTAssertEqual(person?.kind, .person)

        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "a1", name: "Song", type: .audio)))
        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "a2", name: "Artist", type: .musicArtist)))
        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "a3", name: "Album", type: .musicAlbum)))
        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "pl1", name: "Mix", type: .playlist)))
        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "b1", name: "Novel", type: .book)))
        XCTAssertNil(ItemMapper.searchHit(from: SearchHint(id: "ph1", name: "Sunset", type: .photo)))
    }

    func testRecommendationTitles() {
        XCTAssertEqual(
            ItemMapper.recommendationTitle(
                from: RecommendationDto(baselineItemName: "Dune", recommendationType: .similarToRecentlyPlayed)
            ),
            "Because You Watched Dune"
        )
        XCTAssertEqual(
            ItemMapper.recommendationTitle(from: RecommendationDto(recommendationType: .similarToLikedItem)),
            "Because You Liked"
        )
    }

    func testTrickplayTileMath() {
        let info = TrickplayInfo(
            width: 320,
            interval: 10,
            thumbnailCount: 25,
            tileWidth: 10,
            tileHeight: 10,
            thumbnailWidth: 320,
            thumbnailHeight: 180,
            mediaSourceID: "src"
        )
        XCTAssertEqual(info.thumbnailIndex(at: 0), 0)
        XCTAssertEqual(info.thumbnailIndex(at: 25), 2)
        XCTAssertEqual(info.tileIndex(at: 0), 0)
        XCTAssertEqual(info.cell(at: 25).column, 2)
        XCTAssertEqual(info.cell(at: 25).row, 0)
        XCTAssertEqual(info.thumbnailIndex(at: 10_000), 24)
    }

    func testFavoriteAndLikeCopies() {
        var item = MediaItem(
            id: "1",
            name: "Dune",
            kind: .movie,
            overview: nil,
            year: 2021,
            runtime: 100,
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
            audioFormat: .stereo
        )
        item = item.withFavorite(true).withLikes(true)
        XCTAssertTrue(item.isFavorite)
        XCTAssertEqual(item.likes, true)
        item = item.withLikes(nil)
        XCTAssertNil(item.likes)
    }
}

final class AppTabTests: XCTestCase {
    func testOrderedKeepsKnownTabsAndFillsMissing() {
        XCTAssertEqual(AppTab.ordered(from: "library,movies"), [.library, .movies, .home, .shows, .liveTV, .collections, .favorites])
        XCTAssertEqual(AppTab.ordered(from: "nope,home"), [.home, .movies, .shows, .liveTV, .collections, .library, .favorites])
        XCTAssertEqual(AppTab.raw(from: [.shows, .home, .shows]), "shows,home")
        XCTAssertEqual(AppTab.defaultOrderRaw, "home,movies,shows,liveTV,collections,library,favorites")
    }

    func testHomeCannotBeHidden() {
        XCTAssertFalse(AppTab.home.canHide)
        XCTAssertTrue(AppTab.movies.canHide)
        XCTAssertTrue(AppTab.liveTV.canHide)
        XCTAssertTrue(AppTab.collections.canHide)
        XCTAssertTrue(AppTab.favorites.canHide)
        XCTAssertEqual(AppTab.liveTV.title, "Live TV")
        XCTAssertEqual(AppTab.favorites.title, "Favorites")
        XCTAssertEqual(AppTab.collections.title, "Collections")
        XCTAssertEqual(AppTab.liveTV.customizationID, "app.zelefin.tab.liveTV")
        XCTAssertEqual(AppTab.collections.customizationID, "app.zelefin.tab.collections")
        XCTAssertEqual(AppTab.library.customizationID, "app.zelefin.tab.library")
        XCTAssertEqual(AppTab.favorites.customizationID, "app.zelefin.tab.favorites")
        XCTAssertEqual(AppTab.hiddenByDefault, [.liveTV, .collections, .favorites])
        XCTAssertFalse(AppTab.hiddenByDefault.contains(.movies))
    }
}

final class SearchChromeMetricsTests: XCTestCase {
    func testPhoneStaysUnderTheStatusBar() {
        XCTAssertEqual(
            SearchChromeMetrics.topInset(
                statusBarHeight: 59,
                usesPadTopChrome: false,
                isSidebarVisible: false
            ),
            59
        )
    }

    func testPadTabBarLeavesRoomBelowTheFloatingBar() {
        XCTAssertEqual(
            SearchChromeMetrics.topInset(
                statusBarHeight: 24,
                usesPadTopChrome: true,
                isSidebarVisible: false
            ),
            24 + SearchChromeMetrics.topTabBarClearance
        )
    }

    func testPadSidebarMovesSearchIntoTheTabBarSlot() {
        XCTAssertEqual(
            SearchChromeMetrics.topInset(
                statusBarHeight: 24,
                usesPadTopChrome: true,
                isSidebarVisible: true
            ),
            24
        )
    }

    func testPhoneIgnoresSidebarWhenMeasuringChrome() {
        XCTAssertEqual(
            SearchChromeMetrics.topInset(
                statusBarHeight: 59,
                usesPadTopChrome: false,
                isSidebarVisible: true
            ),
            59
        )
    }
}

final class RootPageChromeTests: XCTestCase {
    func testPhoneShowsTabTitles() {
        XCTAssertTrue(RootPageChrome.showsTitle(idiom: .phone))
    }

    func testPadHidesTabTitles() {
        XCTAssertFalse(RootPageChrome.showsTitle(idiom: .pad))
    }

    func testHeaderStaysVisibleNearTheTop() {
        XCTAssertTrue(
            RootPageChrome.headerVisible(offset: 8, previousOffset: 0, wasVisible: true)
        )
    }

    func testHeaderHidesWhenScrollingDown() {
        XCTAssertFalse(
            RootPageChrome.headerVisible(offset: 48, previousOffset: 28, wasVisible: true)
        )
    }

    func testHeaderReturnsWhenScrollingUp() {
        XCTAssertTrue(
            RootPageChrome.headerVisible(offset: 36, previousOffset: 60, wasVisible: false)
        )
    }

    func testPadTabBarLiftsProfileIntoTheTabRow() {
        XCTAssertEqual(
            RootPageChrome.padTabBarLift(usesPadTopChrome: true, isSidebarVisible: false),
            -RootPageChrome.padTopTabBarClearance
        )
    }

    func testPadSidebarDoesNotLiftProfile() {
        XCTAssertEqual(
            RootPageChrome.padTabBarLift(usesPadTopChrome: true, isSidebarVisible: true),
            0
        )
    }

    func testPhoneDoesNotLiftProfile() {
        XCTAssertEqual(
            RootPageChrome.padTabBarLift(usesPadTopChrome: false, isSidebarVisible: false),
            0
        )
    }

    func testPushedOverlaySitsInThePadTabRowWhenContentGoesUnderTheStatusBar() {
        XCTAssertEqual(
            RootPageChrome.pushedOverlayTopPadding(
                contentIgnoresTopSafeArea: true,
                statusBarHeight: 24
            ),
            28
        )
        XCTAssertEqual(
            RootPageChrome.pushedOverlayLift(
                contentIgnoresTopSafeArea: true,
                usesPadTopChrome: true,
                isSidebarVisible: false
            ),
            0
        )
    }

    func testPushedOverlayLiftsIntoThePadTabRowWhenContentUsesTheSafeArea() {
        XCTAssertEqual(
            RootPageChrome.pushedOverlayTopPadding(
                contentIgnoresTopSafeArea: false,
                statusBarHeight: 24
            ),
            4
        )
        XCTAssertEqual(
            RootPageChrome.pushedOverlayLift(
                contentIgnoresTopSafeArea: false,
                usesPadTopChrome: true,
                isSidebarVisible: false
            ),
            -RootPageChrome.padTopTabBarClearance
        )
    }
}

final class SearchGenreGridTests: XCTestCase {
    func testPhoneKeepsThreeColumns() {
        XCTAssertEqual(
            SearchGenreGrid.columnCount(gridWidth: 390, isRegularWidth: false, isPortrait: true),
            3
        )
    }

    func testPadPortraitUsesFiveColumns() {
        XCTAssertEqual(
            SearchGenreGrid.columnCount(gridWidth: 834, isRegularWidth: true, isPortrait: true),
            5
        )
    }

    func testPadLandscapeUsesSevenColumns() {
        XCTAssertEqual(
            SearchGenreGrid.columnCount(gridWidth: 1366, isRegularWidth: true, isPortrait: false),
            7
        )
        XCTAssertEqual(
            SearchGenreGrid.columnCount(gridWidth: 1194, isRegularWidth: true, isPortrait: false),
            7
        )
        XCTAssertEqual(
            SearchGenreGrid.columnCount(gridWidth: 500, isRegularWidth: true, isPortrait: false),
            7
        )
    }
}

final class HeroMetricsTests: XCTestCase {
    func testHomeAndDetailShareTheSameHeroHeight() {
        let phone = CGSize(width: 390, height: 844)
        let pad = CGSize(width: 1024, height: 1366)
        XCTAssertEqual(PosterMetrics.heroHeight(for: phone), max(680, 844 * 0.82))
        XCTAssertEqual(PosterMetrics.heroHeight(for: pad), max(680, 1366 * 0.82))
    }

    func testHeroHeightStaysPutWhenTheDockChangesHeight() {
        var lock = HeroHeightLock()
        lock.lock(CGSize(width: 440, height: 860))
        let resting = PosterMetrics.heroHeight(for: CGSize(width: 440, height: 860))
        lock.lock(CGSize(width: 440, height: 900))
        XCTAssertEqual(lock.height(for: CGSize(width: 440, height: 900)), resting)
        XCTAssertEqual(lock.height(for: CGSize(width: 440, height: 820)), resting)
    }

    func testBounceTurnsOffOnlyInTheBottomHalf() {
        func bounces(_ offset: CGFloat, content: CGFloat = 2000) -> Bool {
            BottomEdgeClamp.shouldBounce(
                offsetY: offset,
                contentHeight: content,
                viewportHeight: 900,
                insetTop: 0,
                insetBottom: 100
            )
        }
        XCTAssertTrue(bounces(-80), "pull to refresh at the top keeps its bounce")
        XCTAssertTrue(bounces(500))
        XCTAssertFalse(bounces(700))
        XCTAssertFalse(bounces(1200))
        XCTAssertTrue(bounces(40, content: 500), "short pages are left alone")
    }

    func testHeroHeightRemeasuresOnRotation() {
        var lock = HeroHeightLock()
        lock.lock(CGSize(width: 440, height: 860))
        lock.lock(CGSize(width: 956, height: 400))
        XCTAssertEqual(
            lock.height(for: CGSize(width: 956, height: 400)),
            PosterMetrics.heroHeight(for: CGSize(width: 956, height: 400))
        )
    }
}

final class SidebarLayoutMetricsTests: XCTestCase {
    func testScaleStaysIdentityWhenWidthsMatch() {
        XCTAssertEqual(SidebarLayoutMetrics.scale(contentWidth: 1366, expandedWidth: 1366), 1)
        XCTAssertEqual(SidebarLayoutMetrics.scale(contentWidth: 0, expandedWidth: 1366), 1)
    }

    func testScaleShrinksWhenSidebarTakesWidth() {
        XCTAssertEqual(
            SidebarLayoutMetrics.scale(contentWidth: 1046, expandedWidth: 1366),
            1046 / 1366,
            accuracy: 0.0001
        )
    }

    func testLeadingBleedIsTheSidebarWidth() {
        let layout = ZelefinSidebarLayout(scale: 1046 / 1366, contentWidth: 1046, expandedWidth: 1366)
        XCTAssertEqual(layout.leadingBleed, 320, accuracy: 0.0001)
        XCTAssertEqual(ZelefinSidebarLayout.identity.leadingBleed, 0)
    }

    func testExpandedWidthFreezesWhileSidebarIsVisible() {
        XCTAssertEqual(
            SidebarLayoutMetrics.expandedWidth(
                currentWidth: 1046,
                previousExpandedWidth: 1366,
                isSidebarVisible: true
            ),
            1366
        )
    }

    func testExpandedWidthFollowsContentWhenSidebarCloses() {
        XCTAssertEqual(
            SidebarLayoutMetrics.expandedWidth(
                currentWidth: 834,
                previousExpandedWidth: 1366,
                isSidebarVisible: false
            ),
            834
        )
    }

    func testGridColumnCountUsesExpandedWidth() {
        XCTAssertGreaterThan(
            PosterGridLayout.columnCount(expandedWidth: 1366),
            PosterGridLayout.columnCount(expandedWidth: 834)
        )
        XCTAssertEqual(PosterGridLayout.columnCount(expandedWidth: 100), 3)
    }
}
