import Foundation
import Get
import JellyfinAPI
import os

class JellyfinLibraryClient: @unchecked Sendable {
    let client: JellyfinClient
    let userID: String
    let artwork: ArtworkURLBuilder
    private let streams: StreamURLBuilder
    private let serverCapabilities: OSAllocatedUnfairLock<JellyfinServerCapabilities>
    /// `nil` until version is known or the first collections lookup probes `/Items/{id}/Collections`.
    private let hasItemCollectionsEndpoint: OSAllocatedUnfairLock<Bool?>

    init(client: JellyfinClient, userID: String, serverVersion: String? = nil) {
        self.client = client
        self.userID = userID
        self.artwork = ArtworkURLBuilder(client: client)
        self.streams = StreamURLBuilder(client: client)
        let capabilities = JellyfinServerCapabilities(version: serverVersion)
        self.serverCapabilities = OSAllocatedUnfairLock(uncheckedState: capabilities)
        self.hasItemCollectionsEndpoint = OSAllocatedUnfairLock(uncheckedState: capabilities.itemCollectionsAvailability)
    }

    func updateServerVersion(_ raw: String?) {
        let capabilities = JellyfinServerCapabilities(version: raw)
        serverCapabilities.withLock { $0 = capabilities }
        if let known = capabilities.itemCollectionsAvailability {
            hasItemCollectionsEndpoint.withLock { $0 = known }
        }
    }

    func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL? {
        switch style {
        case .landscape, .replayLandscape:
            if item.kind == .liveTV {
                return programStillURL(for: item)
            }
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

    /// Guide stills live on Primary (and sometimes the series), not Thumb.
    func programStillURL(for item: MediaItem, channel: MediaItem? = nil) -> URL? {
        if let url = primaryURL(for: item) {
            return url
        }
        if item.thumbImageTag != nil, let url = artwork.thumb(for: item, maxWidth: 640) {
            return url
        }
        if let url = artwork.backdrop(for: item, maxWidth: 640, allowPosterFallback: false) {
            return url
        }
        if let channel {
            return primaryURL(for: channel)
        }
        return nil
    }

    func primaryURL(for item: MediaItem, maxHeight: Int = ArtworkURLBuilder.posterMaxHeight) -> URL? {
        artwork.primary(for: item, maxHeight: maxHeight)
    }

    func backdropURL(for item: MediaItem, maxWidth: Int = 1400) -> URL? {
        artwork.backdrop(for: item, maxWidth: maxWidth)
    }

    func logoURL(for item: MediaItem, maxHeight: Int = 240) -> URL? {
        artwork.logo(for: item, maxHeight: maxHeight)
    }

    func userAvatarURL(userID: String, tag: String?) -> URL? {
        artwork.userAvatar(userID: userID, tag: tag)
    }

    /// Every remote image this item can show in the app. Prefetch uses this so thumbs,
    /// backdrops, and logos warm without waiting to be scrolled into view.
    func cacheableArtworkURLs(for item: MediaItem) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        let candidates: [URL?] = [
            primaryURL(for: item),
            artworkURL(for: item, style: .landscape),
            backdropURL(for: item),
            logoURL(for: item)
        ]
        for url in candidates.compactMap({ $0 }) where seen.insert(url.absoluteString).inserted {
            urls.append(url)
        }
        return urls
    }

    func resumeItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors { try await resumeItems() } ?? []
    }

