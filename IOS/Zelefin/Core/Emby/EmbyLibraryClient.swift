import Foundation
import JellyfinAPI
import os

/// Catalog, artwork, and playback for an Emby server through Emby's own API. Responses decode
/// leniently into the shared DTOs so `ItemMapper` maps them exactly as it maps Jellyfin's.
final class EmbyLibraryClient: @unchecked Sendable {
    let api: EmbyAPI
    let userID: String
    let artwork: ArtworkURLBuilder
    private let streams: StreamURLBuilder
    private let cinemaIntroCache = OSAllocatedUnfairLock<[String: [MediaItem]]>(initialState: [:])

    init(api: EmbyAPI, userID: String) {
        self.api = api
        self.userID = userID
        self.artwork = ArtworkURLBuilder(serverURL: api.serverURL, accessToken: api.accessToken)
        self.streams = StreamURLBuilder(serverURL: api.serverURL, accessToken: api.accessToken)
    }

    func updateServerVersion(_ raw: String?) {}

    // MARK: Artwork

    func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL? {
        switch style {
        case .landscape, .replayLandscape:
            return artwork.thumb(for: item, maxWidth: 640)
        case .portrait, .ranked:
            return artwork.primary(for: item, maxHeight: ArtworkURLBuilder.posterMaxHeight)
        case .labeledPortrait:
            if item.kind == .genre {
                return artwork.genreCover(for: item, maxWidth: 480)
            }
            return artwork.primary(for: item, maxHeight: ArtworkURLBuilder.posterMaxHeight)
        }
    }

    func programStillURL(for item: MediaItem, channel: MediaItem?) -> URL? {
        primaryURL(for: item) ?? channel.flatMap { primaryURL(for: $0) }
    }

    func primaryURL(for item: MediaItem, maxHeight: Int) -> URL? {
        artwork.primary(for: item, maxHeight: maxHeight)
    }

    func backdropURL(for item: MediaItem, maxWidth: Int) -> URL? {
        artwork.backdrop(for: item, maxWidth: maxWidth)
    }

    func bannerURL(for item: MediaItem, maxWidth: Int) -> URL? {
        artwork.banner(for: item, maxWidth: maxWidth)
    }

    func logoURL(for item: MediaItem, maxHeight: Int) -> URL? {
        artwork.logo(for: item, maxHeight: maxHeight)
    }

    func userAvatarURL(userID: String, tag: String?) -> URL? {
        artwork.userAvatar(userID: userID, tag: tag)
    }

    func personImageURL(id: String, tag: String?, maxHeight: Int) -> URL? {
        artwork.image(itemID: id, type: "Primary", tag: tag, maxHeight: maxHeight)
    }

    func searchHitImageURL(_ hit: LibrarySearchHit) -> URL? {
        if let imageURL = hit.imageURL { return imageURL }
        switch hit.kind {
        case .person:
            return personImageURL(id: hit.id, tag: hit.imageTag)
        default:
            return artwork.image(
                itemID: hit.id,
                type: "Primary",
                tag: hit.imageTag,
                maxHeight: ArtworkURLBuilder.posterMaxHeight,
                format: "jpg"
            )
        }
    }

