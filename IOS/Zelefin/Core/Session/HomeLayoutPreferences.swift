import Foundation

enum HomeRowKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case featured
    case continueWatching
    case nextUp
    case upcoming
    case recommendations
    case recentlyAddedMovies
    case recentlyAddedShows
    case collections
    case genres
    case recentlyWatched

    static let orderStorageKey = "zelefin.home-row-order"
    static let hiddenStorageKey = "zelefin.home-row-hidden"
    static let defaultOrderRaw = allCases.map(\.rawValue).joined(separator: ",")

    var id: String { rawValue }

    var title: String {
        switch self {
        case .featured: "Featured"
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case .upcoming: "Upcoming Episodes"
        case .recommendations: "Recommendations"
        case .recentlyAddedMovies: "Recently Added Movies"
        case .recentlyAddedShows: "Recently Added Shows"
        case .collections: "Collections"
        case .genres: "Genres"
        case .recentlyWatched: "Recently Watched"
        }
    }

    var systemImage: String {
        switch self {
        case .featured: "sparkles.tv"
        case .continueWatching: "play.circle"
        case .nextUp: "forward.end"
        case .upcoming: "calendar"
        case .recommendations: "star"
        case .recentlyAddedMovies: "film"
        case .recentlyAddedShows: "tv"
        case .collections: "square.grid.2x2.fill"
        case .genres: "square.grid.2x2"
        case .recentlyWatched: "clock.arrow.circlepath"
        }
    }

    static func ordered(from raw: String) -> [HomeRowKind] {
        var seen = Set<HomeRowKind>()
        var order: [HomeRowKind] = []
        for token in raw.split(separator: ",") {
            guard let kind = HomeRowKind(rawValue: String(token)), seen.insert(kind).inserted else { continue }
            order.append(kind)
        }
        for kind in allCases where seen.insert(kind).inserted {
            order.append(kind)
        }
        return order
    }

    static func raw(from order: [HomeRowKind]) -> String {
        var seen = Set<HomeRowKind>()
        return order.compactMap { kind in
            seen.insert(kind).inserted ? kind.rawValue : nil
        }.joined(separator: ",")
    }

    static func hidden(from raw: String) -> Set<HomeRowKind> {
        Set(raw.split(separator: ",").compactMap { HomeRowKind(rawValue: String($0)) })
    }

    static func hiddenRaw(from hidden: Set<HomeRowKind>) -> String {
        hidden.map(\.rawValue).sorted().joined(separator: ",")
    }

    static func kind(forSectionID id: String) -> HomeRowKind? {
        switch id {
        case "continue": return HomeRowKind.continueWatching
        case "next-up": return HomeRowKind.nextUp
        case "upcoming": return HomeRowKind.upcoming
        case "collections": return HomeRowKind.collections
        case "genres": return HomeRowKind.genres
        case "recently-watched": return HomeRowKind.recentlyWatched
        case "library-shows": return HomeRowKind.recentlyAddedShows
        default:
            if id.hasPrefix("recommend-") { return HomeRowKind.recommendations }
            if id.hasPrefix("library-") { return HomeRowKind.recentlyAddedMovies }
            return nil
        }
    }
}

enum HomeFeedItem: Identifiable, Hashable, Sendable {
    case featured([MediaItem])
    case section(HomeSection)

    var id: String {
        switch self {
        case .featured: HomeRowKind.featured.rawValue
        case .section(let section): section.id
        }
    }
}

enum FeaturedHeroContent: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded
    case random
    case continueWatching
    case nextUp
    case recommendations
    case recentlyWatched
    case favorites

    static let storageKey = "zelefin.home-hero-content"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .random: "Random"
        case .continueWatching: "Continue Watching"
        case .nextUp: "Next Up"
        case .recommendations: "Recommendations"
        case .recentlyWatched: "Recently Watched"
        case .favorites: "Favorites"
        }
    }

    static var current: FeaturedHeroContent {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? ""
        if let value = FeaturedHeroContent(rawValue: raw) { return value }
        return .recentlyAdded
    }
}

enum HomeLayoutPreferences {
    static let mergeContinueAndNextUpKey = "zelefin.merge-continue-next-up"

    static var mergeContinueAndNextUp: Bool {
        UserDefaults.standard.bool(forKey: mergeContinueAndNextUpKey)
    }

