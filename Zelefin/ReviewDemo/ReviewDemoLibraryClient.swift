import Foundation
import JellyfinAPI

final class ReviewDemoLibraryClient: JellyfinLibraryClient, @unchecked Sendable {
    override func updateServerVersion(_ raw: String?) {}

    override func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL? {
        switch style {
        case .landscape, .replayLandscape:
            ReviewDemoCatalog.artworkURL(for: item, portrait: false)
        case .portrait, .ranked, .labeledPortrait:
            ReviewDemoCatalog.artworkURL(for: item, portrait: true)
        }
    }

    override func primaryURL(for item: MediaItem, maxHeight: Int = ArtworkURLBuilder.posterMaxHeight) -> URL? {
        ReviewDemoCatalog.artworkURL(for: item, portrait: true)
    }

    override func backdropURL(for item: MediaItem, maxWidth: Int = 1400) -> URL? {
        ReviewDemoCatalog.artworkURL(for: item, portrait: false)
    }

    override func logoURL(for item: MediaItem, maxHeight: Int = 240) -> URL? {
        nil
    }

    override func userAvatarURL(userID: String, tag: String?) -> URL? {
        nil
    }

    override func personImageURL(id: String, tag: String?, maxHeight: Int = 360) -> URL? {
        URL(string: "https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=360&h=360&auto=format&fit=crop&q=80")
    }

    override func resumeItemsIgnoringErrors() async -> [MediaItem] {
        ReviewDemoCatalog.continueWatching
    }

    override func nextUpItemsIgnoringErrors() async -> [MediaItem] {
        ReviewDemoCatalog.nextUp
    }

    override func recentlyWatchedIgnoringErrors() async -> [MediaItem] {
        ReviewDemoCatalog.recentlyWatched
    }

    override func featuredItemsIgnoringErrors() async -> [MediaItem] {
        ReviewDemoCatalog.featured
    }

    override func markPlayed(itemID: String) async throws {}

    override func markUnplayed(itemID: String) async throws {}