    func cacheableArtworkURLs(for item: MediaItem) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        let candidates: [URL?] = [
            primaryURL(for: item),
            artworkURL(for: item, style: .landscape),
            backdropURL(for: item),
            bannerURL(for: item),
            logoURL(for: item)
        ]
        for url in candidates.compactMap({ $0 }) where seen.insert(url.absoluteString).inserted {
            urls.append(url)
        }
        return urls
    }

    func chapterImageURL(itemID: String, index: Int, tag: String?) -> URL? {
        artwork.image(itemID: itemID, type: "Chapter/\(index)", tag: tag, maxWidth: 480, format: "jpg")
    }

    /// Emby has no Jellyfin trickplay tiles; scrub previews come from `PlaybackPlan.bifPreviewURL`.
    func trickplayTileURL(itemID: String, info: TrickplayInfo, time: TimeInterval) -> URL? { nil }

    // MARK: Home

    func resumeItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors {
            try await self.dtos(
                "/Users/\(self.userID)/Items/Resume",
                query: [
                    ("Limit", "20"),
                    ("Recursive", "true"),
                    ("Fields", EmbyFields.list),
                    ("MediaTypes", "Video"),
                    ("EnableUserData", "true"),
                    ("EnableImageTypes", EmbyFields.imageTypes)
                ]
            ).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .resume) }
        } ?? []
    }

    func nextUpItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors {
            try await self.dtos(
                "/Shows/NextUp",
                query: [
                    ("UserId", self.userID),
                    ("Limit", "20"),
                    ("Fields", EmbyFields.list),
                    ("EnableImages", "true"),
                    ("EnableImageTypes", EmbyFields.imageTypes),
                    ("EnableUserData", "true")
                ]
            ).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .nextUp) }
        } ?? []
    }

    func recentlyWatchedIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors {
            let items = try await self.userItems([
                ("Limit", "40"),
                ("Recursive", "true"),
                ("SortBy", "DatePlayed"),
                ("SortOrder", "Descending"),
                ("Fields", EmbyFields.list),
                ("IncludeItemTypes", "Movie,Episode"),
                ("Filters", "IsPlayed"),
                ("MediaTypes", "Video"),
                ("IsPlayed", "true")
            ])
            return HomeLayoutPreferences.collapseRecentlyWatched(items)
        } ?? []
    }

    func featuredItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors {
            switch FeaturedHeroContent.current {
            case .random:
                let items = try await self.userItems([
                    ("Limit", "24"),
                    ("Recursive", "true"),
                    ("Fields", EmbyFields.list),
                    ("IncludeItemTypes", "Movie,Series"),
                    ("SortBy", "Random")
                ])
                return HomeLayoutPreferences.featured(
                    latestMovies: items.filter { $0.kind == .movie },
                    latestShows: items.filter { $0.kind == .series }
                )
            case .favorites:
                let items = await self.browseCatalog(kind: .favorites, libraries: [], query: .default, onPage: nil)
                return HomeLayoutPreferences.featured(
                    latestMovies: items.filter { $0.kind == .movie },
                    latestShows: items.filter { $0.kind == .series }
                )
            case .recentlyAdded:
                async let movies = self.latestMedia(include: [.movie], parentID: nil, fields: EmbyFields.list, limit: 16)
                async let shows = self.latestMedia(include: [.series], parentID: nil, fields: EmbyFields.list, limit: 16)
                return HomeLayoutPreferences.featured(latestMovies: try await movies, latestShows: try await shows)
            case .continueWatching, .nextUp, .recommendations, .recentlyWatched:
                return []
            }
        } ?? []
    }

    func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        await ignoringErrors {
            let catalog = try await self.libraries()
            let ordered = HomeLayoutPreferences.orderedHomeLibraries(catalog)
            async let movies = self.recentlyAdded(.movie)
            async let shows = self.recentlyAdded(.series)
            let others = await self.latestSections(for: ordered.filter { $0.libraryKind != .movies && $0.libraryKind != .shows })
            return (catalog, [await movies, await shows].compactMap { $0 } + others)
        } ?? ([], [])
    }

    /// One row per kind across every library, newest first. `Items/Latest` brings a show back to the front
    /// when it gets new episodes; Emby mixes movies into a `Series` answer, so each row keeps only its own kind.
    private func recentlyAdded(_ kind: BaseItemKind) async -> HomeSection? {
        let wanted: MediaKind = kind == .movie ? .movie : .series
        let latest = (try? await latestMedia(include: [kind], parentID: nil, fields: EmbyFields.home, limit: 36)) ?? []
        var items = Array(latest.filter { $0.kind == wanted }.prefix(24))
        if items.isEmpty, kind == .series {
            items = (try? await recentlyAddedShows(parentID: nil))?.items ?? []
        }
        guard !items.isEmpty else { return nil }
        return kind == .movie
            ? HomeSection(id: "library-movies", title: "Recently Added Movies", style: .portrait, items: items)
            : HomeSection(id: "library-shows", title: "Recently Added Shows", style: .portrait, items: items)
    }

    func collectionsSectionIgnoringErrors() async -> HomeSection? {
        let items = await boxSets(limit: 24)
        guard !items.isEmpty else { return nil }
        return HomeSection(id: "collections", title: "Browse by Collection", style: .labeledPortrait, items: items)
    }

    func genresSectionIgnoringErrors() async -> HomeSection? {
        await ignoringErrors {
            let genres = HomeLayoutPreferences.collapsedGenres(
                try await self.dtos(
                    "/Genres",
                    query: [
                        ("UserId", self.userID),
                        ("Limit", "48"),
                        ("Recursive", "true"),
                        ("IncludeItemTypes", "Movie,Series"),
                        ("SortBy", "SortName"),
                        ("Fields", EmbyFields.list),
                        ("EnableImageTypes", EmbyFields.imageTypes)
                    ]
                ).compactMap(ItemMapper.mediaItem(from:))
            ).prefix(24).map { $0 }
            guard !genres.isEmpty else { return nil }
            let covers = try await self.userItems([
                ("Limit", "200"),
                ("Recursive", "true"),
                ("Fields", EmbyFields.list),
                ("IncludeItemTypes", "Movie,Series"),
                ("SortBy", "Random")
            ])
            return HomeSection(
                id: "genres",
                title: "Browse by Genre",
                style: .labeledPortrait,
                items: HomeLayoutPreferences.applyGenreCovers(genres, covers: covers)
            )
        } ?? nil
    }

    func movieRecommendationsIgnoringErrors() async -> [HomeSection] {
        await ignoringErrors {
            let rows = try await self.api.decode(
                [RecommendationDto].self,
                "/Movies/Recommendations",
                query: [
                    ("UserId", self.userID),
                    ("CategoryLimit", "5"),
                    ("ItemLimit", "16"),
                    ("Fields", EmbyFields.home)
                ]
            )
            return rows.enumerated().compactMap { index, row in
                let items = (row.items ?? []).compactMap(ItemMapper.mediaItem(from:))
                guard !items.isEmpty else { return nil }
                return HomeSection(
                    id: "recommend-\(row.categoryID ?? "\(index)")",
                    title: ItemMapper.recommendationTitle(from: row),
                    style: .portrait,
                    items: items
                )
            }
        } ?? []
    }

    func upcomingEpisodesIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors {
            try await self.dtos(
                "/Shows/Upcoming",
                query: [
                    ("UserId", self.userID),
                    ("Limit", "20"),
                    ("Fields", EmbyFields.list),
                    ("EnableImages", "true"),
                    ("EnableImageTypes", EmbyFields.imageTypes),
                    ("EnableUserData", "true")
                ]
            ).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .nextUp) }
        } ?? []
    }

    private func latestSections(for libraries: [MediaLibrary]) async -> [HomeSection] {
        await withTaskGroup(of: (Int, HomeSection?).self) { group in
            for (index, library) in libraries.enumerated() {
                group.addTask {
                    if library.libraryKind == .shows {
                        return (index, try? await self.recentlyAddedShows(parentID: library.id))
                    }
                    let items = (try? await self.latestMedia(
                        include: self.includeTypes(for: library),
                        parentID: library.id,
                        fields: EmbyFields.home,
                        limit: 12
                    )) ?? []
                    guard !items.isEmpty else { return (index, nil) }
                    return (index, HomeSection(
                        id: "library-\(library.id)",
                        title: library.libraryKind.recentlyAddedTitle(libraryName: library.name),
                        style: .portrait,
                        items: items
                    ))
                }
            }
            var slots = [HomeSection?](repeating: nil, count: libraries.count)
            for await (index, section) in group {
                slots[index] = section
            }
            return slots.compactMap { $0 }
        }
    }

    private func recentlyAddedShows(parentID: String?) async throws -> HomeSection? {
        let items = try await userItems([
            ("Limit", "12"),
            ("Recursive", "true"),
            ("SortBy", "DateCreated"),
            ("SortOrder", "Descending"),
            ("ParentId", parentID),
            ("Fields", EmbyFields.home),
            ("IncludeItemTypes", "Series")
        ])
        guard !items.isEmpty else { return nil }
        return HomeSection(id: "library-shows", title: "Recently Added Shows", style: .portrait, items: items)
    }

    private func latestMedia(include: [BaseItemKind], parentID: String?, fields: String, limit: Int) async throws -> [MediaItem] {
        try await api.decode(
            [BaseItemDto].self,
            "/Users/\(userID)/Items/Latest",
            query: [
                ("ParentId", parentID),
                ("Fields", fields),
                ("IncludeItemTypes", Self.joined(include)),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.imageTypes),
                ("EnableUserData", "true"),
                ("Limit", String(limit)),
                ("GroupItems", "true")
            ]
        ).compactMap(ItemMapper.mediaItem(from:))
    }

    // MARK: Libraries and catalog

    func libraries() async throws -> [MediaLibrary] {
        let result = try await api.decode(BaseItemDtoQueryResult.self, "/Users/\(userID)/Views")
        return (result.items ?? []).compactMap(ItemMapper.library(from:))
    }

    func tmdbCatalog() async -> JellyfinTmdbCatalog {
        async let movies = tmdbIDs(include: .movie)
        async let shows = tmdbIDs(include: .series)
        return JellyfinTmdbCatalog(movieIDs: await movies, seriesIDs: await shows)
    }

    private func tmdbIDs(include: BaseItemKind) async -> Set<Int> {
        var ids = Set<Int>()
        var start = 0
        let pageSize = 250
        while start < 5_000 {
            guard let result = try? await api.decode(
                BaseItemDtoQueryResult.self,
                "/Users/\(userID)/Items",
                query: [
                    ("StartIndex", String(start)),
                    ("Limit", String(pageSize)),
                    ("Recursive", "true"),
                    ("Fields", "ProviderIds"),
                    ("IncludeItemTypes", include.rawValue),
                    ("EnableUserData", "false"),
                    ("EnableImages", "false")
                ]
            ) else { break }
            let items = result.items ?? []
            for item in items {
                if let tmdbID = JellyfinTmdbCatalog.tmdbID(from: item.providerIDs) {
                    ids.insert(tmdbID)
                }
            }
            start += items.count
            if items.isEmpty || start >= (result.totalRecordCount ?? 0) { break }
        }
        return ids
    }

    func previewItems(in library: MediaLibrary, limit: Int) async -> [MediaItem] {
        let include = browseIncludeTypes(for: library)
        if let latest = try? await latestMedia(include: include, parentID: library.id, fields: EmbyFields.home, limit: limit),
           !latest.isEmpty {
            return latest
        }
        let items = (try? await userItems([
            ("Limit", String(limit)),
            ("Recursive", "true"),
            ("SortBy", "DateCreated"),
            ("SortOrder", "Descending"),
            ("ParentId", library.id),
            ("Fields", EmbyFields.home),
            ("IncludeItemTypes", Self.joined(include))
        ])) ?? []
        return Array(items.prefix(limit))
    }

    func items(in library: MediaLibrary, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(parentID: library.id, include: browseIncludeTypes(for: library), query: query, onPage: onPage)
    }

    func items(inLibraries libraries: [MediaLibrary], query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async -> [MediaItem] {
        if libraries.count == 1 {
            return (try? await items(in: libraries[0], query: query, onPage: onPage)) ?? []
        }
        return await withTaskGroup(of: [MediaItem].self) { group in
            for library in libraries {
                group.addTask { (try? await self.items(in: library, query: query, onPage: nil)) ?? [] }
            }
            var merged: [MediaItem] = []
            var seen = Set<String>()
            for await batch in group {
                for item in batch where seen.insert(item.id).inserted {
                    merged.append(item)
                }
            }
            let sorted = query.sorted(merged)
            await onPage?(CatalogPageUpdate(items: sorted, totalCount: sorted.count))
            return sorted
        }
    }

    func browseCatalog(
        kind: LibraryKind,
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async -> [MediaItem] {
        if kind == .collections {
            let matches = HomeLayoutPreferences.libraries(libraries, matching: .collections)
            if !matches.isEmpty {
                let scoped = await items(inLibraries: matches, query: query, onPage: onPage)
                if !scoped.isEmpty { return scoped }
            }
            return (try? await collectionItems(query: query, onPage: onPage)) ?? []
        }
        if kind == .favorites {
            return (try? await catalogItems(
                parentID: nil,
                include: [.movie, .series],
                query: query.applyingFavoriteFilter(),
                onPage: onPage
            )) ?? []
        }
        if kind == .watchlist {
            let items = await watchlistItems()
            await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
            return items
        }
        let matches = HomeLayoutPreferences.libraries(libraries, matching: kind)
        return await items(inLibraries: matches, query: query, onPage: onPage)
    }

    func catalogCount(kind: LibraryKind, libraries: [MediaLibrary]) async -> Int {
        if kind == .collections {
            let matches = HomeLayoutPreferences.libraries(libraries, matching: .collections)
            if !matches.isEmpty {
                let scoped = await countItems(in: matches)
                if scoped > 0 { return scoped }
            }
            return await countItems(include: [.boxSet], parentID: nil)
        }
        if kind == .favorites {
            return await browseCatalog(kind: .favorites, libraries: libraries, query: .default, onPage: nil).count
        }
        if kind == .watchlist { return await watchlistItems().count }
        return await countItems(in: HomeLayoutPreferences.libraries(libraries, matching: kind))
    }

    func serverCatalogCounts() async -> ServerCatalogCounts {
        if let counts = try? await api.decode(ItemCounts.self, "/Items/Counts", query: [("UserId", userID)]) {
            return ServerCatalogCounts(
                movies: counts.movieCount ?? 0,
                shows: counts.seriesCount ?? 0,
                episodes: counts.episodeCount ?? 0
            )
        }
        async let movies = countItems(include: [.movie], parentID: nil)
        async let shows = countItems(include: [.series], parentID: nil)
        async let episodes = countItems(include: [.episode], parentID: nil)
        return await ServerCatalogCounts(movies: movies, shows: shows, episodes: episodes)
    }

    func roomCounts(for library: MediaLibrary) async -> LibraryRoomCounts {
        switch library.libraryKind {
        case .movies:
            return LibraryRoomCounts(movies: await countItems(include: [.movie], parentID: library.id), shows: 0, episodes: 0)
        case .shows, .youTube:
            async let shows = countItems(include: [.series], parentID: library.id)
            async let episodes = countItems(include: [.episode], parentID: library.id)
            return await LibraryRoomCounts(movies: 0, shows: shows, episodes: episodes)
        // Under a box-set view Emby ignores IncludeItemTypes and counts the box sets themselves.
        case .liveTV, .collections:
            return LibraryRoomCounts(movies: 0, shows: 0, episodes: 0)
        default:
            async let movies = countItems(include: [.movie], parentID: library.id)
            async let shows = countItems(include: [.series], parentID: library.id)
            async let episodes = countItems(include: [.episode], parentID: library.id)
            return await LibraryRoomCounts(movies: movies, shows: shows, episodes: episodes)
        }
    }

    private func countItems(in libraries: [MediaLibrary]) async -> Int {
        await withTaskGroup(of: Int.self) { group in
            for library in libraries {
                group.addTask {
                    await self.countItems(include: self.browseIncludeTypes(for: library), parentID: library.id)
                }
            }
            var total = 0
            for await count in group {
                total += count
            }
            return total
        }
    }

    private func countItems(include: [BaseItemKind], parentID: String?) async -> Int {
        let result = try? await api.decode(
            BaseItemDtoQueryResult.self,
            "/Users/\(userID)/Items",
            query: [
                ("Limit", "1"),
                ("Recursive", "true"),
                ("ParentId", parentID),
                ("IncludeItemTypes", Self.joined(include)),
                ("EnableUserData", "false"),
                ("EnableImages", "false"),
                ("EnableTotalRecordCount", "true")
            ]
        )
        return result?.totalRecordCount ?? result?.items?.count ?? 0
    }

    func catalogFilterOptions(for library: MediaLibrary) async -> CatalogFilterOptions {
        await filterOptions(parentID: library.id, include: browseIncludeTypes(for: library))
    }

    func catalogFilterOptions(for kind: LibraryKind) async -> CatalogFilterOptions {
        await filterOptions(parentID: nil, include: filterIncludeTypes(for: kind))
    }

    func mixedCatalogFilterOptions(parentID: String?) async -> CatalogFilterOptions {
        await filterOptions(parentID: parentID, include: [.movie, .series])
    }

    func collectionFilterOptions(parentID: String) async -> CatalogFilterOptions {
        await filterOptions(parentID: parentID, include: [.movie, .series, .boxSet])
    }

    /// Emby has no single filters endpoint, so each list comes from its own route. Emby cannot
    /// filter by audio or subtitle language, so no languages are offered.
    private func filterOptions(parentID: String?, include: [BaseItemKind]) async -> CatalogFilterOptions {
        let query: [(String, String?)] = [
            ("UserId", userID),
            ("ParentId", parentID),
            ("IncludeItemTypes", Self.joined(include)),
            ("Recursive", "true"),
            ("SortBy", "SortName"),
            ("EnableImages", "false"),
            ("EnableUserData", "false")
        ]
        async let genres = names("/Genres", query: query)
        async let ratings = names("/OfficialRatings", query: query)
        async let tags = names("/Tags", query: query)
        async let years = names("/Years", query: query)
        async let studios = names("/Studios", query: query)
        return CatalogFilterOptions(
            genres: CatalogFilterLists.choices(from: await genres),
            officialRatings: CatalogFilterLists.choices(from: await ratings),
            tags: CatalogFilterLists.choices(from: await tags),
            years: CatalogFilterLists.yearChoices(from: (await years).compactMap { Int($0) }),
            studios: CatalogFilterLists.choices(from: await studios),
            languages: []
        )
    }

    private func names(_ path: String, query: [(String, String?)]) async -> [String] {
        let result = try? await api.decode(EmbyNameList.self, path, query: query)
        return (result?.items ?? []).compactMap(\.name)
    }

    func items(genreID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(
            parentID: nil,
            include: [.movie, .series],
            query: query,
            extra: [("GenreIds", genreID)],
            onPage: onPage
        )
    }

    func items(parentID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(parentID: parentID, include: [.movie, .series, .boxSet, .video], query: query, onPage: onPage)
    }

    func items(personID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(
            parentID: nil,
            include: [.movie, .series],
            query: query,
            extra: [("PersonIds", personID)],
            onPage: onPage
        )
    }

    func items(studioID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(
            parentID: nil,
            include: [.movie, .series],
            query: query,
            extra: [("StudioIds", studioID)],
            onPage: onPage
        )
    }

    func collectionItems(query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await catalogItems(parentID: nil, include: [.boxSet], query: query, onPage: onPage)
    }

    func boxSets() async -> [MediaItem] {
        await boxSets(limit: 80)
    }

    private func boxSets(limit: Int) async -> [MediaItem] {
        (try? await userItems([
            ("Limit", String(limit)),
            ("Recursive", "true"),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", "BoxSet"),
            ("SortBy", "SortName")
        ])) ?? []
    }

    // MARK: Titles

    func item(id: String) async throws -> MediaItem {
        guard let item = ItemMapper.mediaItem(from: try await itemDTO(id: id)) else {
            throw ZelefinError.missingItemID
        }
        return item
    }

    func itemDTO(id: String) async throws -> BaseItemDto {
        try await api.decode(BaseItemDto.self, "/Users/\(userID)/Items/\(id)")
    }

    func titleMoreInfo(for item: MediaItem) async -> TitleMoreInfo {
        if let dto = try? await itemDTO(id: item.id) {
            return TitleMoreInfoMapper.info(from: dto, item: item)
        }
        return TitleMoreInfoMapper.info(from: item)
    }

    func trailers(for item: MediaItem) async -> [TitleTrailer] {
        let locals = ((try? await dtoArray("/Users/\(userID)/Items/\(item.id)/LocalTrailers")) ?? [])
            .compactMap(ItemMapper.mediaItem(from:))
            .map(TitleTrailer.jellyfin)
        if !locals.isEmpty { return locals }
        guard let dto = try? await itemDTO(id: item.id) else { return [] }
        return JellyfinTrailers.remotes(from: dto.remoteTrailers)
    }

    func similarItems(for item: MediaItem) async -> [MediaItem] {
        let items = (try? await dtos(
            "/Items/\(item.id)/Similar",
            query: [("UserId", userID), ("Limit", "16"), ("Fields", EmbyFields.list)]
        )) ?? []
        return items
            .compactMap(ItemMapper.mediaItem(from:))
            .filter { $0.id != item.id && ($0.kind == .movie || $0.kind == .series) }
    }

    /// Emby has no "collections containing this item" route, so box sets are checked a couple at a time.
    /// `ListItemIds` asks Emby for the box sets holding the title directly, across every collection.
    func collections(containing itemID: String) async -> [ItemCollectionMembership] {
        let boxSets = (try? await userItems([
            ("Recursive", "true"),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", "BoxSet"),
            ("ListItemIds", itemID),
            ("SortBy", "SortName")
        ])) ?? []
        var found: [ItemCollectionMembership] = []
        await withTaskGroup(of: ItemCollectionMembership?.self) { group in
            for boxSet in boxSets {
                group.addTask {
                    let members = (try? await self.catalogItems(
                        parentID: boxSet.id,
                        include: [.movie, .series, .video],
                        recursive: false,
                        query: .default,
                        onPage: nil
                    )) ?? []
                    return ItemCollectionMembership(collection: boxSet, items: members)
                }
            }
            for await membership in group {
                if let membership { found.append(membership) }
            }
        }
        return found.sorted {
            $0.collection.name.localizedCaseInsensitiveCompare($1.collection.name) == .orderedAscending
        }
    }

    func credits(for item: MediaItem) async -> [CreditPerson] {
        guard let dto = try? await itemDTO(id: item.id) else { return [] }
        return ItemMapper.credits(from: dto.people)
    }

    func specialFeatures(for itemID: String) async -> [TitleExtra] {
        ((try? await dtoArray("/Users/\(userID)/Items/\(itemID)/SpecialFeatures")) ?? []).compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return TitleExtra(item: item, caption: ItemMapper.extraCaption(from: dto))
        }
    }

    func themeVideos(for itemID: String) async -> [TitleExtra] {
        ((await allThemeMedia(itemID: itemID))?.themeVideosResult?.items ?? []).compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return TitleExtra(item: item, caption: ItemMapper.themeVideoCaption)
        }
    }

    func themeMedia(for itemID: String) async -> ThemeMedia {
        let result = await allThemeMedia(itemID: itemID)
        let song = result?.themeSongsResult?.items?.first?.id
        let videoURL = await themeVideoURL(result?.themeVideosResult?.items?.first)
        return ThemeMedia(songURL: song.flatMap(themeSongURL), videoURL: videoURL)
    }

    private func allThemeMedia(itemID: String) async -> AllThemeMediaResult? {
        try? await api.decode(
            AllThemeMediaResult.self,
            "/Items/\(itemID)/ThemeMedia",
            query: [("UserId", userID), ("InheritFromParent", "true"), ("Fields", "MediaSources,Container")]
        )
    }

    private func themeSongURL(id: String) -> URL? {
        api.mediaURL(
            "/Audio/\(id)/universal",
            query: [
                ("UserId", userID),
                ("DeviceId", api.deviceID),
                ("MaxStreamingBitrate", "320000"),
                ("Container", "mp3,aac,m4a,m4b,flac,alac,wav"),
                ("TranscodingContainer", "m4a"),
                ("TranscodingProtocol", "http"),
                ("AudioCodec", "aac")
            ]
        )
    }

    private func themeVideoURL(_ dto: BaseItemDto?) async -> URL? {
        guard let dto, let id = dto.id else { return nil }
        let containers = (dto.container ?? "").lowercased().split(separator: ",").map(String.init)
        if let container = containers.first(where: { ["mp4", "m4v", "mov"].contains($0) }) {
            return api.mediaURL("/Videos/\(id)/stream.\(container)", query: [("Static", "true")])
        }
        guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
        return try? await playbackPlan(
            for: item,
            audioIndex: nil,
            subtitleIndex: nil,
            allowDirectPlay: false,
            maxBitrate: 8_000_000,
            startTime: 0,
            mediaSourceID: nil
        ).streamURL
    }

    func cinemaIntros(for itemID: String) async -> [MediaItem] {
        if let cached = cinemaIntroCache.withLock({ $0[itemID] }) {
            return cached
        }
        let items = ((try? await dtos("/Users/\(userID)/Items/\(itemID)/Intros")) ?? [])
            .compactMap(ItemMapper.mediaItem(from:))
            .filter { $0.id != itemID }
        cinemaIntroCache.withLock { $0[itemID] = items }
        return items
    }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        let items = try await dtos(
            "/Shows/\(seriesID)/Seasons",
            query: [
                ("UserId", userID),
                ("Fields", EmbyFields.list),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.imageTypes),
                ("EnableUserData", "true")
            ]
        )
        return MediaItem.orderedSeasons(items.compactMap(ItemMapper.mediaItem(from:)))
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        let items = try await dtos(
            "/Shows/\(seriesID)/Episodes",
            query: [
                ("UserId", userID),
                ("Fields", EmbyFields.episode),
                ("SeasonId", seasonID),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.imageTypes),
                ("EnableUserData", "true")
            ]
        )
        return MediaItem.orderedEpisodes(items.compactMap(ItemMapper.mediaItem(from:)))
    }

    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard item.kind == .episode, let seriesID = item.seriesID else { return nil }
        do {
            async let fetchedSeasons = seasons(seriesID: seriesID)
            async let fetchedEpisodes = episodes(seriesID: seriesID, seasonID: nil)
            let ordered = MediaItem.orderedShowEpisodes(try await fetchedEpisodes, seasons: try await fetchedSeasons)
            return PlaybackEpisodeAdvance.next(after: item, in: ordered)
        } catch {
            return nil
        }
    }

    func search(term: String) async throws -> [MediaItem] {
        try await userItems([
            ("Limit", "40"),
            ("Recursive", "true"),
            ("SearchTerm", term),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", "Movie,Series,Episode")
        ])
    }

    /// Emby 4.10 answers `/Search/Hints` with an empty list, so titles, people, genres, and
    /// studios are searched on their own routes.
    func searchLibrary(_ term: String) async throws -> [LibrarySearchHit] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let shared: [(String, String?)] = [
            ("UserId", userID),
            ("SearchTerm", trimmed),
            ("Recursive", "true"),
            ("EnableUserData", "false"),
            ("EnableImageTypes", "Primary")
        ]
        async let titles = dtos(
            "/Users/\(userID)/Items",
            query: shared + [("Limit", "24"), ("Fields", "ProductionYear"), ("IncludeItemTypes", "Movie,Series,Episode,BoxSet")]
        )
        async let people = dtos("/Persons", query: shared + [("Limit", "8")])
        async let genres = dtos("/Genres", query: shared + [("Limit", "6"), ("IncludeItemTypes", "Movie,Series")])
        async let studios = dtos("/Studios", query: shared + [("Limit", "4"), ("IncludeItemTypes", "Movie,Series")])
        let found = try await titles + ((try? await people) ?? []) + ((try? await genres) ?? []) + ((try? await studios) ?? [])
        var seen = Set<String>()
        return found.compactMap { dto in
            let hint = SearchHint(
                id: dto.id,
                name: dto.name,
                primaryImageTag: dto.imageTags?["Primary"],
                productionYear: dto.productionYear,
                series: dto.seriesName,
                type: dto.type
            )
            guard let hit = ItemMapper.searchHit(from: hint), seen.insert(hit.id).inserted else { return nil }
            return hit
        }
    }

    func person(id: String) async -> CreditPerson? {
        guard let dto = try? await itemDTO(id: id) else { return nil }
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return CreditPerson(
            id: dto.id ?? id,
            name: name,
            roleLabel: "Cast & Crew",
            imageTag: dto.imageTags?["Primary"],
            rank: 0,
            overview: dto.overview,
            birthYear: dto.productionYear ?? dto.premiereDate.flatMap {
                Calendar.current.dateComponents([.year], from: $0).year
            }
        )
    }

    func mediaVersions(for itemID: String) async -> [MediaVersion] {
        ItemMapper.versions(from: (try? await itemDTO(id: itemID))?.mediaSources)
    }

    // MARK: Playback

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        allowDirectPlay: Bool,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan {
        let bitrate = maxBitrate ?? PlaybackPreferences.maxStreamingBitrate
        let resume = item.kind == .liveTV ? 0 : (startTime ?? item.playbackPosition)
        let query: [(String, String?)] = [
            ("UserId", userID),
            ("StartTimeTicks", String(TickClock.intTicks(from: resume))),
            ("IsPlayback", "true"),
            ("AutoOpenLiveStream", "true"),
            ("MaxStreamingBitrate", String(bitrate)),
            ("AudioStreamIndex", audioIndex.map(String.init)),
            ("SubtitleStreamIndex", subtitleIndex.map(String.init)),
            ("MediaSourceId", mediaSourceID),
            // Emby's Direct Stream serves the original file as-is, so a Direct Play fallback must
            // turn it off too to get the server's HLS remux or transcode.
            ("EnableDirectPlay", allowDirectPlay ? nil : "false"),
            ("EnableDirectStream", allowDirectPlay ? nil : "false"),
            ("EnableTranscoding", "true")
        ]
        let body = try EmbyPlayback.deviceProfileBody(maxBitrate: bitrate)
        async let configuration = try? userConfiguration()
        let data = try await api.data("POST", "/Items/\(item.id)/PlaybackInfo", query: query, body: body)
        let response = try EmbyJSON.decode(PlaybackInfoResponse.self, from: data)
        let extras = try? EmbyJSON.decode(EmbyPlaybackExtras.self, from: data)
        if let code = response.errorCode {
            throw ZelefinError.server("Emby could not play this title (\(code.rawValue)).")
        }
        guard let source = EmbyPlayback.selectSource(response.mediaSources ?? [], requested: mediaSourceID) else {
            throw ZelefinError.emptyPlaybackSources
        }
        let sourceExtras = extras?.source(id: source.id)
        return try Self.plan(
            item: item,
            response: response,
            source: source,
            extras: sourceExtras,
            resume: resume,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex,
            preferences: JellyfinPlaybackPreferences(configuration: await configuration ?? UserConfiguration()),
            api: api,
            streams: streams
        )
    }

    static func plan(
        item: MediaItem,
        response: PlaybackInfoResponse,
        source: MediaSourceInfo,
        extras: EmbyMediaSourceExtras?,
        resume: TimeInterval,
        audioIndex: Int?,
        subtitleIndex: Int?,
        preferences: JellyfinPlaybackPreferences,
        api: EmbyAPI,
        streams: StreamURLBuilder
    ) throws -> PlaybackPlan {
        let isLive = item.kind == .liveTV || source.isInfiniteStream == true
        let url = try EmbyPlayback.streamURL(
            itemID: item.id,
            source: source,
            directStreamPath: extras?.directStreamURL,
            serverURL: api.serverURL,
            token: api.accessToken
        )
        let mediaStreams = source.mediaStreams ?? []
        let chosenAudio = audioIndex ?? source.defaultAudioStreamIndex
        let serverSubtitle: Int? = subtitleIndex == -1
            ? nil
            : PlaybackLanguage.positiveIndex(subtitleIndex)
                ?? PlaybackLanguage.positiveIndex(source.defaultSubtitleStreamIndex)
        let audioTracks = ItemMapper.tracks(from: mediaStreams, kind: .audio)
        let subtitleTracks = ItemMapper.tracks(from: mediaStreams, kind: .subtitle)
        let chosenSubtitle = PlaybackLanguage.startingSubtitleIndex(
            in: subtitleTracks,
            serverIndex: serverSubtitle,
            mode: preferences.subtitleMode,
            preferredLanguage: preferences.subtitleLanguage,
            audioLanguage: audioTracks.first(where: { $0.id == chosenAudio })?.language,
            preferSDH: PlaybackPreferences.preferSDH,
            forcedByUser: subtitleIndex != nil
        )
        let rawChapters = extras?.chapters ?? []
        let runtime = (extras?.runTimeTicks ?? source.runTimeTicks.map(Int64.init)).map { TickClock.seconds(from: $0) }
            ?? item.runtime
        return PlaybackPlan(
            item: item,
            streamURL: url,
            playSessionID: response.playSessionID,
            mediaSourceID: source.id,
            method: ItemMapper.playbackMethod(from: source),
            container: StreamContainer.pathExtension(from: source),
            videoCodec: ItemMapper.videoCodec(from: mediaStreams),
            videoRange: ItemMapper.videoRange(from: mediaStreams),
            audioFormat: ItemMapper.audioFormat(from: mediaStreams),
            startTime: isLive ? 0 : resume,
            byteSize: isLive ? nil : source.size.map(Int64.init),
            extraHTTPHeaders: source.requiredHTTPHeaders ?? [:],
            audioTracks: PlaybackLanguage.selecting(audioTracks, selectedID: chosenAudio),
            subtitleTracks: PlaybackLanguage.selecting(subtitleTracks, selectedID: chosenSubtitle),
            externalSubtitles: streams.externalSubtitles(itemID: item.id, source: source),
            chapters: isLive ? [] : EmbyPlayback.chapters(from: rawChapters),
            trickplay: nil,
            bifPreviewURL: isLive ? nil : api.mediaURL("/Videos/\(item.id)/index.bif", query: [("Width", "320")]),
            skipSegments: isLive ? [] : EmbyPlayback.skipSegments(from: rawChapters, runtime: runtime),
            versions: ItemMapper.versions(from: response.mediaSources),
            isLive: isLive,
            liveStreamID: source.liveStreamID,
            clientOwnsPlayhead: true,
            sourceVideo: ItemMapper.sourceVideoFacts(from: mediaStreams)
        )
    }

    func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        let dto = try? await itemDTO(id: itemID)
        let source = dto?.mediaSources?.first
        let streams = source?.mediaStreams ?? dto?.mediaStreams
        return (
            ItemMapper.tracks(from: streams, kind: .audio, source: source),
            ItemMapper.tracks(from: streams, kind: .subtitle, source: source)
        )
    }

    func originalFileDownloadURL(for itemID: String) throws -> URL {
        guard let url = api.mediaURL("/Items/\(itemID)/Download") else {
            throw ZelefinError.missingStreamURL
        }
        return url
    }

    func measureStreamingBitrate(size: Int, timeout: TimeInterval, transport: NetworkTransport) async -> BitrateProbeResult? {
        let work = Task { try await downloadBitrateTest(size: size, transport: transport) }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        defer { watchdog.cancel() }
        return try? await work.value
    }

    private func downloadBitrateTest(size: Int, transport: NetworkTransport) async throws -> BitrateProbeResult {
        guard let base = ServerURL.resolve(base: api.serverURL, path: "/Playback/BitrateTest") else {
            throw ZelefinError.bitrateTestFailed
        }
        var request = URLRequest(url: ServerURL.appending([("Size", String(size))], to: base))
        request.setValue(api.accessToken, forHTTPHeaderField: "X-Emby-Token")
        let timer = TransferTimer()
        let start = Date()
        let (data, response) = try await JellyfinNetworking.apiData(for: request, delegate: timer)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode), !data.isEmpty else {
            throw ZelefinError.bitrateTestFailed
        }
        let wallClock = max(Date().timeIntervalSince(start), 0.05)
        let transfer = await timer.settledSeconds()
        return BitrateProbeResult(
            bitsPerSecond: TransferTimer.bitsPerSecond(bytes: data.count, transferSeconds: transfer, wallClock: wallClock),
            bytes: data.count,
            elapsed: transfer > 0 ? transfer : wallClock,
            transport: transport,
            measuredAt: Date()
        )
    }

    // MARK: User data

    func markPlayed(itemID: String) async throws {
        try await api.send("POST", "/Users/\(userID)/PlayedItems/\(itemID)")
    }

    func markUnplayed(itemID: String) async throws {
        try await api.send("DELETE", "/Users/\(userID)/PlayedItems/\(itemID)")
    }

    func markFavorite(itemID: String, isFavorite: Bool) async throws -> Bool {
        let data = try await api.decode(
            UserItemDataDto.self,
            "/Users/\(userID)/FavoriteItems/\(itemID)",
            method: isFavorite ? "POST" : "DELETE"
        )
        return data.isFavorite ?? isFavorite
    }

    // MARK: Account

    func currentUser() async throws -> UserDto {
        try await api.decode(UserDto.self, "/Users/\(userID)")
    }

    func userConfiguration() async throws -> UserConfiguration {
        try await currentUser().configuration ?? UserConfiguration()
    }

    /// Writes back Emby's own configuration object with only the playback language keys
    /// changed, so Emby-only settings survive the round trip.
    func updatePlaybackPreferences(_ preferences: JellyfinPlaybackPreferences) async throws {
        let data = try await api.data("GET", "/Users/\(userID)")
        guard let user = EmbyJSON.object(from: data),
              var configuration = user["Configuration"] as? [String: Any] else {
            throw ZelefinError.server("Emby did not return this user's settings.")
        }
        let applied = preferences.applying(to: UserConfiguration())
        configuration["AudioLanguagePreference"] = applied.audioLanguagePreference ?? ""
        configuration["PlayDefaultAudioTrack"] = applied.isPlayDefaultAudioTrack ?? false
        configuration["SubtitleLanguagePreference"] = applied.subtitleLanguagePreference ?? ""
        configuration["SubtitleMode"] = (applied.subtitleMode ?? .default).rawValue
        try await api.send("POST", "/Users/\(userID)/Configuration", json: configuration)
    }

    // MARK: Shared helpers

    func userItems(_ query: [(String, String?)]) async throws -> [MediaItem] {
        try await dtos(
            "/Users/\(userID)/Items",
            query: query + [("EnableUserData", "true"), ("EnableImageTypes", EmbyFields.imageTypes)]
        ).compactMap(ItemMapper.mediaItem(from:))
    }

    func dtos(_ path: String, query: [(String, String?)] = []) async throws -> [BaseItemDto] {
        try await api.decode(BaseItemDtoQueryResult.self, path, query: query).items ?? []
    }

    func dtoArray(_ path: String) async throws -> [BaseItemDto] {
        try await api.decode([BaseItemDto].self, path)
    }

    func ignoringErrors<T: Sendable>(
        _ work: @Sendable () async throws -> T,
        caller: String = #function
    ) async -> T? {
        do {
            return try await work()
        } catch {
            #if DEBUG
            print("[Emby] \(caller) failed: \(error)")
            #endif
            return nil
        }
    }

    private func catalogItems(
        parentID: String?,
        include: [BaseItemKind],
        recursive: Bool = true,
        query: CatalogBrowseQuery,
        extra: [(String, String?)] = [],
        onPage: CatalogPageHandler?
    ) async throws -> [MediaItem] {
        let base: [(String, String?)] = [
            ("Recursive", recursive ? "true" : "false"),
            ("ParentId", parentID),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", Self.joined(include)),
            ("EnableUserData", "true"),
            ("EnableImageTypes", EmbyFields.imageTypes),
            ("EnableTotalRecordCount", "true")
        ] + extra
        let passes = query.resolutionPasses
        if passes.count == 1 {
            let streamPages = query.sort != .random
            let items = try await pagedItems(base: base, query: query, pass: passes[0], onPage: streamPages ? onPage : nil)
            if query.sort == .random {
                let shuffled = items.shuffled()
                await onPage?(CatalogPageUpdate(items: shuffled, totalCount: shuffled.count))
                return shuffled
            }
            return items
        }
        var merged: [MediaItem] = []
        var seen = Set<String>()
        for pass in passes {
            for item in try await pagedItems(base: base, query: query, pass: pass, onPage: nil)
            where seen.insert(item.id).inserted {
                merged.append(item)
            }
        }
        let sorted = query.sorted(merged)
        await onPage?(CatalogPageUpdate(items: sorted, totalCount: sorted.count))
        return sorted
    }

    private func pagedItems(
        base: [(String, String?)],
        query: CatalogBrowseQuery,
        pass: (isHd: Bool?, is4K: Bool?),
        onPage: CatalogPageHandler?
    ) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var start = 0
        var isFirst = true
        var totalCount: Int?
        let filters = EmbyCatalogQuery.items(for: query, isHd: pass.isHd, is4K: pass.is4K)
        while true {
            let pageSize = (isFirst && onPage != nil) ? CatalogPaging.firstPaintSize : CatalogPaging.pageSize
            isFirst = false
            let result = try await api.decode(
                BaseItemDtoQueryResult.self,
                "/Users/\(userID)/Items",
                query: base + filters + [("StartIndex", String(start)), ("Limit", String(pageSize))]
            )
            let raw = result.items ?? []
            if let total = result.totalRecordCount {
                totalCount = total
            }
            items.append(contentsOf: raw.compactMap(ItemMapper.mediaItem(from:)))
            await onPage?(CatalogPageUpdate(items: items, totalCount: totalCount))
            guard let next = CatalogPaging.nextStartIndex(
                fetchedCount: raw.count,
                currentStart: start,
                totalCount: result.totalRecordCount,
                pageSize: pageSize
            ) else { break }
            start = next
        }
        return items
    }

    private func browseIncludeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie, .boxSet]
        case .shows, .youTube: [.series]
        case .collections: [.boxSet]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        case .homeVideos: [.video, .movie]
        default: includeTypes(for: library)
        }
    }

    private func filterIncludeTypes(for kind: LibraryKind) -> [BaseItemKind] {
        switch kind {
        case .movies: [.movie]
        case .shows, .youTube: [.series]
        case .collections: [.boxSet]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        case .homeVideos: [.video, .movie]
        default: [.movie, .series]
        }
    }

    private func includeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie]
        case .shows, .youTube: [.series]
        case .homeVideos: [.video, .movie]
        case .collections: [.boxSet]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        default: [.movie, .series, .video]
        }
    }

    private static func joined(_ kinds: [BaseItemKind]) -> String {
        kinds.map(\.rawValue).joined(separator: ",")
    }
}