    static func playbackQueueSections(resume: [MediaItem], nextUp: [MediaItem], merge: Bool) -> [HomeSection] {
        if merge {
            let items = mergedQueue(resume: resume, nextUp: nextUp)
            guard !items.isEmpty else { return [] }
            return [HomeSection(id: "continue", title: "Continue Watching", style: .landscape, items: items)]
        }

        var sections: [HomeSection] = []
        if !resume.isEmpty {
            sections.append(HomeSection(id: "continue", title: "Continue Watching", style: .landscape, items: resume))
        }
        if !nextUp.isEmpty {
            sections.append(HomeSection(id: "next-up", title: "Next Up", style: .landscape, items: nextUp))
        }
        return sections
    }

    static func assemble(
        resume: [MediaItem],
        nextUp: [MediaItem],
        merge: Bool,
        libraries: [HomeSection],
        collections: HomeSection?,
        genres: HomeSection?,
        recentlyWatched: [MediaItem],
        recommendations: [HomeSection] = [],
        upcoming: [MediaItem] = []
    ) -> [HomeSection] {
        var sections = playbackQueueSections(resume: resume, nextUp: nextUp, merge: merge)
        if !upcoming.isEmpty {
            sections.append(
                HomeSection(id: "upcoming", title: "Upcoming Episodes", style: .landscape, items: upcoming)
            )
        }
        sections.append(contentsOf: recommendations)
        sections.append(contentsOf: librarySectionsExcludingCollections(libraries))
        if let collections { sections.append(collections) }
        if let genres { sections.append(genres) }
        if !recentlyWatched.isEmpty {
            sections.append(
                HomeSection(
                    id: "recently-watched",
                    title: "Recently Watched",
                    style: .replayLandscape,
                    items: recentlyWatched
                )
            )
        }
        return sections
    }

    static func feed(
        featured: [MediaItem],
        sections: [HomeSection],
        order: [HomeRowKind],
        hidden: Set<HomeRowKind>
    ) -> [HomeFeedItem] {
        var buckets: [HomeRowKind: [HomeSection]] = [:]
        var leftovers: [HomeSection] = []
        for section in sections {
            if let kind = HomeRowKind.kind(forSectionID: section.id) {
                buckets[kind, default: []].append(section)
            } else {
                leftovers.append(section)
            }
        }

        let resolvedOrder = HomeRowKind.ordered(from: HomeRowKind.raw(from: order))
        var feed: [HomeFeedItem] = []
        for kind in resolvedOrder where !hidden.contains(kind) {
            if kind == .featured {
                if !featured.isEmpty {
                    feed.append(.featured(featured))
                }
                continue
            }
            feed.append(contentsOf: (buckets[kind] ?? []).map(HomeFeedItem.section))
        }
        feed.append(contentsOf: leftovers.map(HomeFeedItem.section))
        return feed
    }

    static func orderedHomeLibraries(_ libraries: [MediaLibrary]) -> [MediaLibrary] {
        let eligible = libraries.filter { library in
            library.libraryKind.appearsOnHome && !library.name.localizedCaseInsensitiveContains("collection")
        }
        let movies = eligible.filter { $0.libraryKind == .movies }
        let shows = eligible.filter { $0.libraryKind == .shows }
        let rest = eligible.filter { $0.libraryKind != .movies && $0.libraryKind != .shows }
        return movies + shows + rest
    }

    static func libraryTabLibraries(_ libraries: [MediaLibrary]) -> [MediaLibrary] {
        libraries.filter(\.libraryKind.appearsInLibrary)
    }

    static func libraries(_ libraries: [MediaLibrary], matching kind: LibraryKind) -> [MediaLibrary] {
        libraries.filter { $0.libraryKind == kind }
    }

    static func librarySectionsExcludingCollections(_ sections: [HomeSection]) -> [HomeSection] {
        sections.filter { !$0.isRecentlyAddedCollections }
    }

    static func collapseRecentlyWatched(_ items: [MediaItem]) -> [MediaItem] {
        var seenSeries = Set<String>()
        var collapsed: [MediaItem] = []
        for item in items {
            if item.kind == .episode, let seriesID = item.seriesID {
                if seenSeries.contains(seriesID) { continue }
                seenSeries.insert(seriesID)
            }
            collapsed.append(item)
            if collapsed.count == 20 { break }
        }
        return collapsed
    }

    /// "Game Show" and "Game-Show" are the same genre.
    static func genreKey(_ name: String) -> String {
        name.lowercased().filter(\.isLetter) + name.lowercased().filter(\.isNumber)
    }

