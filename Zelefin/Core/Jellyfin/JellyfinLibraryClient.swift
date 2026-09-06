import Foundation
import JellyfinAPI

final class JellyfinLibraryClient: Sendable {
    private let client: JellyfinClient
    private let userID: String
    private let artwork: ArtworkURLBuilder
    private let streams: StreamURLBuilder

    init(client: JellyfinClient, userID: String) {
        self.client = client
        self.userID = userID
        self.artwork = ArtworkURLBuilder(client: client)
        self.streams = StreamURLBuilder(client: client)
    }

    func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL? {
        switch style {
        case .landscape, .replayLandscape:
            artwork.thumb(for: item, maxWidth: 640)
        case .portrait, .ranked:
            artwork.primary(for: item, maxHeight: 420)
        case .labeledPortrait:
            if item.kind == .genre {
                artwork.genreCover(for: item, maxWidth: 480)
            } else {
                artwork.primary(for: item, maxHeight: 420)
            }
        }
    }

    func primaryURL(for item: MediaItem, maxHeight: Int = 900) -> URL? {
        artwork.primary(for: item, maxHeight: maxHeight)
    }

    func backdropURL(for item: MediaItem, maxWidth: Int = 1400) -> URL? {
        artwork.backdrop(for: item, maxWidth: maxWidth)
    }

    func logoURL(for item: MediaItem, maxHeight: Int = 240) -> URL? {
        artwork.logo(for: item, maxHeight: maxHeight)
    }

    enum HomeChunk: Sendable {
        case continueWatching([MediaItem])
        case nextUp([MediaItem])
        case recentlyWatched([MediaItem])
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

    func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        await ignoringErrors { try await libraryHome() } ?? ([], [])
    }

    func collectionsSectionIgnoringErrors() async -> HomeSection? {
        await ignoringErrors { try await collectionsSection() } ?? nil
    }

    func genresSectionIgnoringErrors() async -> HomeSection? {
        await ignoringErrors { try await genresSection() } ?? nil
    }

    func items(genreID: String) async throws -> [MediaItem] {
        try await catalogItems(genreID: genreID, parentID: nil, include: [.movie, .series])
    }