extension EmbyLibraryClient: LibraryServing {}

/// Emby only returns the fields a request names; Jellyfin returns dates, ratings, and years by default.
enum EmbyFields {
    static let imageTypes = "Primary,Thumb,Backdrop,Logo,Banner"
    private static let basics = "PrimaryImageAspectRatio,MediaStreams,ProviderIds,Width,Height,ProductionYear,PremiereDate,OfficialRating,CommunityRating,CriticRating,DateCreated"
    static let home = basics
    static let list = "Overview,Genres," + basics
    static let episode = "Overview," + basics
}

/// `CatalogBrowseQuery` as `/Users/{id}/Items` parameters. Emby joins genres, ratings, tags,
/// and studios with `|`, and has no audio or subtitle language filter.
enum EmbyCatalogQuery {
    static func items(for query: CatalogBrowseQuery, isHd: Bool?, is4K: Bool?) -> [(String, String?)] {
        var items: [(String, String?)] = []
        let filters = query.itemFilters
        if !filters.isEmpty { items.append(("Filters", filters.map(\.rawValue).joined(separator: ","))) }
        let features: [(CatalogFeatureFilter, String)] = [
            (.subtitles, "HasSubtitles"),
            (.trailers, "HasTrailer"),
            (.extras, "HasSpecialFeature"),
            (.themeSongs, "HasThemeSong"),
            (.themeVideos, "HasThemeVideo")
        ]
        for (feature, name) in features where query.features.contains(feature) {
            items.append((name, "true"))
        }
        if let isHd { items.append(("IsHD", isHd ? "true" : "false")) }
        if let is4K { items.append(("Is4K", is4K ? "true" : "false")) }
        if let is3D = query.is3D { items.append(("Is3D", is3D ? "true" : "false")) }
        let discs = query.videoTypes
        if !discs.isEmpty { items.append(("VideoTypes", discs.map(\.rawValue).joined(separator: ","))) }
        if !query.genres.isEmpty { items.append(("Genres", query.genres.sorted().joined(separator: "|"))) }
        if !query.officialRatings.isEmpty {
            items.append(("OfficialRatings", query.officialRatings.sorted().joined(separator: "|")))
        }
        if !query.tags.isEmpty { items.append(("Tags", query.tags.sorted().joined(separator: "|"))) }
        if !query.years.isEmpty { items.append(("Years", query.years.sorted().map(String.init).joined(separator: ","))) }
        if !query.studios.isEmpty { items.append(("Studios", query.studios.sorted().joined(separator: "|"))) }
        items.append(("SortBy", query.sort.itemSortBy.rawValue))
        if query.sort.allowsDirection {
            items.append(("SortOrder", query.sortAscending ? "Ascending" : "Descending"))
        }
        return items
    }
}

private struct EmbyNameList: Decodable {
    struct Entry: Decodable {
        var name: String?

        enum CodingKeys: String, CodingKey {
            case name = "Name"
        }
    }

    var items: [Entry]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
