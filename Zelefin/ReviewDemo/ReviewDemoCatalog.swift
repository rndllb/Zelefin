import Foundation
import JellyfinAPI

enum ReviewDemoCatalog {
    static let moviesLibrary = MediaLibrary(id: "demo-lib-movies", name: "Movies", kind: .movie, libraryKind: .movies)
    static let showsLibrary = MediaLibrary(id: "demo-lib-shows", name: "Shows", kind: .series, libraryKind: .shows)
    static let collectionsLibrary = MediaLibrary(
        id: "demo-lib-collections",
        name: "Collections",
        kind: .collection,
        libraryKind: .collections
    )

    static var libraries: [MediaLibrary] {
        [moviesLibrary, showsLibrary, collectionsLibrary]
    }

    static let harborLights = movie(
        id: "demo-movie-harbor",
        name: "Harbor Lights",
        year: 2023,
        runtime: 128 * 60,
        rating: "PG-13",
        genres: ["Drama", "Mystery"],
        overview: "A night-shift dispatcher in a coastal town starts tracing a string of radio calls that no ship will claim.",
        critic: 91,
        community: 8.2,
        videoRange: .dolbyVision,
        audioFormat: .atmos,
        resolution: .fourK,
        position: 42 * 60,
        photo: "1489599849927-2ee91cede3ba"
    )

    static let nightCircuit = movie(
        id: "demo-movie-circuit",
        name: "Night Circuit",
        year: 2024,
        runtime: 109 * 60,
        rating: "R",
        genres: ["Thriller", "Crime"],
        overview: "An engineer is hired to debug a city’s traffic grid and finds the delays are being written on purpose.",
        critic: 84,
        community: 7.6,
        videoRange: .hdr10,
        audioFormat: .surround,
        resolution: .hd,
        photo: "1440404653325-ab127d49abc1"
    )

    static let cartographer = movie(
        id: "demo-movie-map",
        name: "The Last Cartographer",
        year: 2022,
        runtime: 141 * 60,
        rating: "PG-13",
        genres: ["Adventure", "Drama"],
        overview: "A survey team maps a valley that does not appear on any official chart, then has to decide who owns the drawing.",
        critic: 88,
        community: 8.0,
        videoRange: .hdr10,
        audioFormat: .atmos,
        resolution: .fourK,
        photo: "1469474968028-56623f02e42e"
    )

    static let glassHarbor = movie(
        id: "demo-movie-glass",
        name: "Glass Harbor",
        year: 2021,
        runtime: 98 * 60,
        rating: "PG",
        genres: ["Drama"],
        overview: "Two siblings inherit a boarded-up ferry terminal and try to reopen it before the winter schedule is cancelled.",
        critic: 79,
        community: 7.1,
        videoRange: .sdr,
        audioFormat: .surround,
        resolution: .hd,
        photo: "1517604931442-7e0c8ed2963c"
    )

    static let winterFrequency = movie(
        id: "demo-movie-winter",
        name: "Winter Frequency",
        year: 2024,
        runtime: 116 * 60,
        rating: "PG-13",
        genres: ["Mystery", "Science Fiction"],
        overview: "A radio astronomer records a repeating pulse from the ice and follows it inland with a borrowed snowcat.",
        critic: 86,
        community: 7.9,
        videoRange: .dolbyVision,
        audioFormat: .atmos,
        resolution: .fourK,
        photo: "1485846234645-a62644f547ff"
    )

    static let copperSky = movie(
        id: "demo-movie-copper",
        name: "Copper Sky",
        year: 2020,
        runtime: 104 * 60,
        rating: "PG-13",
        genres: ["Adventure"],
        overview: "A salvage pilot agrees to lift one crate from a desert airstrip and spends the rest of the film trying to put it back.",
        critic: 74,
        community: 6.8,
        videoRange: .sdr,
        audioFormat: .stereo,
        resolution: .hd,
        isPlayed: true,
        photo: "1500462918059-b1a0cb512f1d"
    )

    static let stationNorth = series(
        id: "demo-show-station",
        name: "Station North",
        year: 2023,
        rating: "TV-14",
        genres: ["Drama"],
        overview: "Overnight staff at a regional rail hub keep the last trains moving while the city above them goes quiet.",
        unplayed: 3,
        photo: "1536440136628-849c177e76a1"
    )