    /// Music libraries and music genres are not a supported catalog.
    static func isBrowsableGenre(_ name: String) -> Bool {
        switch genreKey(name) {
        case "music", "musicvideo", "musicvideos", "actionadventure", "actionandadventure", "adventureaction", "adventureandaction":
            false
        default:
            true
        }
    }

    static func collapsedGenres(_ genres: [MediaItem]) -> [MediaItem] {
        var chosen: [String: MediaItem] = [:]
        var order: [String] = []
        for genre in genres {
            let key = genreKey(genre.name)
            guard !key.isEmpty, isBrowsableGenre(genre.name) else { continue }
            if let existing = chosen[key] {
                if prefersGenreName(genre.name, over: existing.name) {
                    chosen[key] = genre
                }
            } else {
                chosen[key] = genre
                order.append(key)
            }
        }
        return order.compactMap { chosen[$0] }
    }

    private static func prefersGenreName(_ candidate: String, over current: String) -> Bool {
        let candidateSplit = candidate.contains("-")
        let currentSplit = current.contains("-")
        if currentSplit && !candidateSplit { return true }
        if candidateSplit && !currentSplit { return false }
        return candidate.count < current.count
    }

    static func applyGenreCovers(_ genres: [MediaItem], covers: [MediaItem]) -> [MediaItem] {
        let posters = covers.filter(\.hasGenreCoverArt).shuffled()
        var usedIDs = Set<String>()

        return genres.map { genre in
            let key = genreKey(genre.name)
            func matches(_ cover: MediaItem) -> Bool {
                cover.genres.contains { genreKey($0) == key }
            }

            if let cover = posters.first(where: { matches($0) && !usedIDs.contains($0.id) }) {
                usedIDs.insert(cover.id)
                return genre.withCover(from: cover)
            }
            if let cover = posters.first(where: matches) {
                return genre.withCover(from: cover)
            }
            return genre
        }
    }

    static let featuredLimit = 8

    static func featured(latestMovies: [MediaItem], latestShows: [MediaItem]) -> [MediaItem] {
        interleaveForHero(rankedForHero(latestMovies), rankedForHero(latestShows), limit: featuredLimit)
    }

    static func hero(
        recentlyAdded: [MediaItem],
        continueWatching: [MediaItem],
        nextUp: [MediaItem],
        recentlyWatched: [MediaItem],
        recommendations: [HomeSection],
        source: FeaturedHeroContent = .current
    ) -> [MediaItem] {
        let pool: [MediaItem]
        switch source {
        case .recentlyAdded, .random, .favorites:
            pool = recentlyAdded
        case .continueWatching:
            pool = continueWatching
        case .nextUp:
            pool = nextUp
        case .recentlyWatched:
            pool = recentlyWatched
        case .recommendations:
            pool = recommendations.flatMap(\.items)
        }
        var seen = Set<String>()
        let unique = pool.filter { seen.insert($0.id).inserted }
        return Array(rankedForHero(unique).prefix(featuredLimit))
    }

    /// Home-feed hero URLs are requested at `image_size=large`; catalog cards are not.
    static func replacingHeroArtwork(on items: [MediaItem], with sources: [MediaItem]) -> [MediaItem] {
        guard !sources.isEmpty else { return items }
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return items.map { item in
            guard let source = byID[item.id] else { return item }
            var copy = item
            if source.backdropURL != nil { copy.backdropURL = source.backdropURL }
            if source.logoURL != nil { copy.logoURL = source.logoURL }
            if copy.posterURL == nil { copy.posterURL = source.posterURL }
            return copy
        }
    }

    static func isPlaybackQueueSection(_ id: String) -> Bool {
        id == "continue" || id == "next-up"
    }

    static func menuContext(forSectionID id: String) -> PlaybackQueueMenuContext? {
        switch id {
        case "continue": .continueWatching
        case "next-up": .nextUp
        case "recently-watched": .recentlyWatched
        default: nil
        }
    }

    static func removing(_ itemID: String, from layout: HomeLayout) -> HomeLayout {
        HomeLayout(
            featured: layout.featured,
            sections: layout.sections.compactMap { section in
                let items = section.items.filter { $0.id != itemID }
                if items.isEmpty, isPlaybackQueueSection(section.id) || section.isRecentlyWatched {
                    return nil
                }
                return HomeSection(id: section.id, title: section.title, style: section.style, items: items)
            }
        )
    }