    func nextUpItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors { try await nextUpItems() } ?? []
    }

    func recentlyWatchedIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors { try await recentlyWatchedItems() } ?? []
    }

    func featuredItemsIgnoringErrors() async -> [MediaItem] {
        await ignoringErrors { try await featuredItems() } ?? []
    }

    /// Latest movies, shows, and episodes for local “new on server” alerts.
    /// Returns `nil` when every request failed, so a timeout cannot look like an empty library.
    func recentlyAddedForAlerts() async -> [MediaItem]? {
        async let movies = ignoringErrors {
            try await latestMedia(include: [.movie], parentID: nil, fields: ItemMapper.alertFields, limit: 24)
        }
        async let shows = ignoringErrors {
            try await latestMedia(include: [.series], parentID: nil, fields: ItemMapper.alertFields, limit: 24)
        }
        async let episodes = ignoringErrors {
            try await latestMedia(include: [.episode], parentID: nil, fields: ItemMapper.alertFields, limit: 24)
        }
        let movieItems = await movies
        let showItems = await shows
        let episodeItems = await episodes
        if movieItems == nil, showItems == nil, episodeItems == nil {
            return nil
        }
        var seen = Set<String>()
        return ((movieItems ?? []) + (showItems ?? []) + (episodeItems ?? [])).filter { seen.insert($0.id).inserted }
    }

    func markPlayed(itemID: String) async throws {
        _ = try await client.send(Paths.markPlayedItem(itemID: itemID, userID: userID, datePlayed: Date()))
    }

    func markUnplayed(itemID: String) async throws {
        _ = try await client.send(Paths.markUnplayedItem(itemID: itemID, userID: userID))
    }

    func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        await ignoringErrors { try await libraryHome() } ?? ([], [])
    }

    func collectionsSectionIgnoringErrors() async -> HomeSection? {
        await ignoringErrors { try await collectionsSection() } ?? nil
    }

    func genresSectionIgnoringErrors() async -> HomeSection? {
        await ignoringErrors { try await genresSection() } ?? nil
    }

    func items(genreID: String, query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await catalogItems(genreID: genreID, parentID: nil, include: [.movie, .series], query: query, onPage: onPage)
    }

    func items(parentID: String, query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await catalogItems(
            genreID: nil,
            parentID: parentID,
            include: [.movie, .series, .boxSet, .video],
            query: query,
            onPage: onPage
        )
    }

    func catalogFilterOptions(
        parentID: String?,
        include: [BaseItemKind]
    ) async -> CatalogFilterOptions {
        async let legacy = ignoringErrors {
            try await client.send(
                Paths.getQueryFiltersLegacy(
                    parameters: .init(
                        userID: userID,
                        parentID: parentID,
                        includeItemTypes: include
                    )
                )
            ).value
        }
        async let studios = ignoringErrors {
            try await client.send(
                Paths.getStudios(
                    parameters: .init(
                        parentID: parentID,
                        includeItemTypes: include,
                        userID: userID,
                        enableImages: false,
                        enableTotalRecordCount: false
                    )
                )
            ).value
        }
        async let cultures = ignoringErrors {
            try await client.send(Paths.getCultures).value
        }
        let filters = await legacy
        let studioItems = await studios?.items ?? []
        return CatalogFilterOptions(
            genres: CatalogFilterLists.choices(from: filters?.genres),
            officialRatings: CatalogFilterLists.choices(from: filters?.officialRatings),
            tags: CatalogFilterLists.choices(from: filters?.tags),
            years: CatalogFilterLists.yearChoices(from: filters?.years),
            studios: CatalogFilterLists.choices(from: studioItems.compactMap(\.name)),
            languages: CatalogFilterLists.languageChoices(from: await cultures ?? [])
        )
    }

    func mixedCatalogFilterOptions(parentID: String? = nil) async -> CatalogFilterOptions {
        await catalogFilterOptions(parentID: parentID, include: mixedCatalogFilterTypes())
    }

    func collectionFilterOptions(parentID: String) async -> CatalogFilterOptions {
        await catalogFilterOptions(parentID: parentID, include: collectionFilterTypes())
    }

    func catalogFilterOptions(for library: MediaLibrary) async -> CatalogFilterOptions {
        await catalogFilterOptions(parentID: library.id, include: browseIncludeTypes(for: library))
    }

    func catalogFilterOptions(for kind: LibraryKind) async -> CatalogFilterOptions {
        await catalogFilterOptions(parentID: nil, include: filterIncludeTypes(for: kind))
    }

    private func ignoringErrors<T: Sendable>(_ work: @Sendable () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            return nil
        }
    }

    func libraries() async throws -> [MediaLibrary] {
        let result = try await client.send(
            Paths.getUserViews(parameters: .init(userID: userID, isIncludeHidden: true))
        ).value
        return (result.items ?? []).compactMap(ItemMapper.library(from:))
    }

    /// Loads TMDB identifiers for movies and series already in this library.
    func tmdbCatalog() async -> JellyfinTmdbCatalog {
        async let movies = tmdbIDs(include: [.movie])
        async let shows = tmdbIDs(include: [.series])
        return JellyfinTmdbCatalog(
            movieIDs: (try? await movies) ?? [],
            seriesIDs: (try? await shows) ?? []
        )
    }

    func items(in library: MediaLibrary, query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await pagedMediaItems(query: query, onPage: onPage) { start, pageSize in
            .init(
                userID: userID,
                startIndex: start,
                limit: pageSize,
                isRecursive: true,
                parentID: library.id,
                fields: ItemMapper.listFields,
                includeItemTypes: browseIncludeTypes(for: library),
                sortBy: [.sortName],
                enableUserData: true,
                enableImageTypes: ItemMapper.listImageTypes,
                enableTotalRecordCount: true
            )
        }
    }

    func items(inLibraries libraries: [MediaLibrary], query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async -> [MediaItem] {
        if libraries.count == 1 {
            return (try? await items(in: libraries[0], query: query, onPage: onPage)) ?? []
        }
        return await withTaskGroup(of: [MediaItem].self) { group in
            for library in libraries {
                group.addTask { (try? await self.items(in: library, query: query)) ?? [] }
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

    func collectionItems(query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await catalogItems(genreID: nil, parentID: nil, include: [.boxSet], query: query, onPage: onPage)
    }

    /// Movies/Shows are scoped to their libraries. Collections use a Collections library when
    /// the server has one, otherwise every box set on the server.
    func browseCatalog(
        kind: LibraryKind,
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
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
                genreID: nil,
                parentID: nil,
                include: [.movie, .series],
                query: query.applyingFavoriteFilter(),
                onPage: onPage
            )) ?? []
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
            return await browseCatalog(kind: .favorites, libraries: libraries).count
        }
        let matches = HomeLayoutPreferences.libraries(libraries, matching: kind)
        return await countItems(in: matches)
    }

    private func countItems(in libraries: [MediaLibrary]) async -> Int {
        await withTaskGroup(of: Int.self) { group in
            for library in libraries {
                group.addTask { await self.countItems(in: library) }
            }
            var total = 0
            for await count in group {
                total += count
            }
            return total
        }
    }

    private func countItems(in library: MediaLibrary) async -> Int {
        await countItems(include: browseIncludeTypes(for: library), parentID: library.id)
    }

    private func countItems(include: [BaseItemKind], parentID: String?) async -> Int {
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 1,
                    isRecursive: true,
                    parentID: parentID,
                    includeItemTypes: include,
                    enableUserData: false,
                    enableTotalRecordCount: true,
                    enableImages: false
                )
            )
        ).value
        return result?.totalRecordCount ?? result?.items?.count ?? 0
    }

    func item(id: String) async throws -> MediaItem {
        try await itemDTO(id: id).item
    }

    func itemDTO(id: String) async throws -> (item: MediaItem, dto: BaseItemDto) {
        let dto = try await client.send(Paths.getItem(itemID: id, userID: userID)).value
        guard let item = ItemMapper.mediaItem(from: dto) else {
            throw ZelefinError.missingItemID
        }
        return (item, dto)
    }

    func titleMoreInfo(for item: MediaItem) async -> TitleMoreInfo {
        if let dto = try? await itemDTO(id: item.id).dto {
            return TitleMoreInfoMapper.info(from: dto, item: item)
        }
        return TitleMoreInfoMapper.info(from: item)
    }

    /// Jellyfin 12 trailers: local extras (`-trailer` / `trailers/` / `.trailer`) first,
    /// then the item's `RemoteTrailers` (usually TMDb/NFO YouTube) if none exist on disk.
    func trailers(for item: MediaItem) async -> [TitleTrailer] {
        if let dto = try? await itemDTO(id: item.id).dto {
            return await trailers(for: dto)
        }
        return []
    }

    func trailers(for dto: BaseItemDto) async -> [TitleTrailer] {
        guard let itemID = dto.id else { return [] }

        if let locals = try? await client.send(Paths.getLocalTrailers(itemID: itemID, userID: userID)).value {
            let items = locals.compactMap(ItemMapper.mediaItem(from:)).map(TitleTrailer.jellyfin)
            if !items.isEmpty {
                return items
            }
        }

        return JellyfinTrailers.remotes(from: dto.remoteTrailers)
    }

    func similarItems(for item: MediaItem) async -> [MediaItem] {
        let result = await similarResult(itemID: item.id, kind: item.kind)
        return (result?.items ?? [])
            .compactMap(ItemMapper.mediaItem(from:))
            .filter { $0.id != item.id && ($0.kind == .movie || $0.kind == .series) }
    }

    /// Jellyfin 12 tightened similar-item permissions on the typed routes.
    /// `/Movies/{id}/Similar` and `/Shows/{id}/Similar` exist on 10.11 too;
    /// generic `/Items/{id}/Similar` is the fallback.
    private func similarResult(itemID: String, kind: MediaKind) async -> BaseItemDtoQueryResult? {
        switch kind {
        case .movie:
            if let result = try? await client.send(
                Paths.getSimilarMovies(
                    itemID: itemID,
                    parameters: .init(userID: userID, limit: 16, fields: ItemMapper.listFields)
                )
            ).value {
                return result
            }
        case .series:
            if let result = try? await client.send(
                Paths.getSimilarShows(
                    itemID: itemID,
                    parameters: .init(userID: userID, limit: 16, fields: ItemMapper.listFields)
                )
            ).value {
                return result
            }
        default:
            break
        }
        return try? await client.send(
            Paths.getSimilarItems(
                itemID: itemID,
                parameters: .init(
                    userID: userID,
                    limit: 16,
                    fields: ItemMapper.listFields
                )
            )
        ).value
    }

    func collections(containing itemID: String) async -> [ItemCollectionMembership] {
        switch hasItemCollectionsEndpoint.withLock({ $0 }) {
        case true:
            return await memberships(for: await collectionsFromItemEndpoint(itemID: itemID) ?? [])
        case false:
            return await collectionsByThrottledScan(containing: itemID)
        case nil:
            if let collections = await collectionsFromItemEndpoint(itemID: itemID) {
                hasItemCollectionsEndpoint.withLock { $0 = true }
                return await memberships(for: collections)
            }
            hasItemCollectionsEndpoint.withLock { $0 = false }
            return await collectionsByThrottledScan(containing: itemID)
        }
    }

    /// Jellyfin 12+: one lookup. Returns `nil` when the server is older and lacks the endpoint.
    private func collectionsFromItemEndpoint(itemID: String) async -> [MediaItem]? {
        do {
            let result = try await client.send(
                Paths.getItemCollections(
                    itemID: itemID,
                    userID: userID,
                    fields: ItemMapper.listFields
                )
            ).value
            return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        } catch let APIError.unacceptableStatusCode(status) where (400...404).contains(status) || status == 501 {
            return nil
        } catch {
            return []
        }
    }

    /// 10.11 fallback: walk BoxSets a couple at a time instead of querying every collection at once.
    private func collectionsByThrottledScan(containing itemID: String) async -> [ItemCollectionMembership] {
        let boxSets = await listedBoxSets(limit: 24)
        guard !boxSets.isEmpty else { return [] }

        var found: [ItemCollectionMembership] = []
        var index = 0
        while index < boxSets.count {
            let end = min(index + 2, boxSets.count)
            let slice = Array(boxSets[index..<end])
            index = end
            await withTaskGroup(of: ItemCollectionMembership?.self) { group in
                for boxSet in slice {
                    group.addTask {
                        let members = await self.collectionMembers(parentID: boxSet.id)
                        guard members.contains(where: { $0.id == itemID }) else { return nil }
                        return ItemCollectionMembership(collection: boxSet, items: members)
                    }
                }
                for await membership in group {
                    if let membership { found.append(membership) }
                }
            }
        }
        found.sort {
            $0.collection.name.localizedCaseInsensitiveCompare($1.collection.name) == .orderedAscending
        }
        return found
    }

    private func listedBoxSets(limit: Int) async -> [MediaItem] {
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: limit,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        return (result?.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    private func memberships(for boxSets: [MediaItem]) async -> [ItemCollectionMembership] {
        guard !boxSets.isEmpty else { return [] }
        return await withTaskGroup(of: ItemCollectionMembership?.self) { group in
            for boxSet in boxSets {
                group.addTask {
                    let members = await self.collectionMembers(parentID: boxSet.id)
                    return ItemCollectionMembership(collection: boxSet, items: members)
                }
            }
            var found: [ItemCollectionMembership] = []
            for await membership in group {
                if let membership { found.append(membership) }
            }
            found.sort {
                $0.collection.name.localizedCaseInsensitiveCompare($1.collection.name) == .orderedAscending
            }
            return found
        }
    }

    private func collectionMembers(parentID: String) async -> [MediaItem] {
        let direct = (try? await catalogItems(
            genreID: nil,
            parentID: parentID,
            include: [.movie, .series, .video],
            recursive: false
        )) ?? []
        if !direct.isEmpty { return direct }
        return (try? await catalogItems(
            genreID: nil,
            parentID: parentID,
            include: [.movie, .series, .video],
            recursive: true
        )) ?? []
    }

    func items(personID: String, query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await pagedMediaItems(query: query, onPage: onPage) { start, limit in
            .init(
                userID: userID,
                startIndex: start,
                limit: limit,
                isRecursive: true,
                fields: ItemMapper.listFields,
                includeItemTypes: [.movie, .series],
                sortBy: [.sortName],
                enableUserData: true,
                enableImageTypes: ItemMapper.listImageTypes,
                personIDs: [personID],
                enableTotalRecordCount: true
            )
        }
    }

    func items(studioID: String, query: CatalogBrowseQuery = .default, onPage: CatalogPageHandler? = nil) async throws -> [MediaItem] {
        try await pagedMediaItems(query: query, onPage: onPage) { start, limit in
            .init(
                userID: userID,
                startIndex: start,
                limit: limit,
                isRecursive: true,
                fields: ItemMapper.listFields,
                includeItemTypes: [.movie, .series],
                sortBy: [.sortName],
                enableUserData: true,
                enableImageTypes: ItemMapper.listImageTypes,
                studioIDs: [studioID],
                enableTotalRecordCount: true
            )
        }
    }

    func credits(for item: MediaItem) async -> [CreditPerson] {
        if let dto = try? await itemDTO(id: item.id).dto {
            return await credits(for: item.id, from: dto)
        }
        return []
    }

    func credits(for itemID: String, from dto: BaseItemDto) async -> [CreditPerson] {
        let fromDTO = ItemMapper.credits(from: dto.people)
        if !fromDTO.isEmpty { return fromDTO }
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    fields: [.people],
                    enableImageTypes: [.primary],
                    ids: [itemID]
                )
            )
        ).value
        return ItemMapper.credits(from: result?.items?.first?.people)
    }

    func personImageURL(id: String, tag: String?, maxHeight: Int = 360) -> URL? {
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

    func seasons(seriesID: String) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getSeasons(
                seriesID: seriesID,
                parameters: .init(
                    userID: userID,
                    fields: ItemMapper.listFields,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true
                )
            )
        ).value
        return MediaItem.orderedSeasons((result.items ?? []).compactMap(ItemMapper.mediaItem(from:)))
    }

    func episodes(seriesID: String, seasonID: String? = nil) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getEpisodes(
                seriesID: seriesID,
                parameters: .init(
                    userID: userID,
                    fields: ItemMapper.episodeFields,
                    seasonID: seasonID,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true
                )
            )
        ).value
        return MediaItem.orderedEpisodes((result.items ?? []).compactMap(ItemMapper.mediaItem(from:)))
    }

    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard item.kind == .episode, let seriesID = item.seriesID else { return nil }
        do {
            async let fetchedSeasons = seasons(seriesID: seriesID)
            async let fetchedEpisodes = episodes(seriesID: seriesID)
            let ordered = MediaItem.orderedShowEpisodes(try await fetchedEpisodes, seasons: try await fetchedSeasons)
            return PlaybackEpisodeAdvance.next(after: item, in: ordered)
        } catch {
            return nil
        }
    }

    func search(term: String) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 40,
                    isRecursive: true,
                    searchTerm: term,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series, .episode],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func originalFileDownloadURL(for itemID: String) throws -> URL {
        guard let url = ServerURL.resolve(
            base: client.configuration.url,
            path: "/Items/\(itemID)/Download",
            token: client.accessToken
        ) else {
            throw ZelefinError.missingStreamURL
        }
        return url
    }

    func measureStreamingBitrate(
        size: Int,
        timeout: TimeInterval,
        transport: NetworkTransport
    ) async -> BitrateProbeResult? {
        let work = Task {
            try await downloadBitrateTest(size: size, transport: transport)
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        defer { watchdog.cancel() }
        return try? await work.value
    }

    private func downloadBitrateTest(size: Int, transport: NetworkTransport) async throws -> BitrateProbeResult {
        let start = Date()
        let data = try await client.send(Paths.getBitrateTestBytes(size: size)).value
        try Task.checkCancellation()
        let elapsed = max(Date().timeIntervalSince(start), 0.05)
        let bitsPerSecond = Int((Double(data.count) * 8.0) / elapsed)
        return BitrateProbeResult(
            bitsPerSecond: max(0, bitsPerSecond),
            bytes: data.count,
            elapsed: elapsed,
            transport: transport,
            measuredAt: Date()
        )
    }

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil,
        allowDirectPlay: Bool = true,
        maxBitrate: Int? = nil,
        startTime: TimeInterval? = nil,
        mediaSourceID: String? = nil
    ) async throws -> PlaybackPlan {
        try await fetchPlaybackPlan(
            for: item,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex,
            enableDirectPlay: allowDirectPlay,
            maxBitrate: maxBitrate,
            startTime: startTime,
            mediaSourceID: mediaSourceID
        )
    }

    func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        let dto = try? await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        let streams = dto?.mediaStreams ?? dto?.mediaSources?.first?.mediaStreams
        return (
            ItemMapper.tracks(from: streams, kind: .audio),
            ItemMapper.tracks(from: streams, kind: .subtitle)
        )
    }

    private func fetchPlaybackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        enableDirectPlay: Bool,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan {
        let bitrate = maxBitrate ?? PlaybackPreferences.maxStreamingBitrate
        let resume = await resolvedResumePosition(requested: startTime, item: item)
        let preferredTracks = (audioIndex == nil || subtitleIndex == nil)
            ? await streamTracks(for: item.id)
            : (audio: [], subtitles: [])
        let resolvedAudio = audioIndex ?? PlaybackLanguage.audioIndex(in: preferredTracks.audio)
        let resolvedSubtitle = subtitleIndex ?? PlaybackLanguage.subtitleIndex(in: preferredTracks.subtitles)
        let profile = AVDeviceProfileFactory.make(
            preferFMP4InHLS: PlaybackPreferences.effectivePreferFMP4InHLS,
            maxBitrate: bitrate
        )
        let body = PlaybackInfoDto(
            audioStreamIndex: resolvedAudio,
            deviceProfile: profile,
            enableDirectPlay: enableDirectPlay,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: bitrate,
            mediaSourceID: mediaSourceID,
            startTimeTicks: TickClock.intTicks(from: resume),
            subtitleStreamIndex: resolvedSubtitle,
            userID: userID
        )

        let query: Paths.GetPostedPlaybackInfoParameters? = serverCapabilities.withLock({ $0.prefersPlaybackInfoBody })
            ? nil
            : .init(
                userID: userID,
                maxStreamingBitrate: bitrate,
                startTimeTicks: TickClock.intTicks(from: resume),
                audioStreamIndex: resolvedAudio,
                subtitleStreamIndex: resolvedSubtitle,
                mediaSourceID: mediaSourceID,
                isAutoOpenLiveStream: true,
                enableDirectPlay: enableDirectPlay,
                enableDirectStream: true,
                enableTranscoding: true
            )
        async let playback = client.send(
            Paths.getPostedPlaybackInfo(
                itemID: item.id,
                parameters: query,
                body
            )
        )
        async let detail = client.send(Paths.getItem(itemID: item.id, userID: userID))
        let response = try await playback.value
        let dto = try? await detail.value

        let sources = response.mediaSources ?? []
        let source = sources.first(where: { $0.id == mediaSourceID }) ?? sources.first
        guard let source else {
            throw ZelefinError.emptyPlaybackSources
        }

        let method = ItemMapper.playbackMethod(from: source)
        let isLive = item.kind == .liveTV || source.isInfiniteStream == true
        let url = StreamResumeURL.ensuringStartTimeTicks(
            try streams.url(itemID: item.id, source: source),
            method: method,
            startTime: isLive ? 0 : resume
        )
        let streams = source.mediaStreams ?? []

        return PlaybackPlan(
            item: item,
            streamURL: url,
            playSessionID: response.playSessionID,
            mediaSourceID: source.id,
            method: method,
            container: StreamContainer.pathExtension(from: source),
            videoCodec: ItemMapper.videoCodec(from: streams),
            videoRange: ItemMapper.videoRange(from: streams),
            audioFormat: ItemMapper.audioFormat(from: streams),
            startTime: isLive ? 0 : resume,
            byteSize: isLive ? nil : source.size.map(Int64.init),
            extraHTTPHeaders: source.requiredHTTPHeaders ?? [:],
            audioTracks: PlaybackLanguage.selecting(
                ItemMapper.tracks(from: streams, kind: .audio),
                selectedID: resolvedAudio
            ),
            subtitleTracks: PlaybackLanguage.selecting(
                ItemMapper.tracks(from: streams, kind: .subtitle),
                selectedID: resolvedSubtitle == -1 ? nil : resolvedSubtitle
            ),
            externalSubtitles: self.streams.externalSubtitles(itemID: item.id, source: source),
            chapters: isLive ? [] : (dto.map(ItemMapper.chapters(from:)) ?? []),
            trickplay: isLive ? nil : dto.flatMap { ItemMapper.trickplay(from: $0, sourceID: source.id) },
            versions: ItemMapper.versions(from: sources),
            isLive: isLive,
            liveStreamID: source.liveStreamID
        )
    }

    private func resolvedResumePosition(requested: TimeInterval?, item: MediaItem) async -> TimeInterval {
        if item.kind == .liveTV { return 0 }
        let local = requested ?? item.playbackPosition
        if local > PlaybackResumePolicy.threshold { return local }
        guard let fresh = try? await self.item(id: item.id).playbackPosition else { return local }
        return max(local, fresh)
    }

    private func resumeItems() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getResumeItems(
                parameters: .init(
                    userID: userID,
                    limit: 20,
                    fields: ItemMapper.listFields,
                    mediaTypes: [.video],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        return (result.items ?? []).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .resume) }
    }

    private func nextUpItems() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getNextUp(
                parameters: .init(
                    userID: userID,
                    limit: 20,
                    fields: ItemMapper.listFields,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true,
                    enableTotalRecordCount: false
                )
            )
        ).value
        return (result.items ?? []).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .nextUp) }
    }

    private func recentlyWatchedItems() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 40,
                    isRecursive: true,
                    sortOrder: [.descending],
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .episode],
                    filters: [.isPlayed],
                    mediaTypes: [.video],
                    sortBy: [.datePlayed],
                    isPlayed: true,
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        let items = (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        return HomeLayoutPreferences.collapseRecentlyWatched(items)
    }

    private func libraryHome() async throws -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        let catalog = try await libraries()
        let ordered = HomeLayoutPreferences.orderedHomeLibraries(catalog)
        var sections = await latestSections(for: ordered)
        if !sections.contains(where: { $0.title == "Recently Added Shows" }) {
            if let shows = try? await recentlyAddedShows(parentID: nil) {
                if let movieIndex = sections.firstIndex(where: { $0.title == "Recently Added Movies" }) {
                    sections.insert(shows, at: movieIndex + 1)
                } else {
                    sections.insert(shows, at: 0)
                }
            }
        }
        return (catalog, sections)
    }

    private func latestSections(for libraries: [MediaLibrary]) async -> [HomeSection] {
        await withTaskGroup(of: (Int, HomeSection?).self) { group in
            for (index, library) in libraries.enumerated() {
                group.addTask {
                    let section: HomeSection?
                    if library.libraryKind == .shows {
                        section = try? await self.recentlyAddedShows(parentID: library.id)
                    } else {
                        section = try? await self.latestItems(
                            include: self.includeTypes(for: library),
                            title: library.libraryKind.recentlyAddedTitle(libraryName: library.name),
                            id: "library-\(library.id)",
                            parentID: library.id
                        )
                    }
                    return (index, section)
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
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 12,
                    isRecursive: true,
                    sortOrder: [.descending],
                    parentID: parentID,
                    fields: ItemMapper.homeFields,
                    includeItemTypes: [.series],
                    sortBy: [.dateCreated],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        let items = (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        guard !items.isEmpty else { return nil }
        return HomeSection(id: "library-shows", title: "Recently Added Shows", style: .portrait, items: items)
    }

    private func collectionsSection() async throws -> HomeSection? {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 24,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        let items = (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        guard !items.isEmpty else { return nil }
        return HomeSection(id: "collections", title: "Browse by Collection", style: .labeledPortrait, items: items)
    }

    private func genresSection() async throws -> HomeSection? {
        let result = try await client.send(
            Paths.getGenres(
                parameters: .init(
                    limit: 24,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series],
                    enableImageTypes: ItemMapper.listImageTypes,
                    userID: userID,
                    sortBy: [.sortName],
                    enableImages: true
                )
            )
        ).value
        let genres = (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        guard !genres.isEmpty else { return nil }
        let covers = try await genreCoverItems()
        let assigned = HomeLayoutPreferences.applyGenreCovers(genres, covers: covers)
        return HomeSection(
            id: "genres",
            title: "Browse by Genre",
            style: .labeledPortrait,
            items: assigned
        )
    }

    private func genreCoverItems() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 200,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series],
                    sortBy: [.random],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableTotalRecordCount: false
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    private func catalogItems(
        genreID: String?,
        parentID: String?,
        include: [BaseItemKind],
        recursive: Bool = true,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        try await pagedMediaItems(query: query, onPage: onPage) { start, limit in
            .init(
                userID: userID,
                startIndex: start,
                limit: limit,
                isRecursive: recursive,
                parentID: parentID,
                fields: ItemMapper.listFields,
                includeItemTypes: include,
                sortBy: [.sortName],
                enableUserData: true,
                enableImageTypes: ItemMapper.listImageTypes,
                genreIDs: genreID.map { [$0] },
                enableTotalRecordCount: true
            )
        }
    }

    private func pagedMediaItems(
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil,
        parameters: (Int, Int) -> Paths.GetItemsParameters
    ) async throws -> [MediaItem] {
        let passes = query.resolutionPasses
        let streamPages = query.sort != .random && passes.count == 1
        if passes.count == 1 {
            let items = try await pagedMediaItemsOnce(
                query: query,
                isHd: passes[0].isHd,
                is4K: passes[0].is4K,
                onPage: streamPages ? onPage : nil,
                parameters: parameters
            )
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
            let batch = try await pagedMediaItemsOnce(
                query: query,
                isHd: pass.isHd,
                is4K: pass.is4K,
                parameters: parameters
            )
            for item in batch where seen.insert(item.id).inserted {
                merged.append(item)
            }
        }
        let sorted = query.sorted(merged)
        await onPage?(CatalogPageUpdate(items: sorted, totalCount: sorted.count))
        return sorted
    }

    private func pagedMediaItemsOnce(
        query: CatalogBrowseQuery,
        isHd: Bool?,
        is4K: Bool?,
        onPage: CatalogPageHandler? = nil,
        parameters: (Int, Int) -> Paths.GetItemsParameters
    ) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var start = 0
        var isFirst = true
        var totalCount: Int?
        while true {
            let pageSize = (isFirst && onPage != nil) ? CatalogPaging.firstPaintSize : CatalogPaging.pageSize
            isFirst = false
            let page = try await mediaPage(
                start: start,
                pageSize: pageSize,
                query: query,
                isHd: isHd,
                is4K: is4K,
                parameters: parameters
            )
            if let total = page.totalCount {
                totalCount = total
            }
            items.append(contentsOf: page.items)
            await onPage?(CatalogPageUpdate(items: items, totalCount: totalCount))
            guard let next = page.nextStart else { break }
            start = next
        }
        return items
    }

    private func mediaPage(
        start: Int,
        pageSize: Int = CatalogPaging.pageSize,
        query: CatalogBrowseQuery = .default,
        isHd: Bool? = nil,
        is4K: Bool? = nil,
        parameters: (Int, Int) -> Paths.GetItemsParameters
    ) async throws -> CatalogPage {
        var params = parameters(start, pageSize)
        query.apply(to: &params, isHd: isHd, is4K: is4K)
        var request = Paths.getItems(parameters: params)
        let extra = query.extraLanguageQuery
        if !extra.isEmpty {
            request.query = (request.query ?? []) + extra
        }
        let result = try await client.send(request).value
        let raw = result.items ?? []
        return CatalogPage(
            items: raw.compactMap(ItemMapper.mediaItem(from:)),
            nextStart: CatalogPaging.nextStartIndex(
                fetchedCount: raw.count,
                currentStart: start,
                totalCount: result.totalRecordCount,
                pageSize: pageSize
            ),
            totalCount: result.totalRecordCount
        )
    }

    private func browseIncludeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie, .boxSet]
        case .shows: [.series]
        case .collections: [.boxSet]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        case .homeVideos: [.video, .movie]
        default: includeTypes(for: library)
        }
    }

    func filterIncludeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        browseIncludeTypes(for: library)
    }

    func filterIncludeTypes(for kind: LibraryKind) -> [BaseItemKind] {
        switch kind {
        case .movies: [.movie]
        case .shows: [.series]
        case .collections: [.boxSet]
        case .favorites: [.movie, .series]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        case .homeVideos: [.video, .movie]
        default: [.movie, .series]
        }
    }

    func mixedCatalogFilterTypes() -> [BaseItemKind] { [.movie, .series] }

    func collectionFilterTypes() -> [BaseItemKind] { [.movie, .series, .boxSet] }

    private func includeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie]
        case .shows: [.series]
        case .homeVideos: [.video, .movie]
        case .collections: [.boxSet]
        case .books: [.book]
        case .photos: [.photo, .photoAlbum]
        case .liveTV: [.tvChannel]
        case .playlists: [.playlist]
        default: [.movie, .series, .video]
        }
    }

    private func latestItems(
        include: [BaseItemKind],
        title: String,
        id: String,
        parentID: String?
    ) async throws -> HomeSection? {
        let items = try await latestMedia(include: include, parentID: parentID)
        guard !items.isEmpty else { return nil }
        return HomeSection(id: id, title: title, style: .portrait, items: items)
    }

    private func featuredItems() async throws -> [MediaItem] {
        async let movies = featuredLatest(include: [.movie])
        async let shows = featuredLatest(include: [.series])
        return HomeLayoutPreferences.featured(
            latestMovies: try await movies,
            latestShows: try await shows
        )
    }

    private func featuredLatest(include: [BaseItemKind]) async throws -> [MediaItem] {
        try await latestMedia(include: include, parentID: nil, fields: ItemMapper.listFields, limit: 16)
    }

    private func latestMedia(include: [BaseItemKind]?, parentID: String?) async throws -> [MediaItem] {
        try await latestMedia(include: include, parentID: parentID, fields: ItemMapper.homeFields, limit: 12)
    }

    private func latestMedia(
        include: [BaseItemKind]?,
        parentID: String?,
        fields: [ItemFields],
        limit: Int
    ) async throws -> [MediaItem] {
        try await client.send(
            Paths.getLatestMedia(
                parameters: .init(
                    userID: userID,
                    parentID: parentID,
                    fields: fields,
                    includeItemTypes: include,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true,
                    limit: limit,
                    isGroupItems: true
                )
            )
        ).value.compactMap(ItemMapper.mediaItem(from:))
    }

    private func tmdbIDs(include: [BaseItemKind]) async throws -> Set<Int> {
        var ids = Set<Int>()
        var start = 0
        let pageSize = 250

        while start < 5_000 {
            let result = try await client.send(
                Paths.getItems(
                    parameters: .init(
                        userID: userID,
                        startIndex: start,
                        limit: pageSize,
                        isRecursive: true,
                        fields: [.providerIDs],
                        includeItemTypes: include,
                        enableUserData: false,
                        enableImages: false
                    )
                )
            ).value
            let items = result.items ?? []
            for item in items {
                if let tmdbID = JellyfinTmdbCatalog.tmdbID(from: item.providerIDs) {
                    ids.insert(tmdbID)
                }
            }
            start += items.count
            let total = result.totalRecordCount ?? 0
            if items.isEmpty || start >= total {
                break
            }
        }

        return ids
    }

    /// Sessions Jellyfin still considers active, including idle clients.
    func playbackSessions(activeWithinSeconds: Int = 960) async throws -> [PlaybackSession] {
        let request = Paths.getSessions(parameters: .init(activeWithinSeconds: activeWithinSeconds))
        let data = try await client.data(for: request).value
        let dtos = try JellyfinJSONDate.decoder.decode([SessionInfoDto].self, from: data)
        return PlaybackSession.sorted(dtos.compactMap(PlaybackSession.init(dto:)))
    }

    func sendPlaystate(
        sessionID: String,
        command: PlaystateCommand,
        seekPosition: TimeInterval? = nil
    ) async throws {
        _ = try await client.send(
            Paths.sendPlaystateCommand(
                sessionID: sessionID,
                command: command.rawValue,
                seekPositionTicks: seekPosition.map(TickClock.intTicks(from:)),
                controllingUserID: userID
            )
        )
    }

    func sendSessionCommand(sessionID: String, command: GeneralCommandType) async throws {
        _ = try await client.send(
            Paths.sendGeneralCommand(sessionID: sessionID, command: command.rawValue)
        )
    }

    func playOnSession(sessionID: String, itemIDs: [String], startPosition: TimeInterval? = nil) async throws {
        _ = try await client.send(
            Paths.play(
                sessionID: sessionID,
                parameters: .init(
                    playCommand: .playNow,
                    itemIDs: itemIDs,
                    startPositionTicks: startPosition.map(TickClock.intTicks(from:))
                )
            )
        )
    }

    func markFavorite(itemID: String, isFavorite: Bool) async throws -> Bool {
        let data = isFavorite
            ? try await client.send(Paths.markFavoriteItem(itemID: itemID, userID: userID)).value
            : try await client.send(Paths.unmarkFavoriteItem(itemID: itemID, userID: userID)).value
        return data.isFavorite ?? isFavorite
    }

    func setLikes(itemID: String, likes: Bool?) async throws -> Bool? {
        if let likes {
            let data = try await client.send(
                Paths.updateUserItemRating(itemID: itemID, userID: userID, isLikes: likes)
            ).value
            return data.isLikes
        }
        let data = try await client.send(Paths.deleteUserItemRating(itemID: itemID, userID: userID)).value
        return data.isLikes
    }

    func specialFeatures(for itemID: String) async -> [TitleExtra] {
        let dtos = (try? await client.send(Paths.getSpecialFeatures(itemID: itemID, userID: userID)).value) ?? []
        return dtos.compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return TitleExtra(item: item, caption: ItemMapper.extraCaption(from: dto))
        }
    }

    func themeVideos(for itemID: String) async -> [TitleExtra] {
        let result = try? await client.send(
            Paths.getThemeMedia(itemID: itemID, parameters: .init(userID: userID, isInheritFromParent: true))
        ).value
        return (result?.themeVideosResult?.items ?? []).compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return TitleExtra(item: item, caption: "Theme")
        }
    }

    func cinemaIntros(for itemID: String) async -> [MediaItem] {
        let result = try? await client.send(Paths.getIntros(itemID: itemID, userID: userID)).value
        return (result?.items ?? []).compactMap(ItemMapper.mediaItem(from:)).filter { $0.id != itemID }
    }

    func movieRecommendationsIgnoringErrors() async -> [HomeSection] {
        (try? await movieRecommendations()) ?? []
    }

    func movieRecommendations() async throws -> [HomeSection] {
        let rows = try await client.send(
            Paths.getMovieRecommendations(
                parameters: .init(
                    userID: userID,
                    fields: ItemMapper.homeFields,
                    categoryLimit: 5,
                    itemLimit: 16
                )
            )
        ).value
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
    }

    func upcomingEpisodesIgnoringErrors() async -> [MediaItem] {
        (try? await upcomingEpisodes()) ?? []
    }

    func upcomingEpisodes() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getUpcomingEpisodes(
                parameters: .init(
                    userID: userID,
                    limit: 20,
                    fields: ItemMapper.listFields,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true
                )
            )
        ).value
        return (result.items ?? []).compactMap { ItemMapper.mediaItem(from: $0, queueKind: .nextUp) }
    }

    func mediaVersions(for itemID: String) async -> [MediaVersion] {
        let dto = try? await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        return ItemMapper.versions(from: dto?.mediaSources)
    }

    func person(id: String) async -> CreditPerson? {
        guard let dto = try? await client.send(Paths.getItem(itemID: id, userID: userID)).value else {
            return nil
        }
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

    func searchLibrary(_ term: String) async throws -> [LibrarySearchHit] {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let result = try await client.send(
            Paths.getSearchHints(
                parameters: .init(
                    limit: 24,
                    userID: userID,
                    searchTerm: trimmed,
                    includeItemTypes: [
                        .movie, .series, .episode, .boxSet, .person, .genre, .studio,
                        .tvChannel
                    ],
                    isIncludePeople: true,
                    isIncludeMedia: true,
                    isIncludeGenres: true,
                    isIncludeStudios: true,
                    isIncludeArtists: false
                )
            )
        ).value
        var seen = Set<String>()
        return (result.searchHints ?? []).compactMap { hint in
            guard let hit = ItemMapper.searchHit(from: hint), seen.insert(hit.id).inserted else { return nil }
            return hit
        }
    }

    func boxSets() async -> [MediaItem] {
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 80,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.boxSet],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableImages: true
                )
            )
        ).value
        return (result?.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func addToCollection(collectionID: String, itemIDs: [String]) async throws {
        _ = try await client.send(Paths.addToCollection(collectionID: collectionID, ids: itemIDs))
    }

    func removeFromCollection(collectionID: String, itemIDs: [String]) async throws {
        _ = try await client.send(Paths.removeFromCollection(collectionID: collectionID, ids: itemIDs))
    }

    func createCollection(name: String, itemIDs: [String]) async throws {
        _ = try await client.send(
            Paths.createCollection(parameters: .init(name: name, ids: itemIDs))
        )
    }

    func chapterImageURL(itemID: String, index: Int, tag: String?) -> URL? {
        artwork.image(itemID: itemID, type: "Chapter/\(index)", tag: tag, maxWidth: 480, format: "jpg")
    }

    func trickplayTileURL(itemID: String, info: TrickplayInfo, time: TimeInterval) -> URL? {
        artwork.trickplayTile(
            itemID: itemID,
            width: info.width,
            index: info.tileIndex(at: time),
            mediaSourceID: info.mediaSourceID
        )
    }

    func activityLog(limit: Int = 80) async throws -> [ActivityLogItem] {
        let result = try await client.send(
            Paths.getLogEntries(parameters: .init(startIndex: 0, limit: limit))
        ).value
        return (result.items ?? []).compactMap { entry in
            let title = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let id = entry.id.map(String.init) ?? "\(title)-\(entry.date?.timeIntervalSince1970 ?? 0)"
            return ActivityLogItem(
                id: id,
                title: title,
                detail: entry.shortOverview ?? entry.overview,
                date: entry.date,
                type: entry.type
            )
        }
    }

    func serverBackups() async throws -> [ServerBackup] {
        try await client.send(Paths.listBackups).value.compactMap { dto in
            guard let path = dto.path, !path.isEmpty else { return nil }
            return ServerBackup(
                id: path,
                path: path,
                dateCreated: dto.dateCreated,
                serverVersion: dto.serverVersion
            )
        }
    }

    func createServerBackup() async throws -> ServerBackup {
        let dto = try await client.send(
            Paths.createBackup(
                BackupOptionsDto(isDatabase: true, isMetadata: true, isSubtitles: true, isTrickplay: true)
            )
        ).value
        guard let path = dto.path, !path.isEmpty else {
            throw ZelefinError.server("The server did not return a backup path.")
        }
        return ServerBackup(
            id: path,
            path: path,
            dateCreated: dto.dateCreated,
            serverVersion: dto.serverVersion
        )
    }

    func restoreServerBackup(_ backup: ServerBackup) async throws {
        _ = try await client.send(
            Paths.startRestoreBackup(BackupRestoreRequestDto(archiveFileName: backup.fileName))
        )
    }

    func scanLibraries() async throws {
        _ = try await client.send(Paths.refreshLibrary)
    }

    func refreshItemMetadata(itemID: String, replaceImages: Bool = false) async throws {
        _ = try await client.send(
            Paths.refreshItem(
                itemID: itemID,
                parameters: .init(
                    metadataRefreshMode: .fullRefresh,
                    imageRefreshMode: replaceImages ? .fullRefresh : .default,
                    isReplaceAllMetadata: false,
                    isReplaceAllImages: replaceImages,
                    isRegenerateTrickplay: false
                )
            )
        )
    }

    func deleteLibraryItem(itemID: String) async throws {
        _ = try await client.send(Paths.deleteItem(itemID: itemID))
    }

    func remoteArtwork(for itemID: String, kind: RemoteArtworkKind) async throws -> [RemoteImageChoice] {
        let type = ImageType(rawValue: kind.jellyfinTypeName) ?? .primary
        let result = try await client.send(
            Paths.getRemoteImages(
                itemID: itemID,
                parameters: .init(type: type, startIndex: 0, limit: 40, isIncludeAllLanguages: true)
            )
        ).value
        return (result.images ?? []).compactMap { info in
            guard let raw = info.url, let url = URL(string: raw) else { return nil }
            let thumb = info.thumbnailURL.flatMap(URL.init(string:))
            return RemoteImageChoice(
                id: "\(kind.rawValue)-\(raw)",
                imageURL: url,
                thumbnailURL: thumb,
                provider: info.providerName ?? "Provider",
                typeName: info.type?.rawValue ?? kind.jellyfinTypeName,
                width: info.width,
                height: info.height
            )
        }
    }

    func downloadRemoteArtwork(itemID: String, kind: RemoteArtworkKind, imageURL: URL) async throws {
        let type = ImageType(rawValue: kind.jellyfinTypeName) ?? .primary
        _ = try await client.send(
            Paths.downloadRemoteImage(itemID: itemID, type: type, imageURL: imageURL.absoluteString)
        )
    }

    func serverBranding() async throws -> ServerBranding {
        let dto = try await client.send(Paths.getBrandingOptions).value
        return ServerBranding(
            loginDisclaimer: dto.loginDisclaimer ?? "",
            customCSS: dto.customCss ?? "",
            splashscreenEnabled: dto.isSplashscreenEnabled ?? false
        )
    }

    func updateServerBranding(_ branding: ServerBranding) async throws {
        _ = try await client.send(
            Paths.updateBrandingConfiguration(
                BrandingOptionsDto(
                    customCss: branding.customCSS,
                    isSplashscreenEnabled: branding.splashscreenEnabled,
                    loginDisclaimer: branding.loginDisclaimer
                )
            )
        )
    }

    func uploadSplashscreen(_ imageData: Data) async throws {
        _ = try await client.send(Paths.uploadCustomSplashscreen(imageData.base64EncodedData()))
    }

    func deleteSplashscreen() async throws {
        _ = try await client.send(Paths.deleteCustomSplashscreen)
    }

    func displayPreferenceCustomPrefs() async throws -> [String: String] {
        let dto = try await client.send(
            Paths.getDisplayPreferences(
                displayPreferencesID: DisplayPreferencesSync.preferenceID,
                userID: userID,
                client: DeviceIdentity.clientName
            )
        ).value
        return dto.customPrefs ?? [:]
    }

    func updateDisplayPreferenceCustomPrefs(_ prefs: [String: String]) async throws {
        _ = try await client.send(
            Paths.updateDisplayPreferences(
                displayPreferencesID: DisplayPreferencesSync.preferenceID,
                userID: userID,
                client: DeviceIdentity.clientName,
                DisplayPreferencesDto(
                    client: DeviceIdentity.clientName,
                    customPrefs: prefs,
                    id: DisplayPreferencesSync.preferenceID
                )
            )
        )
    }

    func playlists() async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 80,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.playlist],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableImages: true
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func playlistEntries(playlistID: String) async throws -> [PlaylistEntry] {
        let result = try await client.send(
            Paths.getPlaylistItems(
                playlistID: playlistID,
                parameters: .init(
                    userID: userID,
                    fields: ItemMapper.listFields,
                    enableImages: true,
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes
                )
            )
        ).value
        return (result.items ?? []).compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return PlaylistEntry(
                id: dto.playlistItemID ?? item.id,
                entryID: dto.playlistItemID,
                item: item
            )
        }
    }

    func createPlaylist(name: String, itemIDs: [String]) async throws {
        _ = try await client.send(
            Paths.createPlaylist(
                CreatePlaylistDto(
                    ids: itemIDs,
                    mediaType: .video,
                    name: name,
                    userID: userID
                )
            )
        )
    }

    func addToPlaylist(playlistID: String, itemIDs: [String]) async throws {
        _ = try await client.send(
            Paths.addItemToPlaylist(playlistID: playlistID, ids: itemIDs, userID: userID)
        )
    }

    func removeFromPlaylist(playlistID: String, entryIDs: [String]) async throws {
        _ = try await client.send(
            Paths.removeItemFromPlaylist(playlistID: playlistID, entryIDs: entryIDs)
        )
    }

    func liveTVInfoEnabled() async throws -> Bool {
        let info = try await client.send(Paths.getLiveTvInfo).value
        return info.isEnabled ?? true
    }

    func liveTVChannels() async throws -> [LiveChannel] {
        let result = try await client.send(
            Paths.getLiveTvChannels(
                parameters: .init(
                    userID: userID,
                    enableImages: true,
                    enableImageTypes: ItemMapper.liveTVImageTypes,
                    fields: ItemMapper.liveTVFields,
                    enableUserData: true,
                    sortBy: [.sortName],
                    enableFavoriteSorting: true,
                    isAddCurrentProgram: true
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.liveChannel(from:))
    }

    func liveTVRecordings(isInProgress: Bool? = nil, limit: Int = 80) async throws -> [LiveTVRecording] {
        if let isInProgress {
            return try await fetchLiveTVRecordings(isInProgress: isInProgress, limit: limit)
        }
        async let active = fetchLiveTVRecordings(isInProgress: true, limit: limit)
        async let completed = fetchLiveTVRecordings(isInProgress: false, limit: limit)
        let inProgress = (try? await active) ?? []
        let finished = (try? await completed) ?? []
        if inProgress.isEmpty && finished.isEmpty {
            return try await fetchLiveTVRecordings(isInProgress: nil, limit: limit)
        }
        return LiveTVRecording.merging(inProgress: inProgress, completed: finished)
    }

    private func fetchLiveTVRecordings(isInProgress: Bool?, limit: Int) async throws -> [LiveTVRecording] {
        let result = try await client.send(
            Paths.getRecordings(
                parameters: .init(
                    userID: userID,
                    limit: limit,
                    isInProgress: isInProgress,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    fields: ItemMapper.liveTVFields,
                    enableUserData: true
                )
            )
        ).value
        return (result.items ?? []).compactMap {
            ItemMapper.recordingItem(from: $0, treatAsInProgress: isInProgress == true)
        }
    }

    func deleteLiveTVRecording(id: String) async throws {
        _ = try await client.send(Paths.deleteRecording(recordingID: id))
    }

    func liveTVPrograms(
        channelIDs: [String]? = nil,
        isAiring: Bool? = nil,
        hasAired: Bool? = nil,
        minStartDate: Date? = nil,
        maxStartDate: Date? = nil,
        filter: LiveTVProgramFilter? = nil,
        limit: Int = 80
    ) async throws -> [LiveProgram] {
        let flags = liveTVProgramFlags(filter)
        let result = try await client.send(
            Paths.getLiveTvPrograms(
                parameters: .init(
                    channelIDs: channelIDs,
                    userID: userID,
                    minStartDate: minStartDate,
                    hasAired: hasAired,
                    isAiring: isAiring,
                    maxStartDate: maxStartDate,
                    isMovie: flags.movie,
                    isSeries: flags.series,
                    isNews: flags.news,
                    isKids: flags.kids,
                    isSports: flags.sports,
                    limit: limit,
                    sortBy: [.startDate],
                    enableImages: true,
                    enableImageTypes: ItemMapper.liveTVImageTypes,
                    enableUserData: true,
                    fields: ItemMapper.liveTVFields
                )
            )
        ).value
        return (result.items ?? []).compactMap { ItemMapper.liveProgram(from: $0) }
    }

    func liveTVRecommendedPrograms(filter: LiveTVProgramFilter? = nil, isAiring: Bool = true, limit: Int = 40) async throws -> [LiveProgram] {
        let flags = liveTVProgramFlags(filter)
        let result = try await client.send(
            Paths.getRecommendedPrograms(
                parameters: .init(
                    userID: userID,
                    limit: limit,
                    isAiring: isAiring,
                    isSeries: flags.series,
                    isMovie: flags.movie,
                    isNews: flags.news,
                    isKids: flags.kids,
                    isSports: flags.sports,
                    enableImages: true,
                    enableImageTypes: ItemMapper.liveTVImageTypes,
                    fields: ItemMapper.liveTVFields,
                    enableUserData: true
                )
            )
        ).value
        return (result.items ?? []).compactMap { ItemMapper.liveProgram(from: $0) }
    }

    func liveTVProgram(id: String) async throws -> LiveProgram {
        let dto = try await client.send(Paths.getProgram(programID: id, userID: userID)).value
        guard let program = ItemMapper.liveProgram(from: dto) else {
            throw ZelefinError.server("This program is no longer in the guide.")
        }
        return program
    }

    func liveTVGuide(channelIDs: [String], from start: Date, to end: Date) async throws -> [LiveProgram] {
        guard !channelIDs.isEmpty else { return [] }
        var programs: [LiveProgram] = []
        for chunk in stride(from: 0, to: channelIDs.count, by: 24) {
            let slice = Array(channelIDs[chunk..<min(chunk + 24, channelIDs.count)])
            let body = GetProgramsDto(
                channelIDs: slice,
                enableImageTypes: ItemMapper.liveTVImageTypes,
                enableImages: true,
                enableTotalRecordCount: false,
                enableUserData: true,
                fields: ItemMapper.liveTVFields,
                maxStartDate: end,
                minStartDate: start.addingTimeInterval(-6 * 3600),
                sortBy: [.startDate],
                userID: userID
            )
            let result = try await client.send(Paths.getPrograms(body)).value
            programs.append(contentsOf: (result.items ?? []).compactMap { ItemMapper.liveProgram(from: $0) })
        }
        return programs
    }

    private func liveTVProgramFlags(_ filter: LiveTVProgramFilter?) -> (
        movie: Bool?,
        series: Bool?,
        news: Bool?,
        kids: Bool?,
        sports: Bool?
    ) {
        switch filter {
        case .movies: (true, nil, nil, nil, nil)
        case .series: (nil, true, nil, nil, nil)
        case .news: (nil, nil, true, nil, nil)
        case .kids: (nil, nil, nil, true, nil)
        case .sports: (nil, nil, nil, nil, true)
        case nil: (nil, nil, nil, nil, nil)
        }
    }

    func syncPlayGroups() async throws -> [SyncPlayGroupInfo] {
        try await client.send(Paths.syncPlayGetGroups).value.compactMap { dto in
            guard let id = dto.groupID, !id.isEmpty else { return nil }
            let name = dto.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return SyncPlayGroupInfo(
                id: id,
                name: name.isEmpty ? "SyncPlay" : name,
                participants: dto.participants ?? [],
                stateLabel: dto.state?.rawValue ?? "Idle"
            )
        }
    }

    func syncPlayCreateGroup(name: String) async throws -> SyncPlayGroupInfo {
        let dto = try await client.send(
            Paths.syncPlayCreateGroup(NewGroupRequestDto(groupName: name))
        ).value
        guard let id = dto.groupID, !id.isEmpty else {
            throw ZelefinError.server("The server did not return a SyncPlay group.")
        }
        let trimmed = dto.groupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return SyncPlayGroupInfo(
            id: id,
            name: trimmed.isEmpty ? name : trimmed,
            participants: dto.participants ?? [],
            stateLabel: dto.state?.rawValue ?? "Idle"
        )
    }

    func syncPlayJoinGroup(id: String) async throws {
        _ = try await client.send(Paths.syncPlayJoinGroup(JoinGroupRequestDto(groupID: id)))
    }

    func syncPlayLeaveGroup() async throws {
        _ = try await client.send(Paths.syncPlayLeaveGroup)
    }

    func syncPlaySetQueue(itemIDs: [String], startPosition: TimeInterval = 0) async throws {
        _ = try await client.send(
            Paths.syncPlaySetNewQueue(
                PlayRequestDto(
                    playingItemPosition: 0,
                    playingQueue: itemIDs,
                    startPositionTicks: TickClock.intTicks(from: startPosition)
                )
            )
        )
    }

    func syncPlayPause() async throws {
        _ = try await client.send(Paths.syncPlayPause)
    }

    func syncPlayUnpause() async throws {
        _ = try await client.send(Paths.syncPlayUnpause)
    }

    func syncPlaySeek(to seconds: TimeInterval) async throws {
        _ = try await client.send(
            Paths.syncPlaySeek(SeekRequestDto(positionTicks: TickClock.intTicks(from: seconds)))
        )
    }

    func syncPlayStop() async throws {
        _ = try await client.send(Paths.syncPlayStop)
    }

    func syncPlayReady(isPlaying: Bool, playlistItemID: String?, position: TimeInterval) async throws {
        _ = try await client.send(
            Paths.syncPlayReady(
                ReadyRequestDto(
                    isPlaying: isPlaying,
                    playlistItemID: playlistItemID,
                    positionTicks: TickClock.intTicks(from: position),
                    when: Date()
                )
            )
        )
    }

    func scheduledTasks() async throws -> [ScheduledTask] {
        let result = try await client.send(Paths.getTasks()).value
        return ScheduledTask.sorted(result.compactMap(ScheduledTask.init(dto:)))
    }

    func startScheduledTask(id: String) async throws {
        _ = try await client.send(Paths.startTask(taskID: id))
    }

    func stopScheduledTask(id: String) async throws {
        _ = try await client.send(Paths.stopTask(taskID: id))
    }
}

extension JellyfinLibraryClient: LibraryServing {}

struct CatalogPageUpdate: Sendable {
    var items: [MediaItem]
    var totalCount: Int?
}

typealias CatalogPageHandler = @MainActor @Sendable (CatalogPageUpdate) -> Void

struct CatalogIndexProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case listing
        case artwork
    }

    var phase: Phase
    var completed: Int
    var total: Int

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1, Double(completed) / Double(total))
    }

    var isDeterminate: Bool { total > 0 }

    var isFinished: Bool { total > 0 && completed >= total }

    var label: String {
        switch phase {
        case .listing: "Indexing"
        case .artwork: "Caching artwork"
        }
    }

    var countLabel: String {
        if total > 0 {
            return "\(completed.formatted()) of \(total.formatted())"
        }
        return completed.formatted()
    }

    static func listing(loaded: Int, total: Int?) -> CatalogIndexProgress {
        CatalogIndexProgress(phase: .listing, completed: loaded, total: total ?? 0)
    }

    static func artwork(cached: Int, total: Int) -> CatalogIndexProgress {
        CatalogIndexProgress(phase: .artwork, completed: cached, total: total)
    }
}

