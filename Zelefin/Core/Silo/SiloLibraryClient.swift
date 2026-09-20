import Foundation

final class SiloLibraryClient: LibraryServing, @unchecked Sendable {
    let api: SiloAPIClient
    private let profileID: String

    init(api: SiloAPIClient, profileID: String) {
        self.api = api
        self.profileID = profileID
    }

    func updateServerVersion(_ raw: String?) {}

    func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL? {
        switch style {
        case .landscape, .replayLandscape:
            item.backdropURL ?? item.posterURL
        case .portrait, .ranked, .labeledPortrait:
            item.posterURL ?? item.backdropURL
        }
    }

    func programStillURL(for item: MediaItem, channel: MediaItem?) -> URL? {
        item.backdropURL ?? item.posterURL ?? channel?.posterURL
    }

    func primaryURL(for item: MediaItem, maxHeight: Int) -> URL? {
        item.posterURL ?? item.backdropURL
    }

    func backdropURL(for item: MediaItem, maxWidth: Int) -> URL? {
        item.backdropURL ?? item.posterURL
    }

    func logoURL(for item: MediaItem, maxHeight: Int) -> URL? { item.logoURL }

    func userAvatarURL(userID: String, tag: String?) -> URL? { nil }

    func personImageURL(id: String, tag: String?, maxHeight: Int) -> URL? { nil }

    func searchHitImageURL(_ hit: LibrarySearchHit) -> URL? { hit.imageURL }

    func cacheableArtworkURLs(for item: MediaItem) -> [URL] {
        [item.posterURL, item.backdropURL, item.logoURL].compactMap { $0 }
    }

    func chapterImageURL(itemID: String, index: Int, tag: String?) -> URL? { nil }

    func trickplayTileURL(itemID: String, info: TrickplayInfo, time: TimeInterval) -> URL? { nil }

    func resumeItemsIgnoringErrors() async -> [MediaItem] {
        if let resume = await mappedHome()?.resume, !resume.isEmpty {
            return resume
        }
        return await ignoringErrors {
            let progress = try await api.progress()
            if let items = progress.continueWatching, !items.isEmpty {
                return items.map { SiloMapper.mediaItem(from: $0, queueKind: .resume) }
            }
            return (progress.items ?? []).compactMap { entry in
                if let item = entry.item { return SiloMapper.mediaItem(from: item, queueKind: .resume) }
                return nil
            }.filter { $0.playbackPosition > 5 && !$0.isWatched }
        } ?? []
    }

    func nextUpItemsIgnoringErrors() async -> [MediaItem] {
        if let nextUp = await mappedHome()?.nextUp, !nextUp.isEmpty {
            return nextUp
        }
        let fetched = await ignoringErrors {
            try await api.homeSectionItems(id: "next_up").map {
                SiloMapper.mediaItem(from: $0, queueKind: .nextUp)
            }
        } ?? []
        if !fetched.isEmpty { return fetched }
        return await ignoringErrors {
            try await api.homeSectionItems(id: "next_in_series").map {
                SiloMapper.mediaItem(from: $0, queueKind: .nextUp)
            }
        } ?? []
    }

    func recentlyWatchedIgnoringErrors() async -> [MediaItem] {
        let history = await ignoringErrors {
            try await catalogItems(query: [
                "source": "history",
                "sort": "date_viewed",
                "order": "desc",
                "limit": "40"
            ])
        } ?? []
        if !history.isEmpty {
            return HomeLayoutPreferences.collapseRecentlyWatched(history)
        }
        if let watched = await mappedHome()?.recentlyWatched, !watched.isEmpty {
            return HomeLayoutPreferences.collapseRecentlyWatched(watched)
        }
        return []
    }

    func featuredItemsIgnoringErrors() async -> [MediaItem] {
        async let catalogMovies = recentlyAdded(type: "movie", limit: 16, imageSize: "large")
        async let catalogShows = recentlyAdded(type: "show", limit: 16, imageSize: "large")
        async let home = mappedHome()
        var movies = await catalogMovies
        var shows = await catalogShows
        if movies.isEmpty || shows.isEmpty {
            let remapped = SiloMapper.canonicalLibraryHome(
                await home?.librarySections ?? [],
                libraries: []
            )
            if movies.isEmpty { movies = remapped.movies?.items ?? [] }
            if shows.isEmpty { shows = remapped.shows?.items ?? [] }
        }
        let featured = HomeLayoutPreferences.featured(
            latestMovies: movies,
            latestShows: shows
        )
        let homeFeatured = await home?.featured ?? []
        if !featured.isEmpty {
            return HomeLayoutPreferences.replacingHeroArtwork(on: featured, with: homeFeatured)
        }
        return homeFeatured
    }

