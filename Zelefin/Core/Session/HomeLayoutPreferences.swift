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

    static func featured(resume: [MediaItem], nextUp: [MediaItem], merge: Bool) -> [MediaItem] {
        let source = merge ? mergedQueue(resume: resume, nextUp: nextUp) : resume
        return Array(source.prefix(8))
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
            featured: layout.featured.filter { $0.id != itemID },
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
}