    override func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection]) {
        (
            ReviewDemoCatalog.libraries,
            [ReviewDemoCatalog.recentlyAddedMovies, ReviewDemoCatalog.recentlyAddedShows]
        )
    }

    override func collectionsSectionIgnoringErrors() async -> HomeSection? {
        ReviewDemoCatalog.collectionsSection
    }

    override func genresSectionIgnoringErrors() async -> HomeSection? {
        ReviewDemoCatalog.genresSection
    }

    override func items(
        genreID: String,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        let items = ReviewDemoCatalog.items(matching: query, from: ReviewDemoCatalog.items(genreID: genreID))
        await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
        return items
    }

    override func items(
        parentID: String,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        let items = ReviewDemoCatalog.items(matching: query, from: ReviewDemoCatalog.items(parentID: parentID))
        await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
        return items
    }

    override func catalogFilterOptions(
        parentID: String?,
        include: [BaseItemKind]
    ) async -> CatalogFilterOptions {
        ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.movies + ReviewDemoCatalog.shows)
    }

    override func mixedCatalogFilterOptions(parentID: String? = nil) async -> CatalogFilterOptions {
        await catalogFilterOptions(parentID: parentID, include: mixedCatalogFilterTypes())
    }

    override func collectionFilterOptions(parentID: String) async -> CatalogFilterOptions {
        ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.items(parentID: parentID))
    }

    override func catalogFilterOptions(for library: MediaLibrary) async -> CatalogFilterOptions {
        ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.items(in: library))
    }

    override func catalogFilterOptions(for kind: LibraryKind) async -> CatalogFilterOptions {
        switch kind {
        case .movies: ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.movies)
        case .shows: ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.shows)
        case .collections: ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.collections)
        case .favorites: ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.movies + ReviewDemoCatalog.shows)
        default: ReviewDemoCatalog.filterOptions(from: ReviewDemoCatalog.movies + ReviewDemoCatalog.shows)
        }
    }

    override func libraries() async throws -> [MediaLibrary] {
        ReviewDemoCatalog.libraries
    }

    override func tmdbCatalog() async -> JellyfinTmdbCatalog {
        JellyfinTmdbCatalog()
    }

    override func items(
        in library: MediaLibrary,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        let items = ReviewDemoCatalog.items(matching: query, from: ReviewDemoCatalog.items(in: library))
        await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
        return items
    }

    override func collectionItems(
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        let items = ReviewDemoCatalog.items(matching: query, from: ReviewDemoCatalog.collections)
        await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
        return items
    }

    override func browseCatalog(
        kind: LibraryKind,
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async -> [MediaItem] {
        if kind == .favorites {
            let items = ReviewDemoCatalog.items(
                matching: query.applyingFavoriteFilter(),
                from: ReviewDemoCatalog.movies + ReviewDemoCatalog.shows
            )
            await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
            return items
        }
        return await super.browseCatalog(kind: kind, libraries: libraries, query: query, onPage: onPage)
    }

    override func catalogCount(kind: LibraryKind, libraries: [MediaLibrary]) async -> Int {
        await browseCatalog(kind: kind, libraries: libraries).count
    }

    override func item(id: String) async throws -> MediaItem {
        guard let item = ReviewDemoCatalog.item(id: id) else {
            throw ZelefinError.missingItemID
        }
        return item
    }

    override func trailers(for item: MediaItem) async -> [TitleTrailer] {
        ReviewDemoCatalog.trailers(for: item.id)
    }

    override func similarItems(for item: MediaItem) async -> [MediaItem] {
        ReviewDemoCatalog.related(to: item)
    }

    override func collections(containing itemID: String) async -> [ItemCollectionMembership] {
        ReviewDemoCatalog.collectionMembers.compactMap { id, members in
            guard members.contains(where: { $0.id == itemID }) else { return nil }
            guard let collection = ReviewDemoCatalog.item(id: id) else { return nil }
            return ItemCollectionMembership(collection: collection, items: members)
        }
    }

    override func items(
        personID: String,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        let items = ReviewDemoCatalog.items(matching: query, from: ReviewDemoCatalog.movies)
        await onPage?(CatalogPageUpdate(items: items, totalCount: items.count))
        return items
    }

    override func titleMoreInfo(for item: MediaItem) async -> TitleMoreInfo {
        TitleMoreInfoMapper.info(from: item)
    }

    override func credits(for item: MediaItem) async -> [CreditPerson] {
        ReviewDemoCatalog.credits
    }

    override func credits(for itemID: String, from dto: BaseItemDto) async -> [CreditPerson] {
        ReviewDemoCatalog.credits
    }

    override func seasons(seriesID: String) async throws -> [MediaItem] {
        guard seriesID == ReviewDemoCatalog.stationNorth.id else { return [] }
        return [ReviewDemoCatalog.season]
    }

    override func episodes(seriesID: String, seasonID: String? = nil) async throws -> [MediaItem] {
        guard seriesID == ReviewDemoCatalog.stationNorth.id else { return [] }
        return ReviewDemoCatalog.episodes
    }

    override func nextEpisode(after item: MediaItem) async -> MediaItem? {
        let episodes = ReviewDemoCatalog.episodes
        guard let index = episodes.firstIndex(where: { $0.id == item.id }) else { return nil }
        let next = index + 1
        guard episodes.indices.contains(next) else { return nil }
        return episodes[next]
    }

    override func search(term: String) async throws -> [MediaItem] {
        ReviewDemoCatalog.search(term: term)
    }

    override func searchLibrary(_ term: String) async throws -> [LibrarySearchHit] {
        try await search(term: term).map { item in
            LibrarySearchHit(
                id: item.id,
                name: item.name,
                kind: .title(item.kind),
                subtitle: item.searchListSubtitle,
                year: item.year,
                imageTag: item.primaryImageTag
            )
        }
    }

    override func markFavorite(itemID: String, isFavorite: Bool) async throws -> Bool {
        isFavorite
    }

    override func setLikes(itemID: String, likes: Bool?) async throws -> Bool? {
        likes
    }

    override func specialFeatures(for itemID: String) async -> [TitleExtra] {
        []
    }

    override func themeVideos(for itemID: String) async -> [TitleExtra] {
        []
    }

    override func cinemaIntros(for itemID: String) async -> [MediaItem] {
        []
    }

    override func movieRecommendationsIgnoringErrors() async -> [HomeSection] {
        []
    }

    override func upcomingEpisodesIgnoringErrors() async -> [MediaItem] {
        []
    }

    override func mediaVersions(for itemID: String) async -> [MediaVersion] {
        []
    }

    override func person(id: String) async -> CreditPerson? {
        ReviewDemoCatalog.credits.first { $0.id == id }
    }

    override func items(
        studioID: String,
        query: CatalogBrowseQuery = .default,
        onPage: CatalogPageHandler? = nil
    ) async throws -> [MediaItem] {
        try await items(personID: studioID, query: query, onPage: onPage)
    }

    override func boxSets() async -> [MediaItem] {
        ReviewDemoCatalog.collectionsSection.items
    }

    override func addToCollection(collectionID: String, itemIDs: [String]) async throws {}

    override func removeFromCollection(collectionID: String, itemIDs: [String]) async throws {}

    override func createCollection(name: String, itemIDs: [String]) async throws {}

    override func playOnSession(sessionID: String, itemIDs: [String], startPosition: TimeInterval? = nil) async throws {}

    override func originalFileDownloadURL(for itemID: String) throws -> URL {
        throw ZelefinError.server("Downloads are not available in the App Review demo.")
    }

    override func measureStreamingBitrate(
        size: Int,
        timeout: TimeInterval,
        transport: NetworkTransport
    ) async -> BitrateProbeResult? {
        BitrateProbeResult(
            bitsPerSecond: 40_000_000,
            bytes: size,
            elapsed: 0.4,
            transport: transport,
            measuredAt: Date()
        )
    }

    override func playbackPlan(
        for item: MediaItem,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil,
        allowDirectPlay: Bool = true,
        maxBitrate: Int? = nil,
        startTime: TimeInterval? = nil,
        mediaSourceID: String? = nil
    ) async throws -> PlaybackPlan {
        let audio = MediaTrack(
            id: 1,
            kind: .audio,
            language: "eng",
            title: "English",
            codec: "aac",
            isSelected: true,
            isDefault: true
        )
        return PlaybackPlan(
            item: item,
            streamURL: ReviewDemoCatalog.sampleStreamURL,
            playSessionID: ReviewDemo.playSessionID,
            mediaSourceID: "review-demo-source",
            method: .directPlay,
            container: "mp4",
            videoCodec: "h264",
            videoRange: item.videoRange,
            audioFormat: item.audioFormat,
            startTime: startTime ?? item.playbackPosition,
            byteSize: nil,
            extraHTTPHeaders: [:],
            audioTracks: [audio],
            subtitleTracks: []
        )
    }

    override func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        (
            [
                MediaTrack(
                    id: 1,
                    kind: .audio,
                    language: "eng",
                    title: "English",
                    codec: "aac",
                    isSelected: true,
                    isDefault: true
                )
            ],
            []
        )
    }

    override func playbackSessions(activeWithinSeconds: Int = 960) async throws -> [PlaybackSession] {
        []
    }

    override func sendPlaystate(
        sessionID: String,
        command: PlaystateCommand,
        seekPosition: TimeInterval? = nil
    ) async throws {}

    override func sendSessionCommand(sessionID: String, command: GeneralCommandType) async throws {}

    override func scheduledTasks() async throws -> [ScheduledTask] {
        []
    }

    override func startScheduledTask(id: String) async throws {}

    override func stopScheduledTask(id: String) async throws {}

    override func activityLog(limit: Int = 80) async throws -> [ActivityLogItem] { [] }

    override func serverBackups() async throws -> [ServerBackup] { [] }

    override func createServerBackup() async throws -> ServerBackup {
        throw ZelefinError.server("Backups are not available in the App Review demo.")
    }

    override func restoreServerBackup(_ backup: ServerBackup) async throws {}

    override func scanLibraries() async throws {}

    override func refreshItemMetadata(itemID: String, replaceImages: Bool = false) async throws {}

    override func deleteLibraryItem(itemID: String) async throws {}

    override func remoteArtwork(for itemID: String) async throws -> [RemoteImageChoice] { [] }

    override func downloadRemoteArtwork(itemID: String, imageURL: URL) async throws {}

    override func serverBranding() async throws -> ServerBranding {
        ServerBranding(loginDisclaimer: "", customCSS: "", splashscreenEnabled: false)
    }

    override func updateServerBranding(_ branding: ServerBranding) async throws {}

    override func uploadSplashscreen(_ imageData: Data) async throws {}

    override func deleteSplashscreen() async throws {}

    override func displayPreferenceCustomPrefs() async throws -> [String: String] { [:] }

    override func updateDisplayPreferenceCustomPrefs(_ prefs: [String: String]) async throws {}

    override func playlists() async throws -> [MediaItem] { [] }

    override func playlistEntries(playlistID: String) async throws -> [PlaylistEntry] { [] }

    override func createPlaylist(name: String, itemIDs: [String]) async throws {}

    override func addToPlaylist(playlistID: String, itemIDs: [String]) async throws {}

    override func removeFromPlaylist(playlistID: String, entryIDs: [String]) async throws {}

    override func liveTVInfoEnabled() async throws -> Bool { true }

    override func liveTVChannels() async throws -> [LiveChannel] {
        ReviewDemoCatalog.liveTVChannels()
    }

    override func liveTVRecordings(isInProgress: Bool? = nil, limit: Int = 80) async throws -> [LiveTVRecording] {
        ReviewDemoCatalog.liveTVRecordings(isInProgress: isInProgress)
    }

    override func deleteLiveTVRecording(id: String) async throws {}

    override func liveTVPrograms(
        channelIDs: [String]? = nil,
        isAiring: Bool? = nil,
        hasAired: Bool? = nil,
        minStartDate: Date? = nil,
        maxStartDate: Date? = nil,
        filter: LiveTVProgramFilter? = nil,
        limit: Int = 80
    ) async throws -> [LiveProgram] {
        ReviewDemoCatalog.liveTVPrograms(filter: filter)
    }

    override func liveTVRecommendedPrograms(filter: LiveTVProgramFilter? = nil, isAiring: Bool = true, limit: Int = 40) async throws -> [LiveProgram] {
        ReviewDemoCatalog.liveTVPrograms(filter: filter)
    }

    override func liveTVProgram(id: String) async throws -> LiveProgram {
        guard let program = ReviewDemoCatalog.liveTVPrograms().first(where: { $0.id == id }) else {
            throw ZelefinError.server("This program is no longer in the guide.")
        }
        return program
    }

    override func liveTVGuide(channelIDs: [String], from start: Date, to end: Date) async throws -> [LiveProgram] {
        ReviewDemoCatalog.liveTVPrograms().filter { channelIDs.contains($0.channel.id) }
    }

    override func syncPlayGroups() async throws -> [SyncPlayGroupInfo] { [] }

    override func syncPlayCreateGroup(name: String) async throws -> SyncPlayGroupInfo {
        SyncPlayGroupInfo(id: "demo", name: name, participants: [], stateLabel: "Idle")
    }

    override func syncPlayJoinGroup(id: String) async throws {}

    override func syncPlayLeaveGroup() async throws {}

    override func syncPlaySetQueue(itemIDs: [String], startPosition: TimeInterval = 0) async throws {}

    override func syncPlayPause() async throws {}

    override func syncPlayUnpause() async throws {}

    override func syncPlaySeek(to seconds: TimeInterval) async throws {}

    override func syncPlayStop() async throws {}

    override func syncPlayReady(isPlaying: Bool, playlistItemID: String?, position: TimeInterval) async throws {}
}