    func recentlyAddedForAlerts() async -> [MediaItem]? {
        let movies = await recentlyAdded(type: "movie", limit: 24)
        let shows = await recentlyAdded(type: "show", limit: 24)
        if movies.isEmpty && shows.isEmpty { return nil }
        return movies + shows
    }

    func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        let catalog = (try? await libraries()) ?? []
        let ordered = HomeLayoutPreferences.orderedHomeLibraries(catalog)
        var sections: [HomeSection] = []
        for library in ordered {
            if library.libraryKind == .shows {
                let items = await recentlyAdded(type: "show", libraryID: library.id, limit: 12)
                guard !items.isEmpty else { continue }
                sections.append(
                    HomeSection(
                        id: "library-shows",
                        title: "Recently Added Shows",
                        style: .portrait,
                        items: items
                    )
                )
            } else {
                let type = SiloMapper.catalogType(for: library.libraryKind)
                let items = await recentlyAdded(type: type, libraryID: library.id, limit: 12)
                guard !items.isEmpty else { continue }
                sections.append(
                    HomeSection(
                        id: "library-\(library.id)",
                        title: library.libraryKind.recentlyAddedTitle(libraryName: library.name),
                        style: .portrait,
                        items: items
                    )
                )
            }
        }
        let mapped = await mappedHome()
        let remapped = SiloMapper.canonicalLibraryHome(mapped?.librarySections ?? [], libraries: catalog)
        if !sections.contains(where: { $0.id == "library-shows" }) {
            if let shows = remapped.shows {
                insertShowsSection(shows, into: &sections)
            } else {
                let items = await recentlyAdded(type: "show", limit: 12)
                if !items.isEmpty {
                    insertShowsSection(
                        HomeSection(
                            id: "library-shows",
                            title: "Recently Added Shows",
                            style: .portrait,
                            items: items
                        ),
                        into: &sections
                    )
                }
            }
        }
        if !sections.contains(where: { $0.id.hasPrefix("library-") && $0.id != "library-shows" }) {
            if let movies = remapped.movies {
                sections.insert(movies, at: 0)
            } else {
                let items = await recentlyAdded(type: "movie", limit: 12)
                if !items.isEmpty {
                    let movieLibraryID = catalog.first(where: { $0.libraryKind == .movies })?.id ?? "movies"
                    sections.insert(
                        HomeSection(
                            id: "library-\(movieLibraryID)",
                            title: "Recently Added Movies",
                            style: .portrait,
                            items: items
                        ),
                        at: 0
                    )
                }
            }
        }
        sections.append(contentsOf: remapped.extras)
        if let extra = mapped?.extraSections {
            sections.append(contentsOf: extra)
        }
        return (catalog, sections)
    }

    private func insertShowsSection(_ shows: HomeSection, into sections: inout [HomeSection]) {
        if let movieIndex = sections.firstIndex(where: { $0.title == "Recently Added Movies" }) {
            sections.insert(shows, at: movieIndex + 1)
        } else {
            sections.insert(shows, at: 0)
        }
    }

    func collectionsSectionIgnoringErrors() async -> HomeSection? {
        // Unlike Jellyfin's franchise box sets, Silo "collections" are dynamic
        // curated rows (Trending Today, Popular Comedy, …) that don't fit the
        // "Browse by Collection" shelf, so it's hidden from the Silo home feed.
        // The Collections tab (hidden by default) still browses them for anyone
        // who opts in.
        nil
    }

    func genresSectionIgnoringErrors() async -> HomeSection? {
        let names = await ignoringErrors {
            (try await api.catalogFilters().genres ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } ?? []
        var genres = names.prefix(24).map { SiloMapper.genreItem(name: $0) }
        if genres.isEmpty {
            let covers = await recentlyAdded(type: "movie", limit: 80) + (await recentlyAdded(type: "show", limit: 80))
            var seen = Set<String>()
            genres = covers.flatMap(\.genres).compactMap { name in
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { return nil }
                return SiloMapper.genreItem(name: trimmed)
            }
        }
        guard !genres.isEmpty else { return nil }
        let covers = await recentlyAdded(type: "movie", limit: 80) + (await recentlyAdded(type: "show", limit: 80))
        return HomeSection(
            id: "genres",
            title: "Browse by Genre",
            style: .labeledPortrait,
            items: HomeLayoutPreferences.applyGenreCovers(genres, covers: covers)
        )
    }

    func movieRecommendationsIgnoringErrors() async -> [HomeSection] {
        var rows: [HomeSection] = []
        if let main = await ignoringErrors({ try await api.forYouMain() }),
           !main.entries.isEmpty {
            rows.append(contentsOf: SiloMapper.recommendationSections(from: [main]))
        }
        let extras = await ignoringErrors { try await api.recommendationRows() } ?? []
        rows.append(contentsOf: SiloMapper.recommendationSections(from: extras))
        if rows.isEmpty, let mapped = await mappedHome()?.recommendations {
            rows = mapped
        }
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }.prefix(5).map { $0 }
    }

    func upcomingEpisodesIgnoringErrors() async -> [MediaItem] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let start = Date()
        let end = Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        let events = await ignoringErrors {
            try await api.calendar(
                start: formatter.string(from: start),
                end: formatter.string(from: end),
                timezone: TimeZone.current.identifier
            ).allEvents
        } ?? []
        var seen = Set<String>()
        return events.compactMap(SiloMapper.mediaItem(from:)).filter { seen.insert($0.id).inserted }
    }

    func libraries() async throws -> [MediaLibrary] {
        try await api.libraries().map(SiloMapper.library(from:))
    }

    func tmdbCatalog() async -> JellyfinTmdbCatalog {
        JellyfinTmdbCatalog(movieIDs: [], seriesIDs: [])
    }

    func items(
        in library: MediaLibrary,
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async throws -> [MediaItem] {
        var params = baseCatalogQuery(query)
        params["library_id"] = library.id
        if let type = SiloMapper.catalogType(for: library.libraryKind) {
            params["type"] = type
        }
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func items(
        inLibraries libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async -> [MediaItem] {
        if libraries.count == 1 {
            return (try? await items(in: libraries[0], query: query, onPage: onPage)) ?? []
        }
        var collected: [MediaItem] = []
        for library in libraries {
            let page = (try? await items(in: library, query: query, onPage: nil)) ?? []
            collected.append(contentsOf: page)
        }
        let filtered = applyLocalFilters(collected, query: query)
        await onPage?(CatalogPageUpdate(items: filtered, totalCount: filtered.count))
        return filtered
    }

    func browseCatalog(
        kind: LibraryKind,
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async -> [MediaItem] {
        if kind == .favorites {
            var params = baseCatalogQuery(query)
            params["favorite"] = "true"
            return (try? await pagedCatalog(params, query: query.applyingFavoriteFilter(), onPage: onPage)) ?? []
        }
        let matches = HomeLayoutPreferences.libraries(libraries, matching: kind)
        if !matches.isEmpty {
            return await items(inLibraries: matches, query: query, onPage: onPage)
        }
        var params = baseCatalogQuery(query)
        if let type = SiloMapper.catalogType(for: kind) {
            params["type"] = type
        }
        return (try? await pagedCatalog(params, query: query, onPage: onPage)) ?? []
    }

    func catalogCount(kind: LibraryKind, libraries: [MediaLibrary]) async -> Int {
        await browseCatalog(kind: kind, libraries: libraries).count
    }

    func catalogFilterOptions(for library: MediaLibrary) async -> CatalogFilterOptions {
        await options(from: (try? await items(in: library)) ?? [])
    }

    func catalogFilterOptions(for kind: LibraryKind) async -> CatalogFilterOptions {
        CatalogFilterOptions()
    }

    func mixedCatalogFilterOptions(parentID: String?) async -> CatalogFilterOptions {
        CatalogFilterOptions()
    }

    func collectionFilterOptions(parentID: String) async -> CatalogFilterOptions {
        CatalogFilterOptions()
    }

    func items(genreID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        var params = baseCatalogQuery(query)
        params["genre"] = genreID
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func items(parentID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        // Silo resolves a collection's members through the catalog endpoint keyed
        // by `source` + `collection_id`. Library/franchise collections and personal
        // (user) collections use different source values, and a given id could be
        // either kind, so try the library source first, then the personal one.
        for source in ["library_collection", "user_collection"] {
            var params = baseCatalogQuery(query)
            params["source"] = source
            params["collection_id"] = parentID
            if let members = try? await pagedCatalog(params, query: query, onPage: onPage),
               !members.isEmpty {
                return members
            }
        }
        // Last resort for servers that expose collection children via a parent filter.
        var params = baseCatalogQuery(query)
        params["parent_id"] = parentID
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func items(personID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        var params = baseCatalogQuery(query)
        params["source"] = "person"
        params["person_id"] = personID
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func items(studioID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        var params = baseCatalogQuery(query)
        params["studio"] = studioID
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func collectionItems(query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        var params = baseCatalogQuery(query)
        params["type"] = "collection"
        return try await pagedCatalog(params, query: query, onPage: onPage)
    }

    func boxSets() async -> [MediaItem] {
        (try? await collectionItems(query: .default, onPage: nil)) ?? []
    }

    func item(id: String) async throws -> MediaItem {
        SiloMapper.mediaItem(from: try await api.catalogItem(id: id))
    }

    func titleMoreInfo(for item: MediaItem) async -> TitleMoreInfo {
        if let catalog = try? await api.catalogItem(id: item.id) {
            return SiloMapper.moreInfo(from: catalog)
        }
        return TitleMoreInfoMapper.info(from: item)
    }

    func trailers(for item: MediaItem) async -> [TitleTrailer] {
        await ignoringErrors {
            SiloMapper.trailers(from: try await api.catalogItem(id: item.id))
        } ?? []
    }

    func similarItems(for item: MediaItem) async -> [MediaItem] {
        let recommended = await ignoringErrors {
            try await api.similarItems(id: item.id).map { SiloMapper.mediaItem(from: $0) }
        } ?? []
        if !recommended.isEmpty { return recommended }
        // The recommendation engine returns nothing for many titles, so fall back
        // to same-genre catalog titles — mirroring Jellyfin's "More Like This".
        guard let genre = item.genres.first else { return [] }
        return await api.genreRelated(
            genre: genre,
            type: Self.siloCatalogType(for: item.kind),
            excluding: item.id
        ).map { SiloMapper.mediaItem(from: $0) }
    }

    private static func siloCatalogType(for kind: MediaKind) -> String {
        switch kind {
        case .movie: return "movie"
        case .series, .season, .episode: return "show"
        default: return ""
        }
    }

    func collections(containing itemID: String) async -> [ItemCollectionMembership] { [] }

    func credits(for item: MediaItem) async -> [CreditPerson] {
        await ignoringErrors {
            SiloMapper.credits(from: try await api.catalogItem(id: item.id))
        } ?? []
    }

    func specialFeatures(for itemID: String) async -> [TitleExtra] {
        await ignoringErrors {
            SiloMapper.extras(from: try await api.catalogItem(id: itemID))
        } ?? []
    }

    func themeVideos(for itemID: String) async -> [TitleExtra] { [] }

    func cinemaIntros(for itemID: String) async -> [MediaItem] { [] }

    func seasons(seriesID: String) async throws -> [MediaItem] {
        let series = try? await item(id: seriesID)
        return try await api.seasons(seriesID: seriesID).compactMap {
            SiloMapper.season(from: $0, seriesID: seriesID, seriesTitle: series?.name)
        }
    }

    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem] {
        let series = try? await item(id: seriesID)
        let seasons = (try? await api.seasons(seriesID: seriesID)) ?? []
        let records: [SiloEpisodeRecord]
        if let seasonID {
            let match = seasons.first(where: { ($0.contentID ?? $0.id) == seasonID })
            records = try await api.episodes(
                seriesID: seriesID,
                seasonNumber: Int(seasonID) ?? match?.seasonNumber,
                seasonContentID: match?.contentID ?? match?.id ?? seasonID
            )
        } else if !seasons.isEmpty {
            records = await api.episodes(seriesID: seriesID, seasons: seasons)
        } else {
            records = try await api.episodes(seriesID: seriesID)
        }
        return records.compactMap {
            SiloMapper.mediaItem(from: $0, seriesID: seriesID, seriesTitle: series?.name)
        }
    }

    func nextEpisode(after item: MediaItem) async -> MediaItem? {
        guard item.kind == .episode, let seriesID = item.seriesID else { return nil }
        let episodes = (try? await episodes(seriesID: seriesID, seasonID: nil)) ?? []
        return PlaybackEpisodeAdvance.next(after: item, in: MediaItem.orderedEpisodes(episodes))
    }

    func search(term: String) async throws -> [MediaItem] {
        try await catalogItems(query: ["q": term, "limit": "40"])
    }

    func searchLibrary(_ term: String) async throws -> [LibrarySearchHit] {
        try await search(term: term).map(SiloMapper.searchHit(from:))
    }

    func person(id: String) async -> CreditPerson? { nil }

    func mediaVersions(for itemID: String) async -> [MediaVersion] {
        let versions = (try? await api.versions(itemID: itemID)) ?? []
        return versions.enumerated().map { index, version in
            MediaVersion(
                id: String(version.resolvedFileID ?? index),
                title: version.label ?? version.name ?? "Version \(index + 1)"
            )
        }
    }

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        allowDirectPlay: Bool,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan {
        let start = startTime ?? item.playbackPosition
        let profile = profileID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !profile.isEmpty else {
            throw ZelefinError.server("Select a profile before playing.")
        }
        let fileID = try await resolveFileID(for: item, mediaSourceID: mediaSourceID)
        let capability = try? await api.playbackCapability()
        if let capability, !capability.supportsV3 {
            throw ZelefinError.server("This Silo server does not advertise playback protocol v3.")
        }
        let decision: SiloPlaybackDecision
        do {
            decision = try await api.startPlayback(
                SiloPlaybackStart.v3Request(
                    fileID: fileID,
                    profileID: profile,
                    startPosition: start,
                    authorizedMediaOrigins: await api.allowsAuthorizedMediaOrigins(capability),
                    maxBitrate: maxBitrate,
                    audioIndex: audioIndex,
                    subtitleIndex: SiloPlaybackStart.subtitleStartIndex(subtitleIndex)
                )
            )
        } catch let error as SiloHTTPError {
            throw ZelefinError.server(SiloPlaybackStart.unsupportedMessage(for: SiloPlaybackDecision(), error: error))
        }

        if let url = await SiloPlaybackStart.playableURL(from: decision, client: api) {
            let plan = decision.playbackPlan
            let stream = plan?.stream
            let protocolKind = stream?.protocolKind?.lowercased() ?? ""
            let delivery = plan?.delivery?.lowercased() ?? ""
            if delivery.contains("media3") {
                throw ZelefinError.server(SiloPlaybackStart.unsupportedMessage(for: decision, error: nil))
            }
            let method = SiloPlaybackStart.playbackMethod(
                protocolKind: protocolKind,
                delivery: delivery
            )
            let timeline = plan?.timeline
            let headers = await api.streamHeaders().merging(stream?.headers ?? [:]) { _, incoming in incoming }
            let overlay = await SiloPlaybackStart.subtitleOverlay(
                inventory: plan?.subtitle?.inventory ?? [],
                subtitlesOff: subtitleIndex == -1,
                resolve: { await api.resolveURL($0) }
            )
            let fileTracks = await tracks(for: item, mediaSourceID: String(fileID), seeded: [])
            return PlaybackPlan(
                item: item,
                streamURL: url,
                playSessionID: decision.sessionID ?? decision.playSessionID ?? plan?.sessionID,
                mediaSourceID: String(fileID),
                method: method,
                container: stream?.container ?? plan?.source?.container ?? url.pathExtension,
                videoCodec: plan?.source?.videoCodec,
                videoRange: item.videoRange,
                audioFormat: item.audioFormat,
                startTime: SiloPlaybackStart.resolvedPlayerStart(requested: start, timeline: timeline),
                byteSize: nil,
                extraHTTPHeaders: headers,
                audioTracks: fileTracks.audio,
                subtitleTracks: overlay.tracks.isEmpty ? fileTracks.subtitles : overlay.tracks,
                externalSubtitles: overlay.sidecars,
                isLive: false,
                clientOwnsPlayhead: SiloPlaybackStart.clientOwnsPlayhead(
                    protocolKind: protocolKind,
                    delivery: delivery,
                    timeline: timeline
                )
            )
        }
        throw ZelefinError.server(SiloPlaybackStart.unsupportedMessage(for: decision, error: nil))
    }

    func playbackFileID(for item: MediaItem, mediaSourceID: String? = nil) async throws -> Int {
        try await resolveFileID(for: item, mediaSourceID: mediaSourceID)
    }

    // MARK: - Managed downloads

    func downloadsAvailable() async -> Bool {
        (try? await api.downloadCapability())?.isUsable ?? false
    }

    func prepareDownloadAsset(for item: MediaItem, plan: PlaybackPlan) async throws -> DownloadAsset {
        let capability = try await api.downloadCapability()
        guard capability.isUsable else {
            throw ZelefinError.server("Downloads are not enabled for your Silo profile.")
        }
        let fileID = try? await resolveFileID(for: item, mediaSourceID: nil)
        let request = SiloCreateDownloadRequest(
            contentID: item.id,
            fileID: fileID,
            quality: capability.preferredQuality
        )
        let created = try await api.createDownload(request)
        var rowID = created.first(where: { $0.contentID == item.id })?.id ?? created.first?.id
        if rowID == nil {
            rowID = (try? await api.downloadRows())?.first(where: { $0.contentID == item.id })?.id
        }
        guard let rowID else {
            throw ZelefinError.server("The Silo server did not accept this download.")
        }
        let ready = try await waitForDownloadReady(id: rowID)
        guard let url = await api.downloadFileURL(id: ready.id) else {
            throw ZelefinError.server("Could not resolve the Silo download URL.")
        }
        return DownloadAsset(url: url, headers: await api.streamHeaders(), serverDownloadID: ready.id)
    }

    func finalizeServerDownload(id: String) async {
        try? await api.patchDownloadStatus(id: id, status: "completed")
    }

    func deleteServerDownload(id: String) async {
        try? await api.deleteDownload(id: id)
    }

    /// Polls the managed-download registry until the server marks the row ready
    /// (it may need to prepare or transcode the file first).
    private func waitForDownloadReady(id: String) async throws -> SiloDownloadRow {
        for attempt in 0..<90 {
            let rows = (try? await api.downloadRows()) ?? []
            if let row = rows.first(where: { $0.id == id }) {
                if row.isReady { return row }
                if row.isRevoked {
                    throw ZelefinError.server("The Silo server could not prepare this download.")
                }
            }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(attempt < 5 ? 1 : 2))
        }
        throw ZelefinError.server("Timed out waiting for Silo to prepare this download.")
    }

    func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        let catalog = try? await api.catalogItem(id: itemID)
        let item = catalog.map { SiloMapper.mediaItem(from: $0) }
            ?? LibrarySearchHit(
                id: itemID,
                name: itemID,
                kind: .title(.movie),
                subtitle: nil,
                year: nil,
                imageTag: nil
            ).recentItem(kind: .movie)
        var seeded = catalog?.fileIDGroups.flatMap { $0 } ?? []
        if !seeded.contains(where: \.hasStreamTracks) {
            seeded = (try? await api.versions(itemID: itemID)) ?? seeded
        }
        return await tracks(for: item, mediaSourceID: nil, seeded: seeded)
    }

    func measureStreamingBitrate(
        size: Int,
        timeout: TimeInterval,
        transport: NetworkTransport
    ) async -> BitrateProbeResult? {
        let fallback = await bitrateFallbackURL()
        let work = Task {
            try await downloadBitrateTest(size: size, transport: transport, fallbackURL: fallback)
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(timeout))
            work.cancel()
        }
        defer { watchdog.cancel() }
        return try? await work.value
    }

    private func bitrateFallbackURL() async -> URL? {
        let items = await resumeItemsIgnoringErrors()
            + (await featuredItemsIgnoringErrors())
        return items.lazy.compactMap { self.cacheableArtworkURLs(for: $0).first }.first
    }

    private func downloadBitrateTest(
        size: Int,
        transport: NetworkTransport,
        fallbackURL: URL?
    ) async throws -> BitrateProbeResult {
        let start = Date()
        let data = try await api.bitrateTestBytes(size: size, fallbackURL: fallbackURL)
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

    private func tracks(
        for item: MediaItem,
        mediaSourceID: String?,
        seeded: [SiloMediaVersion]
    ) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        let version = await versionForTracks(item: item, mediaSourceID: mediaSourceID, seeded: seeded)
        return (version?.audioMediaTracks ?? [], version?.subtitleMediaTracks ?? [])
    }

    private func versionForTracks(
        item: MediaItem,
        mediaSourceID: String?,
        seeded: [SiloMediaVersion]
    ) async -> SiloMediaVersion? {
        let preferred = SiloFileID.parse(mediaSourceID ?? "")
        func match(in versions: [SiloMediaVersion]) -> SiloMediaVersion? {
            let withTracks = versions.filter {
                !($0.audioTracks ?? []).isEmpty || !($0.subtitleTracks ?? []).isEmpty
            }
            if let preferred, let exact = withTracks.first(where: { $0.resolvedFileID == preferred }) {
                return exact
            }
            return withTracks.first
        }
        if let version = match(in: seeded) {
            return version
        }
        if let watch = try? await api.watchVersions(itemID: item.id), let version = match(in: watch) {
            return version
        }
        if let catalog = try? await api.versions(itemID: item.id), let version = match(in: catalog) {
            return version
        }
        if item.kind == .series || item.kind == .season {
            let records = await episodeRecords(for: item, catalog: nil, fallbackID: nil)
            if let episodeID = playableEpisodeID(from: records, item: item, catalog: nil),
               let watch = try? await api.watchVersions(itemID: episodeID),
               let version = match(in: watch)
            {
                return version
            }
        }
        return nil
    }

    private func resolveFileID(for item: MediaItem, mediaSourceID: String?) async throws -> Int {
        if let mediaSourceID, let preferred = SiloFileID.parse(mediaSourceID) {
            return preferred
        }
        var lastError: Error?
        do {
            if let fileID = try await lookupFileID(forContentID: item.id) {
                return fileID
            }
        } catch let error as SiloHTTPError where error.isInvalidWatchTarget {
            lastError = error
        } catch {
            lastError = error
        }
        let catalog = try? await api.catalogItem(id: item.id)
        if let fileID = catalog?.resolvedFileIDs.first {
            return fileID
        }
        var queue: [String] = []
        var seen = Set<String>([item.id])
        func enqueue(_ raw: String?) {
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return }
            queue.append(trimmed)
        }
        if item.kind == .series || item.kind == .season || catalog?.isDirectlyPlayable == false {
            let records = await episodeRecords(for: item, catalog: catalog, fallbackID: nil)
            if let fileID = records.compactMap(\.resolvedFileID).first {
                return fileID
            }
            enqueue(catalog?.playContentID)
            enqueue(playableEpisodeID(from: records, item: item, catalog: catalog))
        }
        enqueue(catalog?.playbackID)
        enqueue(catalog?.contentID)

        var index = 0
        while index < queue.count {
            let candidateID = queue[index]
            index += 1
            do {
                if let fileID = try await lookupFileID(forContentID: candidateID) {
                    return fileID
                }
            } catch let error as SiloHTTPError where error.isInvalidWatchTarget {
                lastError = error
                enqueue(playableEpisodeID(
                    from: await episodeRecords(for: item, catalog: catalog, fallbackID: candidateID),
                    item: item,
                    catalog: catalog
                ))
            } catch {
                lastError = error
            }
        }
        if let fileID = catalog?.resolvedFileIDs.first {
            return fileID
        }
        if let lastError {
            throw lastError
        }
        throw ZelefinError.server("This title has no playable file on the Silo server.")
    }

    private func lookupFileID(forContentID id: String) async throws -> Int? {
        do {
            let watch = try await api.watchVersions(itemID: id)
            if let fileID = watch.compactMap(\.resolvedFileID).first {
                return fileID
            }
        } catch let error as SiloHTTPError where error.isInvalidWatchTarget {
            throw error
        } catch {
            // Catalog versions can still name a file when watch is missing.
        }
        let versions = (try? await api.versions(itemID: id)) ?? []
        return versions.compactMap(\.resolvedFileID).first
    }

    private func playableEpisodeID(
        from records: [SiloEpisodeRecord],
        item: MediaItem,
        catalog: SiloCatalogItem?
    ) -> String? {
        if let fileOwner = records.first(where: { $0.resolvedFileID != nil }) {
            return fileOwner.contentID ?? fileOwner.id
        }
        let seriesID = episodeSeriesID(for: item, catalog: catalog, fallbackID: nil)
        let episodes = records.compactMap {
            SiloMapper.mediaItem(from: $0, seriesID: seriesID, seriesTitle: item.seriesName ?? catalog?.seriesTitle)
        }
        if item.kind == .series {
            let hero = MediaItem.heroPlaybackItem(title: item, episodes: episodes)
            return hero.kind == .episode ? hero.id : nil
        }
        return episodes.first(where: { !$0.isWatched && $0.playbackPosition > 5 })?.id
            ?? episodes.first(where: { !$0.isWatched })?.id
            ?? episodes.first?.id
            ?? records.first?.contentID
            ?? records.first?.id
    }

    private func episodeRecords(
        for item: MediaItem,
        catalog: SiloCatalogItem?,
        fallbackID: String?
    ) async -> [SiloEpisodeRecord] {
        let seriesID = episodeSeriesID(for: item, catalog: catalog, fallbackID: fallbackID)
        let seasonNumber = item.kind == .season ? (item.seasonIndex ?? catalog?.seasonNumber) : nil
        return (try? await api.episodes(seriesID: seriesID, seasonNumber: seasonNumber)) ?? []
    }

    private func episodeSeriesID(
        for item: MediaItem,
        catalog: SiloCatalogItem?,
        fallbackID: String?
    ) -> String {
        if item.kind == .season {
            return item.seriesID ?? catalog?.seriesID ?? fallbackID ?? item.id
        }
        return catalog?.seriesID ?? item.seriesID ?? fallbackID ?? item.id
    }

    func markPlayed(itemID: String) async throws {
        try await api.markWatched(id: itemID)
    }

    func markUnplayed(itemID: String) async throws {
        try await api.markUnwatched(id: itemID)
    }

    func markFavorite(itemID: String, isFavorite: Bool) async throws -> Bool {
        try await api.setFavorite(id: itemID, isFavorite: isFavorite)
        return isFavorite
    }

    private func mappedHome() async -> SiloMappedHome? {
        await ignoringErrors {
            SiloMapper.homeFeed(from: try await api.homeSections())
        }
    }

    private func recentlyAdded(
        type: String?,
        libraryID: String? = nil,
        limit: Int,
        imageSize: String? = nil
    ) async -> [MediaItem] {
        let types: [String?]
        if type == "show" || type == "series" {
            types = ["series", "show"]
        } else {
            types = [type]
        }
        for candidate in types {
            var query = [
                "sort": "added_at",
                "order": "desc",
                "limit": String(limit)
            ]
            if let candidate { query["type"] = candidate }
            if let libraryID { query["library_id"] = libraryID }
            if let imageSize { query["image_size"] = imageSize }
            let items = await ignoringErrors { try await catalogItems(query: query) } ?? []
            if !items.isEmpty { return items }
            if imageSize == nil {
                query["image_size"] = "large"
                let withArt = await ignoringErrors { try await catalogItems(query: query) } ?? []
                if !withArt.isEmpty { return withArt }
            }
        }
        return []
    }

    private func catalogItems(query: [String: String]) async throws -> [MediaItem] {
        try await api.catalog(query: query).entries.map { SiloMapper.mediaItem(from: $0) }
    }

    private func pagedCatalog(
        _ params: [String: String],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async throws -> [MediaItem] {
        var collected: [MediaItem] = []
        var offset = 0
        let pageSize = CatalogPaging.pageSize
        while collected.count < CatalogPaging.maxItems {
            var pageQuery = params
            pageQuery["offset"] = String(offset)
            pageQuery["limit"] = String(pageSize)
            let response = try await api.catalog(query: pageQuery)
            let mapped = applyLocalFilters(response.entries.map { SiloMapper.mediaItem(from: $0) }, query: query)
            collected.append(contentsOf: mapped)
            await onPage?(CatalogPageUpdate(items: collected, totalCount: response.total ?? response.totalCount))
            if response.entries.count < pageSize { break }
            offset += response.entries.count
        }
        return query.sorted(collected)
    }

    private func baseCatalogQuery(_ query: CatalogBrowseQuery) -> [String: String] {
        let pair = SiloMapper.sortQuery(query.sort)
        var params = [
            "sort": pair.sort,
            "order": query.sortAscending ? pair.order : (pair.order == "asc" ? "desc" : "asc")
        ]
        if query.statuses.contains(.favorite) {
            params["favorite"] = "true"
        }
        if let genre = query.genres.first {
            params["genre"] = genre
        }
        if let year = query.years.first {
            params["year"] = String(year)
        }
        return params
    }

    private func applyLocalFilters(_ items: [MediaItem], query: CatalogBrowseQuery) -> [MediaItem] {
        items.filter { item in
            if query.statuses.contains(.played), !item.isPlayed { return false }
            if query.statuses.contains(.unplayed), item.isPlayed { return false }
            if query.statuses.contains(.favorite), !item.isFavorite { return false }
            if query.statuses.contains(.continueWatching), item.playbackPosition <= 5 { return false }
            if !query.genres.isEmpty, query.genres.isDisjoint(with: Set(item.genres)) { return false }
            if !query.years.isEmpty, let year = item.year, !query.years.contains(year) { return false }
            return true
        }
    }

    private func options(from items: [MediaItem]) async -> CatalogFilterOptions {
        CatalogFilterOptions(
            genres: items.flatMap(\.genres).uniquedChoices(),
            officialRatings: items.compactMap(\.officialRating).uniquedChoices(),
            years: items.compactMap(\.year).uniquedYearChoices()
        )
    }

    private func ignoringErrors<T>(_ work: () async throws -> T) async -> T? {
        try? await work()
    }

    func refreshItemMetadata(itemID: String, replaceImages: Bool) async throws {
        try await api.refreshItemMetadata(itemID: itemID)
    }

    func scanLibraries() async throws {
        let catalog = try await libraries()
        guard !catalog.isEmpty else {
            throw ZelefinError.server("No libraries to scan.")
        }
        var lastError: Error?
        for library in catalog {
            do {
                try await api.refreshLibraryMetadata(libraryID: library.id, full: false)
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }
}

private extension Sequence where Element == String {
    func uniquedChoices() -> [CatalogFilterChoice] {
        var seen = Set<String>()
        return compactMap { raw in
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return CatalogFilterChoice(id: name, name: name)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private extension Sequence where Element == Int {
    func uniquedYearChoices() -> [CatalogFilterChoice] {
        Array(Set(self)).sorted(by: >).map { CatalogFilterChoice(id: String($0), name: String($0)) }
    }
}
