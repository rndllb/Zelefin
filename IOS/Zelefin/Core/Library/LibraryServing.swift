import Foundation

/// Catalog, artwork, and playback that Home, Library, Detail, Search, and Player share.
/// Live TV, SyncPlay, remote sessions, and admin stay on `JellyfinLibraryClient`.
struct ServerCatalogCounts: Equatable, Sendable {
    var movies: Int
    var shows: Int
    var episodes: Int
}

struct LibraryRoomCounts: Equatable, Sendable {
    var movies: Int
    var shows: Int
    var episodes: Int

    var caption: String? {
        let parts = [
            Self.phrase(movies, singular: "movie", plural: "movies"),
            Self.phrase(shows, singular: "show", plural: "shows"),
            Self.phrase(episodes, singular: "episode", plural: "episodes")
        ].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func phrase(_ value: Int, singular: String, plural: String) -> String? {
        guard value > 0 else { return nil }
        let number = value.formatted(.number.grouping(.automatic))
        return "\(number) \(value == 1 ? singular : plural)"
    }
}

protocol LibraryServing: AnyObject, Sendable {
    func updateServerVersion(_ raw: String?)

    func artworkURL(for item: MediaItem, style: HomeSection.Style) -> URL?
    func programStillURL(for item: MediaItem, channel: MediaItem?) -> URL?
    func primaryURL(for item: MediaItem, maxHeight: Int) -> URL?
    func backdropURL(for item: MediaItem, maxWidth: Int) -> URL?
    func logoURL(for item: MediaItem, maxHeight: Int) -> URL?
    func userAvatarURL(userID: String, tag: String?) -> URL?
    func personImageURL(id: String, tag: String?, maxHeight: Int) -> URL?
    func searchHitImageURL(_ hit: LibrarySearchHit) -> URL?
    func cacheableArtworkURLs(for item: MediaItem) -> [URL]
    func chapterImageURL(itemID: String, index: Int, tag: String?) -> URL?
    func trickplayTileURL(itemID: String, info: TrickplayInfo, time: TimeInterval) -> URL?

    func resumeItemsIgnoringErrors() async -> [MediaItem]
    func nextUpItemsIgnoringErrors() async -> [MediaItem]
    func recentlyWatchedIgnoringErrors() async -> [MediaItem]
    func featuredItemsIgnoringErrors() async -> [MediaItem]
    func libraryHomeIgnoringErrors() async -> (libraries: [MediaLibrary], sections: [HomeSection])
    func collectionsSectionIgnoringErrors() async -> HomeSection?
    func genresSectionIgnoringErrors() async -> HomeSection?
    func movieRecommendationsIgnoringErrors() async -> [HomeSection]
    func upcomingEpisodesIgnoringErrors() async -> [MediaItem]

    func libraries() async throws -> [MediaLibrary]
    func tmdbCatalog() async -> JellyfinTmdbCatalog
    func previewItems(in library: MediaLibrary, limit: Int) async -> [MediaItem]

