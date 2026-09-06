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

    func testCollectionCardTitleDropsCollectionSuffix() {
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("The Accountant Collection"), "The Accountant")
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("101 Dalmatians (Animated) Collection"), "101 Dalmatians (Animated)")
        XCTAssertEqual(MediaItem.strippingCollectionSuffix("Action"), "Action")
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