    private static func mergedQueue(resume: [MediaItem], nextUp: [MediaItem]) -> [MediaItem] {
        let resumeIDs = Set(resume.map(\.id))
        return resume + nextUp.filter { !resumeIDs.contains($0.id) }
    }

    private static func rankedForHero(_ items: [MediaItem]) -> [MediaItem] {
        let withArt = items.filter(\.hasHeroBackdrop)
        let source = withArt.isEmpty ? items : withArt
        return source.filter { !$0.isPlayed } + source.filter(\.isPlayed)
    }

    private static func interleaveForHero(_ movies: [MediaItem], _ shows: [MediaItem], limit: Int) -> [MediaItem] {
        var result: [MediaItem] = []
        var seen = Set<String>()
        let count = max(movies.count, shows.count)
        for index in 0..<count {
            if index < movies.count, seen.insert(movies[index].id).inserted {
                result.append(movies[index])
                if result.count == limit { return result }
            }
            if index < shows.count, seen.insert(shows[index].id).inserted {
                result.append(shows[index])
                if result.count == limit { return result }
            }
        }
        return result
    }
}

enum FeaturedHeroPaging {
    static let turnDistance: CGFloat = 48
    static let tapSlop: CGFloat = 16

    static func selectionDelta(translation: CGSize) -> Int? {
        guard abs(translation.width) >= turnDistance,
              abs(translation.width) > abs(translation.height)
        else { return nil }
        return translation.width < 0 ? 1 : -1
    }

    static func opensDetail(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) < tapSlop
    }

    static func shouldClaimPan(velocity: CGSize) -> Bool {
        abs(velocity.width) > abs(velocity.height)
    }
}

enum LibraryPageBlock: String, CaseIterable, Identifiable, Hashable, Sendable {
    case favorites
    case watchlist
    case downloaded
    case genres
    case collections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "Favorites"
        case .watchlist: "Watchlist"
        case .downloaded: "Downloaded"
        case .genres: "Genres"
        case .collections: "Collections"
        }
    }

    var systemImage: String {
        switch self {
        case .favorites: "heart.fill"
        case .watchlist: "text.badge.plus"
        case .downloaded: "arrow.down.circle.fill"
        case .genres: "square.grid.2x2.fill"
        case .collections: "square.stack.fill"
        }
    }
}

enum LibraryLayoutPreferences {
    static let orderKey = "zelefin.library-order"
    static let hiddenKey = "zelefin.library-hidden"
    static let pageHiddenKey = "zelefin.library-page-hidden"

    static func arranged(_ libraries: [MediaLibrary], orderRaw: String) -> [MediaLibrary] {
        var remaining = Dictionary(uniqueKeysWithValues: libraries.map { ($0.id, $0) })
        var ordered: [MediaLibrary] = []
        for token in orderRaw.split(separator: ",") {
            let id = String(token)
            if let library = remaining.removeValue(forKey: id) {
                ordered.append(library)
            }
        }
        for library in libraries where remaining[library.id] != nil {
            ordered.append(library)
        }
        return ordered
    }

    static func displayed(
        _ libraries: [MediaLibrary],
        orderRaw: String,
        hiddenRaw: String
    ) -> [MediaLibrary] {
        let hidden = hiddenIDs(from: hiddenRaw)
        return arranged(libraries, orderRaw: orderRaw).filter { !hidden.contains($0.id) }
    }

    static func hiddenIDs(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func hiddenRaw(from hidden: Set<String>) -> String {
        hidden.sorted().joined(separator: ",")
    }

    static func orderRaw(from libraries: [MediaLibrary]) -> String {
        libraries.map(\.id).joined(separator: ",")
    }

    /// Empty means the default arrangement. `none` means the user showed every block.
    static let shownAllToken = "none"

    static func hiddenBlocks(from raw: String) -> Set<LibraryPageBlock> {
        if raw.isEmpty { return [.collections] }
        if raw == shownAllToken { return [] }
        return Set(raw.split(separator: ",").compactMap { LibraryPageBlock(rawValue: String($0)) })
    }

    static func pageHiddenRaw(from hidden: Set<LibraryPageBlock>) -> String {
        if hidden.isEmpty { return shownAllToken }
        return hidden.map(\.rawValue).sorted().joined(separator: ",")
    }
}