    static let nightDesk = series(
        id: "demo-show-desk",
        name: "The Night Desk",
        year: 2024,
        rating: "TV-MA",
        genres: ["Crime", "Drama"],
        overview: "A late copy editor starts rewriting crime briefs that have not been filed yet.",
        unplayed: 8,
        photo: "1594908900066-3f47337549d8"
    )

    static let riverProtocol = series(
        id: "demo-show-river",
        name: "River Protocol",
        year: 2022,
        rating: "TV-14",
        genres: ["Science Fiction"],
        overview: "A river authority installs sensors along a flood wall and discovers the water is answering.",
        unplayed: 1,
        photo: "1492619373894-70c8b5d9b4b0"
    )

    static let northAtlantic = collection(
        id: "demo-col-atlantic",
        name: "North Atlantic",
        overview: "Harbor towns, night routes, and cold water.",
        photo: "1478720568477-152d9b164e26"
    )

    static var movies: [MediaItem] {
        [harborLights, nightCircuit, cartographer, glassHarbor, winterFrequency, copperSky]
    }

    static var shows: [MediaItem] {
        [stationNorth, nightDesk, riverProtocol]
    }

    static var collections: [MediaItem] {
        [northAtlantic]
    }

    static var collectionMembers: [String: [MediaItem]] {
        [northAtlantic.id: [harborLights, glassHarbor, cartographer]]
    }

    static var genres: [MediaItem] {
        [
            genre(id: "demo-genre-drama", name: "Drama", photo: "1489599849927-2ee91cede3ba"),
            genre(id: "demo-genre-thriller", name: "Thriller", photo: "1440404653325-ab127d49abc1"),
            genre(id: "demo-genre-adventure", name: "Adventure", photo: "1469474968028-56623f02e42e"),
            genre(id: "demo-genre-scifi", name: "Science Fiction", photo: "1485846234645-a62644f547ff"),
        ]
    }

    static var season: MediaItem {
        item(
            id: "demo-season-station-1",
            name: "Season 1",
            kind: .season,
            year: 2023,
            genres: ["Drama"],
            seriesName: stationNorth.name,
            seasonIndex: 1,
            seriesID: stationNorth.id,
            photo: "1536440136628-849c177e76a1"
        )
    }

    static var episodes: [MediaItem] {
        (1...6).map { index in
            item(
                id: "demo-ep-station-s1e\(index)",
                name: episodeTitle(index),
                kind: .episode,
                overview: "The overnight crew handles a delay that does not match any posted timetable.",
                year: 2023,
                runtime: 48 * 60,
                rating: "TV-14",
                genres: ["Drama"],
                seriesName: stationNorth.name,
                seasonIndex: 1,
                episodeIndex: index,
                position: index == 4 ? 18 * 60 : 0,
                seriesID: stationNorth.id,
                queueKind: index == 4 ? .resume : .nextUp,
                photo: "1536440136628-849c177e76a1"
            )
        }
    }

    static var continueWatching: [MediaItem] {
        [harborLights, episodes[3]]
    }

    static var nextUp: [MediaItem] {
        [episodes[4]]
    }

    static var recentlyWatched: [MediaItem] {
        [copperSky]
    }

    static var featured: [MediaItem] {
        [harborLights, stationNorth, winterFrequency, nightDesk]
    }

    static var recentlyAddedMovies: HomeSection {
        HomeSection(id: "library-\(moviesLibrary.id)", title: "Recently Added Movies", style: .portrait, items: movies)
    }

    static var recentlyAddedShows: HomeSection {
        HomeSection(id: "library-shows", title: "Recently Added Shows", style: .portrait, items: shows)
    }

    static var collectionsSection: HomeSection {
        HomeSection(id: "collections", title: "Browse by Collection", style: .labeledPortrait, items: collections)
    }

    static var genresSection: HomeSection {
        HomeSection(id: "genres", title: "Browse by Genre", style: .labeledPortrait, items: genres)
    }

    static var credits: [CreditPerson] {
        [
            CreditPerson(id: "demo-person-ada", name: "Ada Kern", roleLabel: "Lead", imageTag: nil, rank: 0),
            CreditPerson(id: "demo-person-nolan", name: "Nolan Voss", roleLabel: "Lead", imageTag: nil, rank: 0),
            CreditPerson(id: "demo-person-mira", name: "Mira Solano", roleLabel: "Supporting", imageTag: nil, rank: 0),
            CreditPerson(id: "demo-person-helen", name: "Helen Park", roleLabel: "Director", imageTag: nil, rank: 1),
        ]
    }

