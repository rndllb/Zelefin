import Foundation

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
        recentlyWatched: [MediaItem]
    ) -> [HomeSection] {
        var sections = playbackQueueSections(resume: resume, nextUp: nextUp, merge: merge)
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
