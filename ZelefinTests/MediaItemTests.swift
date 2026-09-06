import XCTest
@testable import Zelefin

final class TickClockTests: XCTestCase {
    func testSecondsRoundTrip() {
        let ticks: Int64 = 90 * TickClock.ticksPerSecond
        XCTAssertEqual(TickClock.seconds(from: ticks), 90, accuracy: 0.001)
        XCTAssertEqual(TickClock.ticks(from: 90), ticks)
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
            [.download, .play, .goToShow, .markWatched]
        )
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: .episode), "Play Episode")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: .episode), "Go to Show")
    }

    func testMovieUsesPlayAndGoToMovie() {
        XCTAssertEqual(PlaybackQueueMenuLayout.playTitle(for: .movie), "Play")
        XCTAssertEqual(PlaybackQueueMenuLayout.goToTitle(for: .movie), "Go to Movie")
    }

    func testRecentlyWatchedAddsRemove() {
        XCTAssertEqual(
            PlaybackQueueMenuLayout.actions(context: .recentlyWatched, kind: .episode),
            [.download, .play, .goToShow, .markWatched, .removeFromRecentlyWatched]
        )
    }
}

final class HomeLayoutPreferencesTests: XCTestCase {
    func testSeparateKeepsTwoRows() {
        let resume = [Self.item(id: "r1", queueKind: .resume)]
        let nextUp = [Self.item(id: "n1", queueKind: .nextUp)]
        let sections = HomeLayoutPreferences.playbackQueueSections(resume: resume, nextUp: nextUp, merge: false)

        XCTAssertEqual(sections.map(\.id), ["continue", "next-up"])
        XCTAssertEqual(sections[0].items.map(\.id), ["r1"])
        XCTAssertEqual(sections[1].items.map(\.id), ["n1"])
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
        XCTAssertEqual(next.featured.map(\.id), [])
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

    func testMergedFeaturedFallsBackToNextUp() {
        let featured = HomeLayoutPreferences.featured(
            resume: [],
            nextUp: [Self.item(id: "n1", queueKind: .nextUp)],
            merge: true
        )
        XCTAssertEqual(featured.map(\.id), ["n1"])
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
            ["m", "s", "home", "mix"]
        )
        XCTAssertEqual(LibraryKind.movies.recentlyAddedTitle(libraryName: "Movies"), "Recently Added Movies")
        XCTAssertEqual(LibraryKind.shows.recentlyAddedTitle(libraryName: "TV"), "Recently Added Shows")
        XCTAssertEqual(LibraryKind.inferred(fromName: "TV Shows"), .shows)
        XCTAssertFalse(LibraryKind.collections.appearsOnHome)
        XCTAssertEqual(
            HomeLayoutPreferences.libraryTabLibraries(libraries).map(\.id),
            ["m", "s", "tv", "mix"]
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
        XCTAssertTrue(LibraryKind.other.appearsInLibrary)
        XCTAssertFalse(LibraryKind.music.appearsInLibrary)
        XCTAssertFalse(LibraryKind.collections.appearsInLibrary)
        XCTAssertFalse(LibraryKind.homeVideos.appearsInLibrary)

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

    private static func item(id: String) -> MediaItem {
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

    func testWikidataSparqlUsesImdbAndTmdb() {
        let query = WikidataTrailers.sparql(imdbID: "tt1375666", tmdbID: 27205, isSeries: false)
        XCTAssertTrue(query?.contains("P345 \"tt1375666\"") == true)
        XCTAssertTrue(query?.contains("P4947 \"27205\"") == true)
        XCTAssertTrue(query?.contains("P1651") == true)
        XCTAssertNil(WikidataTrailers.sparql(imdbID: nil, tmdbID: nil, isSeries: false))

        let series = WikidataTrailers.sparql(imdbID: nil, tmdbID: 1396, isSeries: true)
        XCTAssertTrue(series?.contains("P4983 \"1396\"") == true)
    }
}

final class AppTabTests: XCTestCase {
    func testOrderedKeepsKnownTabsAndFillsMissing() {
        XCTAssertEqual(AppTab.ordered(from: "library,movies"), [.library, .movies, .home, .shows])
        XCTAssertEqual(AppTab.ordered(from: "nope,home"), [.home, .movies, .shows, .library])
        XCTAssertEqual(AppTab.raw(from: [.shows, .home, .shows]), "shows,home")
    }

    func testHomeCannotBeHidden() {
        XCTAssertFalse(AppTab.home.canHide)
        XCTAssertTrue(AppTab.movies.canHide)
        XCTAssertEqual(AppTab.library.customizationID, "app.zelefin.tab.library")
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