enum CatalogPaging {
    static let pageSize = 200
    /// First request when a grid is waiting to paint. One screen plus a little extra, then
    /// the rest of the catalog continues in the usual page size.
    static let firstPaintSize = 48
    static let maxItems = 20_000

    static func nextStartIndex(
        fetchedCount: Int,
        currentStart: Int,
        totalCount: Int?,
        pageSize: Int = pageSize,
        maxItems: Int = maxItems
    ) -> Int? {
        guard fetchedCount > 0 else { return nil }
        let next = currentStart + fetchedCount
        if next >= maxItems { return nil }
        // When the server reports a total, trust it: keep paging until we reach it, even if a
        // page came back short. The short-page heuristic is only a fallback for an unknown total —
        // otherwise a single undersized page would stop the catalog before it finished loading.
        if let totalCount {
            return next >= totalCount ? nil : next
        }
        if fetchedCount < pageSize { return nil }
        return next
    }
}

struct CatalogPage: Sendable {
    let items: [MediaItem]
    let nextStart: Int?
    let totalCount: Int?
}

/// Maps Jellyfin item `RemoteTrailers` the same way the server web client does.
enum JellyfinTrailers {
    static func remotes(from urls: [MediaURL]?) -> [TitleTrailer] {
        var trailers: [TitleTrailer] = []
        var seen: Set<String> = []
        for remote in urls ?? [] {
            guard let url = remote.url else { continue }
            let title = displayTitle(remote.name)
            guard let trailer = TitleTrailer.jellyfinRemote(url: url, title: title),
                  seen.insert(trailer.id).inserted
            else { continue }
            trailers.append(trailer)
        }
        return trailers
    }

    static func displayTitle(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Trailer" : trimmed
    }
}