    func items(parentID: String) async throws -> [MediaItem] {
        try await catalogItems(genreID: nil, parentID: parentID, include: [.movie, .series, .boxSet, .video])
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

    func items(in library: MediaLibrary) async throws -> [MediaItem] {
        let include: [BaseItemKind] = library.kind == .series ? [.series] : [.movie, .series, .boxSet]
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    startIndex: 0,
                    limit: 100,
                    isRecursive: true,
                    parentID: library.id,
                    fields: ItemMapper.listFields,
                    includeItemTypes: include,
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
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

    func similarItems(for itemID: String) async -> [MediaItem] {
        let result = try? await client.send(
            Paths.getSimilarItems(
                itemID: itemID,
                parameters: .init(
                    userID: userID,
                    limit: 16,
                    fields: ItemMapper.listFields
                )
            )
        ).value
        return (result?.items ?? [])
            .compactMap(ItemMapper.mediaItem(from:))
            .filter { $0.id != itemID && ($0.kind == .movie || $0.kind == .series) }
    }

    func collections(containing itemID: String) async -> [ItemCollectionMembership] {
        let boxSets = ((try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 80,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.boxSet],
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes
                )
            )
        ).value.items) ?? []).compactMap(ItemMapper.mediaItem(from:))

        return await withTaskGroup(of: ItemCollectionMembership?.self) { group in
            for boxSet in boxSets {
                group.addTask {
                    let members = (try? await self.catalogItems(
                        genreID: nil,
                        parentID: boxSet.id,
                        include: [.movie, .series, .video]
                    )) ?? []
                    guard members.contains(where: { $0.id == itemID }) else { return nil }
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

    func items(personID: String) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    startIndex: 0,
                    limit: 100,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series],
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    personIDs: [personID]
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
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
                    fields: ItemMapper.detailFields,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func episodes(seriesID: String, seasonID: String) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getEpisodes(
                seriesID: seriesID,
                parameters: .init(
                    userID: userID,
                    fields: ItemMapper.detailFields,
                    seasonID: seasonID,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
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
                    enableImageTypes: ItemMapper.listImageTypes
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil,
        allowDirectPlay: Bool = true
    ) async throws -> PlaybackPlan {
        try await fetchPlaybackPlan(
            for: item,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex,
            enableDirectPlay: allowDirectPlay
        )
    }

    private func fetchPlaybackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        enableDirectPlay: Bool
    ) async throws -> PlaybackPlan {
        let profile = AVDeviceProfileFactory.make()
        let body = PlaybackInfoDto(
            audioStreamIndex: audioIndex,
            deviceProfile: profile,
            enableDirectPlay: enableDirectPlay,
            enableDirectStream: true,
            enableTranscoding: true,
            isAutoOpenLiveStream: true,
            maxStreamingBitrate: AVDeviceProfileFactory.maxBitrate,
            startTimeTicks: TickClock.intTicks(from: item.playbackPosition),
            subtitleStreamIndex: subtitleIndex,
            userID: userID
        )

        let response = try await client.send(
            Paths.getPostedPlaybackInfo(
                itemID: item.id,
                parameters: .init(
                    userID: userID,
                    maxStreamingBitrate: AVDeviceProfileFactory.maxBitrate,
                    startTimeTicks: TickClock.intTicks(from: item.playbackPosition),
                    audioStreamIndex: audioIndex,
                    subtitleStreamIndex: subtitleIndex,
                    isAutoOpenLiveStream: true,
                    enableDirectPlay: enableDirectPlay,
                    enableDirectStream: true,
                    enableTranscoding: true
                ),
                body
            )
        ).value

        guard let source = response.mediaSources?.first else {
            throw ZelefinError.emptyPlaybackSources
        }

        let url = try streams.url(itemID: item.id, source: source)
        let method = ItemMapper.playbackMethod(from: source)
        let streams = source.mediaStreams ?? []

        return PlaybackPlan(
            item: item,
            streamURL: url,
            playSessionID: response.playSessionID,
            mediaSourceID: source.id,
            method: method,
            videoRange: ItemMapper.videoRange(from: streams),
            audioFormat: ItemMapper.audioFormat(from: streams),
            startTime: item.playbackPosition,
            byteSize: source.size.map(Int64.init),
            extraHTTPHeaders: source.requiredHTTPHeaders ?? [:],
            audioTracks: ItemMapper.tracks(from: streams, kind: .audio),
            subtitleTracks: ItemMapper.tracks(from: streams, kind: .subtitle)
        )
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
                    enableImageTypes: ItemMapper.listImageTypes
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
                    enableUserData: true
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
                    enableImageTypes: ItemMapper.listImageTypes
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
                    enableImageTypes: ItemMapper.listImageTypes
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
                    enableImageTypes: ItemMapper.listImageTypes
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
            items: await fillMissingGenreCovers(assigned)
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
                    enableImageTypes: ItemMapper.listImageTypes
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    private func fillMissingGenreCovers(_ genres: [MediaItem]) async -> [MediaItem] {
        let missing = genres.enumerated().filter { $0.element.imageItemID == nil }
        guard !missing.isEmpty else { return genres }

        return await withTaskGroup(of: (Int, MediaItem).self) { group in
            for (index, genre) in missing {
                group.addTask {
                    if let cover = try? await self.randomItemInGenre(genre.id) {
                        return (index, genre.withCover(from: cover))
                    }
                    return (index, genre)
                }
            }
            var filled = genres
            for await (index, item) in group {
                filled[index] = item
            }
            return filled
        }
    }

    private func randomItemInGenre(_ genreID: String) async throws -> MediaItem? {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 12,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series],
                    sortBy: [.random],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    genreIDs: [genreID]
                )
            )
        ).value
        let items = (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
        return items.first(where: \.hasGenreCoverArt) ?? items.first
    }

    private func catalogItems(genreID: String?, parentID: String?, include: [BaseItemKind]) async throws -> [MediaItem] {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    startIndex: 0,
                    limit: 100,
                    isRecursive: true,
                    parentID: parentID,
                    fields: ItemMapper.listFields,
                    includeItemTypes: include,
                    sortBy: [.sortName],
                    enableUserData: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    genreIDs: genreID.map { [$0] }
                )
            )
        ).value
        return (result.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    private func includeTypes(for library: MediaLibrary) -> [BaseItemKind] {
        switch library.libraryKind {
        case .movies: [.movie]
        case .shows: [.series]
        case .homeVideos: [.video, .movie]
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

    private func latestMedia(include: [BaseItemKind]?, parentID: String?) async throws -> [MediaItem] {
        try await client.send(
            Paths.getLatestMedia(
                parameters: .init(
                    userID: userID,
                    parentID: parentID,
                    fields: ItemMapper.homeFields,
                    includeItemTypes: include,
                    enableImages: true,
                    enableImageTypes: ItemMapper.listImageTypes,
                    enableUserData: true,
                    limit: 12,
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
