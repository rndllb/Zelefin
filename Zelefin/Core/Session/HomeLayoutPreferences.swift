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
    static let freeOrder: [HomeRowKind] = [
        .featured,
        .continueWatching,
        .recentlyAddedMovies,
        .recentlyAddedShows
    ]

    var id: String { rawValue }

    var isIncludedInFreeLayout: Bool {
        Self.freeOrder.contains(self)
    }

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
        hidden: Set<HomeRowKind>,
        isPlus: Bool = true
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

        let resolvedOrder: [HomeRowKind]
        let resolvedHidden: Set<HomeRowKind>
        if isPlus {
            resolvedOrder = HomeRowKind.ordered(from: HomeRowKind.raw(from: order))
            resolvedHidden = hidden
        } else {
            resolvedOrder = HomeRowKind.freeOrder
            resolvedHidden = Set(HomeRowKind.allCases).subtracting(HomeRowKind.freeOrder)
        }

        var feed: [HomeFeedItem] = []
        for kind in resolvedOrder where !resolvedHidden.contains(kind) {
            if kind == .featured {
                if !featured.isEmpty {
                    feed.append(.featured(featured))
                }
                continue
            }
            feed.append(contentsOf: (buckets[kind] ?? []).map(HomeFeedItem.section))
        }
        if isPlus {
            feed.append(contentsOf: leftovers.map(HomeFeedItem.section))
        }
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

    static func applyGenreCovers(_ genres: [MediaItem], covers: [MediaItem]) -> [MediaItem] {
        let posters = covers.filter(\.hasGenreCoverArt).shuffled()
        var usedIDs = Set<String>()

        return genres.map { genre in
            let key = genre.name.lowercased()
            func matches(_ cover: MediaItem) -> Bool {
                cover.genres.contains { $0.lowercased() == key }
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
