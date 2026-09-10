import Foundation
import Get
import JellyfinAPI
import os

class JellyfinLibraryClient: @unchecked Sendable {
    private let client: JellyfinClient
    private let userID: String
    private let artwork: ArtworkURLBuilder
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
            artwork.thumb(for: item, maxWidth: 640)
        case .portrait, .ranked:
            artwork.primary(for: item, maxHeight: ArtworkURLBuilder.posterMaxHeight)
        case .labeledPortrait:
            if item.kind == .genre {
                artwork.genreCover(for: item, maxWidth: 480)
            } else {
                artwork.primary(for: item, maxHeight: ArtworkURLBuilder.posterMaxHeight)
            }
        }
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

    enum HomeChunk: Sendable {
        case continueWatching([MediaItem])
        case nextUp([MediaItem])
        case recentlyWatched([MediaItem])
        case featured([MediaItem])
        case collections(HomeSection?)
        case genres(HomeSection?)
        case libraryHome(libraries: [MediaLibrary], sections: [HomeSection])
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

    func item(id: String) async throws -> (MediaItem, BaseItemDto) {
        let dto = try await client.send(Paths.getItem(itemID: id, userID: userID)).value
        guard let item = ItemMapper.mediaItem(from: dto) else {
            throw ZelefinError.missingItemID
        }
        return (item, dto)
    }

    func trailers(for dto: BaseItemDto) async -> [TitleTrailer] {
        guard let itemID = dto.id else { return [] }
        var trailers: [TitleTrailer] = []
        var seenYouTube: Set<String> = []
        var seenVimeo: Set<String> = []
        let isSeries = dto.type == .series
        let tmdbID = JellyfinTmdbCatalog.tmdbID(from: dto.providerIDs)
        let imdbID = JellyfinTmdbCatalog.imdbID(from: dto.providerIDs)

        func appendYouTube(id: String, title: String) {
            guard TitleTrailer.isOfficialTrailer(title: title) else { return }
            if seenYouTube.insert(id).inserted {
                trailers.append(.youtube(id: id, title: title))
            }
        }

        if let locals = try? await client.send(Paths.getLocalTrailers(itemID: itemID, userID: userID)).value {
            for local in locals {
                if let item = ItemMapper.mediaItem(from: local) {
                    trailers.append(.jellyfin(item))
                }
            }
        }

        for remote in dto.remoteTrailers ?? [] {
            guard let url = remote.url else { continue }
            let title = displayTitle(remote.name)
            if let youtubeID = TrailerLinkParser.youtubeVideoID(from: url) {
                appendYouTube(id: youtubeID, title: title)
            } else if let vimeoID = TrailerLinkParser.vimeoVideoID(from: url),
                      TitleTrailer.isOfficialTrailer(title: title),
                      seenVimeo.insert(vimeoID).inserted
            {
                trailers.append(.vimeo(id: vimeoID, title: title))
            }
        }

        if let tmdbID, let seerr = PluginSettings.seerrClient {
            for video in await seerr.videos(tmdbID: tmdbID, isSeries: isSeries) {
                if case .youtube(let youtubeID) = video.kind {
                    appendYouTube(id: youtubeID, title: video.title)
                }
            }
        }

        if seenYouTube.isEmpty, seenVimeo.isEmpty, trailers.isEmpty {
            let extras = await WikidataTrailers.youtubeIDs(
                imdbID: imdbID,
                tmdbID: tmdbID,
                isSeries: isSeries
            )
            if let youtubeID = extras.first {
                appendYouTube(id: youtubeID, title: "Official Trailer")
            }
        }

        let locals = trailers.filter { $0.jellyfinItem != nil }
        let remotes = trailers.filter { $0.jellyfinItem == nil }
            .sorted { $0.trailerRank < $1.trailerRank }
        return locals + remotes
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

    private func displayTitle(_ name: String?) -> String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Trailer" : trimmed
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
        startTime: TimeInterval? = nil
    ) async throws -> PlaybackPlan {
        try await fetchPlaybackPlan(
            for: item,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex,
            enableDirectPlay: allowDirectPlay,
            maxBitrate: maxBitrate,
            startTime: startTime
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
        startTime: TimeInterval?
    ) async throws -> PlaybackPlan {
        let bitrate = maxBitrate ?? PlaybackPreferences.maxStreamingBitrate
        let resume = await resolvedResumePosition(requested: startTime, item: item)
        let profile = AVDeviceProfileFactory.make(
            preferFMP4InHLS: PlaybackPreferences.effectivePreferFMP4InHLS,
            maxBitrate: bitrate
        )
        let body = PlaybackInfoDto(
            audioStreamIndex: audioIndex,
            deviceProfile: profile,
            enableDirectPlay: enableDirectPlay,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: bitrate,
            startTimeTicks: TickClock.intTicks(from: resume),
            subtitleStreamIndex: subtitleIndex,
            userID: userID
        )

        let query: Paths.GetPostedPlaybackInfoParameters? = serverCapabilities.withLock({ $0.prefersPlaybackInfoBody })
            ? nil
            : .init(
                userID: userID,
                maxStreamingBitrate: bitrate,
                startTimeTicks: TickClock.intTicks(from: resume),
                audioStreamIndex: audioIndex,
                subtitleStreamIndex: subtitleIndex,
                isAutoOpenLiveStream: true,
                enableDirectPlay: enableDirectPlay,
                enableDirectStream: true,
                enableTranscoding: true
            )
        let response = try await client.send(
            Paths.getPostedPlaybackInfo(
                itemID: item.id,
                parameters: query,
                body
            )
        ).value

        guard let source = response.mediaSources?.first else {
            throw ZelefinError.emptyPlaybackSources
        }

        let method = ItemMapper.playbackMethod(from: source)
        let url = StreamResumeURL.ensuringStartTimeTicks(
            try streams.url(itemID: item.id, source: source),
            method: method,
            startTime: resume
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
            startTime: resume,
            byteSize: source.size.map(Int64.init),
            extraHTTPHeaders: source.requiredHTTPHeaders ?? [:],
            audioTracks: ItemMapper.tracks(from: streams, kind: .audio),
            subtitleTracks: ItemMapper.tracks(from: streams, kind: .subtitle),
            externalSubtitles: self.streams.externalSubtitles(itemID: item.id, source: source)
        )
    }

    private func resolvedResumePosition(requested: TimeInterval?, item: MediaItem) async -> TimeInterval {
        let local = requested ?? item.playbackPosition
        if local > PlaybackResumePolicy.threshold { return local }
        guard let fresh = try? await self.item(id: item.id).0.playbackPosition else { return local }
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
        default: [.movie, .series]
        }
    }

    func mixedCatalogFilterTypes() -> [BaseItemKind] { [.movie, .series] }

    func collectionFilterTypes() -> [BaseItemKind] { [.movie, .series, .boxSet, .video] }

    private func includeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie]
        case .shows: [.series]
        case .homeVideos: [.video, .movie]
        case .collections: [.boxSet]
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
        let result = try await client.send(
            Paths.getSessions(parameters: .init(activeWithinSeconds: activeWithinSeconds))
        ).value
        return PlaybackSession.sorted(result.compactMap(PlaybackSession.init(dto:)))
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
}

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