    static let sampleStreamURL = URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!

    static func item(id: String) -> MediaItem? {
        all.first { $0.id == id }
    }

    static func related(to item: MediaItem) -> [MediaItem] {
        let pool = item.kind == .series || item.kind == .season || item.kind == .episode ? shows : movies
        return pool.filter { $0.id != item.id && $0.id != item.seriesID }
    }

    static func trailers(for id: String) -> [TitleTrailer] {
        guard item(id: id) != nil else { return [] }
        return [TitleTrailer.youtube(id: "aqz-KE-bpKQ", title: "Official Trailer")]
    }

    static func dto(for item: MediaItem) -> BaseItemDto {
        var dto = BaseItemDto()
        dto.id = item.id
        dto.name = item.name
        dto.overview = item.overview
        dto.productionYear = item.year
        dto.officialRating = item.officialRating
        dto.genres = item.genres
        dto.seriesID = item.seriesID
        dto.seriesName = item.seriesName
        dto.communityRating = item.communityRating.map { Float($0) }
        dto.criticRating = item.criticRating.map { Float($0) }
        dto.runTimeTicks = item.runtime.map { TickClock.intTicks(from: $0) }
        dto.type = baseKind(item.kind)
        return dto
    }

    static func artworkURL(for item: MediaItem, portrait: Bool) -> URL? {
        let seed = item.imageItemID ?? item.id
        let size = portrait ? "w=600&h=900" : "w=1400&h=788"
        return URL(string: "https://images.unsplash.com/\(photoPath(seed))?\(size)&auto=format&fit=crop&q=80")
    }

    static func search(term: String) -> [MediaItem] {
        let needle = term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return (movies + shows + episodes).filter {
            $0.name.lowercased().contains(needle)
                || ($0.seriesName?.lowercased().contains(needle) ?? false)
                || $0.genres.contains { $0.lowercased().contains(needle) }
        }
    }

    static func items(matching query: CatalogBrowseQuery, from pool: [MediaItem]) -> [MediaItem] {
        var result = pool
        if !query.genres.isEmpty {
            result = result.filter { item in item.genres.contains { query.genres.contains($0) } }
        }
        if !query.years.isEmpty {
            result = result.filter { query.years.contains($0.year ?? 0) }
        }
        if !query.officialRatings.isEmpty {
            result = result.filter { query.officialRatings.contains($0.officialRating ?? "") }
        }
        if query.statuses.contains(.played) {
            result = result.filter(\.isPlayed)
        }
        if query.statuses.contains(.unplayed) {
            result = result.filter { !$0.isPlayed }
        }
        if query.statuses.contains(.continueWatching) {
            result = result.filter { $0.playbackPosition > 0 }
        }
        let resolutions = query.videoKinds.filter(\.isResolution)
        if !resolutions.isEmpty {
            result = result.filter { item in
                (resolutions.contains(.fourK) && item.videoResolution == .fourK)
                    || (resolutions.contains(.hd) && item.videoResolution == .hd)
                    || (resolutions.contains(.sd) && item.videoResolution == .sd)
            }
        }
        return query.sorted(result)
    }

    static func filterOptions(from items: [MediaItem]) -> CatalogFilterOptions {
        CatalogFilterOptions(
            genres: CatalogFilterLists.choices(from: Array(Set(items.flatMap(\.genres))).sorted()),
            officialRatings: CatalogFilterLists.choices(from: items.compactMap(\.officialRating)),
            years: CatalogFilterLists.yearChoices(from: items.compactMap(\.year)),
            studios: [CatalogFilterChoice(id: "North Pier", name: "North Pier")]
        )
    }

    static func items(in library: MediaLibrary) -> [MediaItem] {
        switch library.libraryKind {
        case .movies: movies
        case .shows: shows
        case .collections: collections
        default: []
        }
    }

    static func items(genreID: String) -> [MediaItem] {
        let name = genres.first { $0.id == genreID }?.name
        guard let name else { return [] }
        return (movies + shows).filter { $0.genres.contains(name) }
    }