    func items(
        in library: MediaLibrary,
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async throws -> [MediaItem]
    func items(
        inLibraries libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async -> [MediaItem]
    func browseCatalog(
        kind: LibraryKind,
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler?
    ) async -> [MediaItem]
    func catalogCount(kind: LibraryKind, libraries: [MediaLibrary]) async -> Int
    func serverCatalogCounts() async -> ServerCatalogCounts
    func roomCounts(for library: MediaLibrary) async -> LibraryRoomCounts
    func catalogFilterOptions(for library: MediaLibrary) async -> CatalogFilterOptions
    func catalogFilterOptions(for kind: LibraryKind) async -> CatalogFilterOptions
    func mixedCatalogFilterOptions(parentID: String?) async -> CatalogFilterOptions
    func collectionFilterOptions(parentID: String) async -> CatalogFilterOptions
    func items(genreID: String, genreName: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func items(genreID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func items(parentID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func items(personID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func items(studioID: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func collectionItems(query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem]
    func boxSets() async -> [MediaItem]

    func item(id: String) async throws -> MediaItem
    func titleMoreInfo(for item: MediaItem) async -> TitleMoreInfo
    func trailers(for item: MediaItem) async -> [TitleTrailer]
    func similarItems(for item: MediaItem) async -> [MediaItem]
    func collections(containing itemID: String) async -> [ItemCollectionMembership]
    func credits(for item: MediaItem) async -> [CreditPerson]
    func specialFeatures(for itemID: String) async -> [TitleExtra]
    func themeVideos(for itemID: String) async -> [TitleExtra]
    func cinemaIntros(for itemID: String) async -> [MediaItem]
    func seasons(seriesID: String) async throws -> [MediaItem]
    func episodes(seriesID: String, seasonID: String?) async throws -> [MediaItem]
    func nextEpisode(after item: MediaItem) async -> MediaItem?
    func search(term: String) async throws -> [MediaItem]
    func searchLibrary(_ term: String) async throws -> [LibrarySearchHit]
    func person(id: String) async -> CreditPerson?
    func mediaVersions(for itemID: String) async -> [MediaVersion]

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        allowDirectPlay: Bool,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan
    func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack])
    func originalFileDownloadURL(for itemID: String) throws -> URL
    func prepareDownloadAsset(for item: MediaItem, plan: PlaybackPlan) async throws -> DownloadAsset
    func finalizeServerDownload(id: String) async
    func deleteServerDownload(id: String) async
    func downloadsAvailable() async -> Bool
    func measureStreamingBitrate(
        size: Int,
        timeout: TimeInterval,
        transport: NetworkTransport
    ) async -> BitrateProbeResult?

    func markPlayed(itemID: String) async throws
    func markUnplayed(itemID: String) async throws
    func markFavorite(itemID: String, isFavorite: Bool) async throws -> Bool
    func setLikes(itemID: String, likes: Bool?) async throws -> Bool?

    func playlists() async throws -> [MediaItem]
    func playlistEntries(playlistID: String) async throws -> [PlaylistEntry]
    func createPlaylist(name: String, itemIDs: [String]) async throws
    func addToPlaylist(playlistID: String, itemIDs: [String]) async throws
    func removeFromPlaylist(playlistID: String, entryIDs: [String]) async throws
    func addToCollection(collectionID: String, itemIDs: [String]) async throws
    func removeFromCollection(collectionID: String, itemIDs: [String]) async throws
    func createCollection(name: String, itemIDs: [String]) async throws
    func displayPreferenceCustomPrefs() async throws -> [String: String]
    func updateDisplayPreferenceCustomPrefs(_ prefs: [String: String]) async throws
    func refreshItemMetadata(itemID: String, replaceImages: Bool) async throws
    func deleteLibraryItem(itemID: String) async throws
    func remoteArtwork(for itemID: String, kind: RemoteArtworkKind) async throws -> [RemoteImageChoice]
    func downloadRemoteArtwork(itemID: String, kind: RemoteArtworkKind, imageURL: URL) async throws
    func scanLibraries() async throws
    func playOnSession(sessionID: String, itemIDs: [String], startPosition: TimeInterval?) async throws
    func syncPlayReady(isPlaying: Bool, playlistItemID: String?, position: TimeInterval) async throws
    func syncPlaySetQueue(itemIDs: [String], startPosition: TimeInterval) async throws
    func syncPlayCreateGroup(name: String) async throws -> SyncPlayGroupInfo
    func syncPlayJoinGroup(id: String) async throws
    func syncPlayLeaveGroup() async throws
    func syncPlayPause() async throws
    func syncPlayUnpause() async throws
    func syncPlaySeek(to seconds: TimeInterval) async throws
    func syncPlayStop() async throws
    func syncPlayGroups() async throws -> [SyncPlayGroupInfo]
}

extension LibraryServing {
    func programStillURL(for item: MediaItem) -> URL? {
        programStillURL(for: item, channel: nil)
    }

    func primaryURL(for item: MediaItem) -> URL? {
        primaryURL(for: item, maxHeight: ArtworkURLBuilder.posterMaxHeight)
    }

    func backdropURL(for item: MediaItem) -> URL? {
        backdropURL(for: item, maxWidth: 1400)
    }

    func logoURL(for item: MediaItem) -> URL? {
        logoURL(for: item, maxHeight: 240)
    }

    func personImageURL(id: String, tag: String?) -> URL? {
        personImageURL(id: id, tag: tag, maxHeight: 360)
    }

    func items(in library: MediaLibrary) async throws -> [MediaItem] {
        try await items(in: library, query: .default, onPage: nil)
    }

    func previewItems(in library: MediaLibrary, limit: Int) async -> [MediaItem] {
        Array(((try? await items(in: library)) ?? []).prefix(limit))
    }

    func browseCatalog(kind: LibraryKind, libraries: [MediaLibrary]) async -> [MediaItem] {
        await browseCatalog(kind: kind, libraries: libraries, query: .default, onPage: nil)
    }

    func mixedCatalogFilterOptions() async -> CatalogFilterOptions {
        await mixedCatalogFilterOptions(parentID: nil)
    }

    func items(genreID: String, genreName: String, query: CatalogBrowseQuery, onPage: CatalogPageHandler?) async throws -> [MediaItem] {
        try await items(genreID: genreID, query: query, onPage: onPage)
    }

    func items(genreID: String) async throws -> [MediaItem] {
        try await items(genreID: genreID, query: .default, onPage: nil)
    }

    func items(parentID: String) async throws -> [MediaItem] {
        try await items(parentID: parentID, query: .default, onPage: nil)
    }

    func items(personID: String) async throws -> [MediaItem] {
        try await items(personID: personID, query: .default, onPage: nil)
    }

    func items(studioID: String) async throws -> [MediaItem] {
        try await items(studioID: studioID, query: .default, onPage: nil)
    }

    func episodes(seriesID: String) async throws -> [MediaItem] {
        try await episodes(seriesID: seriesID, seasonID: nil)
    }

    func playbackPlan(for item: MediaItem) async throws -> PlaybackPlan {
        try await playbackPlan(
            for: item,
            audioIndex: nil,
            subtitleIndex: nil,
            allowDirectPlay: true,
            maxBitrate: nil,
            startTime: nil,
            mediaSourceID: nil
        )
    }

    func playbackPlan(
        for item: MediaItem,
        audioIndex: Int?,
        subtitleIndex: Int?,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan {
        try await playbackPlan(
            for: item,
            audioIndex: audioIndex,
            subtitleIndex: subtitleIndex,
            allowDirectPlay: true,
            maxBitrate: maxBitrate,
            startTime: startTime,
            mediaSourceID: mediaSourceID
        )
    }

    func playbackPlan(
        for item: MediaItem,
        allowDirectPlay: Bool,
        maxBitrate: Int?,
        startTime: TimeInterval?,
        mediaSourceID: String?
    ) async throws -> PlaybackPlan {
        try await playbackPlan(
            for: item,
            audioIndex: nil,
            subtitleIndex: nil,
            allowDirectPlay: allowDirectPlay,
            maxBitrate: maxBitrate,
            startTime: startTime,
            mediaSourceID: mediaSourceID
        )
    }

    func refreshItemMetadata(itemID: String) async throws {
        try await refreshItemMetadata(itemID: itemID, replaceImages: false)
    }

    func playOnSession(sessionID: String, itemIDs: [String]) async throws {
        try await playOnSession(sessionID: sessionID, itemIDs: itemIDs, startPosition: nil)
    }

    func syncPlaySetQueue(itemIDs: [String]) async throws {
        try await syncPlaySetQueue(itemIDs: itemIDs, startPosition: 0)
    }
}

enum LibraryServingDefaults {
    static var unavailable: ZelefinError {
        .server("This action is not available on this server.")
    }
}

/// The concrete bytes source for an offline download: a URL plus the request
/// headers needed to fetch it, and (for backends that track downloads
/// server-side, like Silo) the id of the managed row to clean up on removal.
struct DownloadAsset: Sendable {
    let url: URL
    let headers: [String: String]
    let serverDownloadID: String?
}

extension LibraryServing {
    func streamTracks(for itemID: String) async -> (audio: [MediaTrack], subtitles: [MediaTrack]) {
        ([], [])
    }

    func originalFileDownloadURL(for itemID: String) throws -> URL {
        throw LibraryServingDefaults.unavailable
    }

    /// Default: a single direct file download (Jellyfin), fetched straight from
    /// the server's original-file URL with no server-side bookkeeping.
    func prepareDownloadAsset(for item: MediaItem, plan: PlaybackPlan) async throws -> DownloadAsset {
        let url = try originalFileDownloadURL(for: item.id)
        return DownloadAsset(
            url: url,
            headers: PlaybackHTTPHeaders.fields(for: url),
            serverDownloadID: nil
        )
    }

    func finalizeServerDownload(id: String) async {}
    func deleteServerDownload(id: String) async {}
    func downloadsAvailable() async -> Bool { true }

    func measureStreamingBitrate(
        size: Int,
        timeout: TimeInterval,
        transport: NetworkTransport
    ) async -> BitrateProbeResult? {
        nil
    }

    func setLikes(itemID: String, likes: Bool?) async throws -> Bool? {
        throw LibraryServingDefaults.unavailable
    }

    func playlists() async throws -> [MediaItem] { [] }

    func playlistEntries(playlistID: String) async throws -> [PlaylistEntry] { [] }

    func createPlaylist(name: String, itemIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func addToPlaylist(playlistID: String, itemIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func removeFromPlaylist(playlistID: String, entryIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func addToCollection(collectionID: String, itemIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func removeFromCollection(collectionID: String, itemIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func createCollection(name: String, itemIDs: [String]) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func displayPreferenceCustomPrefs() async throws -> [String: String] { [:] }

    func updateDisplayPreferenceCustomPrefs(_ prefs: [String: String]) async throws {}

    func refreshItemMetadata(itemID: String, replaceImages: Bool) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func deleteLibraryItem(itemID: String) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func remoteArtwork(for itemID: String, kind: RemoteArtworkKind) async throws -> [RemoteImageChoice] { [] }

    func downloadRemoteArtwork(itemID: String, kind: RemoteArtworkKind, imageURL: URL) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func scanLibraries() async throws {
        throw LibraryServingDefaults.unavailable
    }

    func playOnSession(sessionID: String, itemIDs: [String], startPosition: TimeInterval?) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayReady(isPlaying: Bool, playlistItemID: String?, position: TimeInterval) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlaySetQueue(itemIDs: [String], startPosition: TimeInterval) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayCreateGroup(name: String) async throws -> SyncPlayGroupInfo {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayJoinGroup(id: String) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayLeaveGroup() async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayPause() async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayUnpause() async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlaySeek(to seconds: TimeInterval) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayStop() async throws {
        throw LibraryServingDefaults.unavailable
    }

    func syncPlayGroups() async throws -> [SyncPlayGroupInfo] { [] }
}