/// YouTube video IDs published on Wikidata for a title (no API key).
enum WikidataTrailers {
    static func youtubeIDs(imdbID: String?, tmdbID: Int?, isSeries: Bool) async -> [String] {
        guard let query = sparql(imdbID: imdbID, tmdbID: tmdbID, isSeries: isSeries) else { return [] }
        var components = URLComponents(string: "https://query.wikidata.org/sparql")
        components?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "query", value: query)
        ]
        guard let url = components?.url else { return [] }

        var request = URLRequest(url: url)
        request.setValue(
            "Zelefin/\(DeviceIdentity.version) (https://github.com/rndllb/Zelefin)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("application/sparql-results+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 12

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200 ..< 300).contains(http.statusCode),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [String: Any],
              let bindings = results["bindings"] as? [[String: Any]]
        else {
            return []
        }

        var seen: Set<String> = []
        var ids: [String] = []
        for binding in bindings {
            guard let youtube = binding["youtube"] as? [String: Any],
                  let value = youtube["value"] as? String,
                  let videoID = TrailerLinkParser.youtubeVideoID(from: value) ?? TrailerLinkParser.youtubeVideoID(from: "https://youtu.be/\(value)"),
                  seen.insert(videoID).inserted
            else { continue }
            ids.append(videoID)
        }
        return ids
    }

    static func sparql(imdbID: String?, tmdbID: Int?, isSeries: Bool) -> String? {
        var clauses: [String] = []
        if let imdbID, imdbID.hasPrefix("tt"), imdbID.dropFirst(2).allSatisfy(\.isNumber) {
            clauses.append("{ ?item wdt:P345 \"\(imdbID)\" }")
        }
        if let tmdbID {
            let property = isSeries ? "P4983" : "P4947"
            clauses.append("{ ?item wdt:\(property) \"\(tmdbID)\" }")
        }
        guard !clauses.isEmpty else { return nil }
        return """
        SELECT DISTINCT ?youtube WHERE {
          \(clauses.joined(separator: " UNION "))
          ?item wdt:P1651 ?youtube.
        }
        LIMIT 6
        """
    }
}