    static func items(parentID: String) -> [MediaItem] {
        if parentID == season.id || parentID == stationNorth.id {
            return episodes
        }
        return collectionMembers[parentID] ?? []
    }

    private static var all: [MediaItem] {
        movies + shows + collections + genres + [season] + episodes
    }

    private static func episodeTitle(_ index: Int) -> String {
        switch index {
        case 1: "Last Call"
        case 2: "Hold for Weather"
        case 3: "Platform Four"
        case 4: "Signal Delay"
        case 5: "Through Freight"
        default: "Clear Board"
        }
    }

    private static func movie(
        id: String,
        name: String,
        year: Int,
        runtime: TimeInterval,
        rating: String,
        genres: [String],
        overview: String,
        critic: Double,
        community: Double,
        videoRange: VideoRange,
        audioFormat: AudioFormat,
        resolution: VideoResolution,
        position: TimeInterval = 0,
        isPlayed: Bool = false,
        photo: String
    ) -> MediaItem {
        item(
            id: id,
            name: name,
            kind: .movie,
            overview: overview,
            year: year,
            runtime: runtime,
            rating: rating,
            genres: genres,
            position: position,
            isPlayed: isPlayed,
            videoRange: videoRange,
            audioFormat: audioFormat,
            critic: critic,
            community: community,
            resolution: resolution,
            photo: photo
        )
    }

    private static func series(
        id: String,
        name: String,
        year: Int,
        rating: String,
        genres: [String],
        overview: String,
        unplayed: Int,
        photo: String
    ) -> MediaItem {
        item(
            id: id,
            name: name,
            kind: .series,
            overview: overview,
            year: year,
            rating: rating,
            genres: genres,
            unplayed: unplayed,
            critic: 82,
            community: 7.8,
            photo: photo
        )
    }

    private static func collection(id: String, name: String, overview: String, photo: String) -> MediaItem {
        item(id: id, name: name, kind: .collection, overview: overview, genres: ["Drama"], photo: photo)
    }

    private static func genre(id: String, name: String, photo: String) -> MediaItem {
        item(id: id, name: name, kind: .genre, photo: photo)
    }

    private static func item(
        id: String,
        name: String,
        kind: MediaKind,
        overview: String? = nil,
        year: Int? = nil,
        runtime: TimeInterval? = nil,
        rating: String? = nil,
        genres: [String] = [],
        seriesName: String? = nil,
        seasonIndex: Int? = nil,
        episodeIndex: Int? = nil,
        position: TimeInterval = 0,
        unplayed: Int? = nil,
        isPlayed: Bool = false,
        videoRange: VideoRange = .sdr,
        audioFormat: AudioFormat = .unknown,
        critic: Double? = nil,
        community: Double? = nil,
        resolution: VideoResolution = .hd,
        seriesID: String? = nil,
        queueKind: PlaybackQueueKind = .resume,
        photo: String
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: overview,
            year: year,
            runtime: runtime,
            officialRating: rating,
            genres: genres,
            seriesName: seriesName,
            seasonIndex: seasonIndex,
            episodeIndex: episodeIndex,
            playbackPosition: position,
            unplayedCount: unplayed,
            isPlayed: isPlayed,
            primaryImageTag: "demo",
            thumbImageTag: "demo",
            backdropImageTag: "demo",
            backdropImageTags: ["demo"],
            logoImageTag: nil,
            parentBackdropItemID: seriesID,
            parentThumbItemID: seriesID,
            parentThumbImageTag: seriesID == nil ? nil : "demo",
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: seriesID == nil ? nil : "demo",
            seriesID: seriesID,
            imageItemID: photo,
            queueKind: queueKind,
            videoRange: videoRange,
            audioFormat: audioFormat,
            criticRating: critic,
            communityRating: community,
            dateCreated: Date().addingTimeInterval(-86_400),
            videoResolution: resolution,
            hasClosedCaptions: true,
            tmdbID: nil
        )
    }

    private static func photoPath(_ seed: String) -> String {
        if seed.hasPrefix("photo-") || seed.contains("-") && seed.count > 20 {
            return seed.hasPrefix("photo-") ? seed : "photo-\(seed)"
        }
        return "photo-\(seed)"
    }

    private static func baseKind(_ kind: MediaKind) -> BaseItemKind {
        switch kind {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .collection: .boxSet
        case .genre: .genre
        case .unknown: .movie
        }
    }
}
