import Foundation
import JellyfinAPI

extension EmbyLibraryClient {
    static let watchlistPlaylistName = "Watchlist"

    // MARK: Likes, playlists, the Watchlist, and collections

    func setLikes(itemID: String, likes: Bool?) async throws -> Bool? {
        let path = "/Users/\(userID)/Items/\(itemID)/Rating"
        guard let likes else {
            _ = try await api.data("DELETE", path)
            return nil
        }
        let data = try await api.data("POST", path, query: [("Likes", likes ? "true" : "false")])
        return (try? EmbyJSON.decode(UserItemDataDto.self, from: data))?.isLikes ?? likes
    }

    func playlists() async throws -> [MediaItem] {
        try await userItems([
            ("Limit", "80"),
            ("Recursive", "true"),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", "Playlist"),
            ("SortBy", "SortName")
        ])
    }

    func playlistEntries(playlistID: String) async throws -> [PlaylistEntry] {
        try await dtos(
            "/Playlists/\(playlistID)/Items",
            query: [
                ("UserId", userID),
                ("Fields", EmbyFields.list),
                ("EnableImages", "true"),
                ("EnableUserData", "true"),
                ("EnableImageTypes", EmbyFields.imageTypes)
            ]
        ).compactMap { dto in
            guard let item = ItemMapper.mediaItem(from: dto) else { return nil }
            return PlaylistEntry(id: dto.playlistItemID ?? item.id, entryID: dto.playlistItemID, item: item)
        }
    }

    func createPlaylist(name: String, itemIDs: [String]) async throws {
        _ = try await createPlaylistID(name: name, itemIDs: itemIDs)
    }

    @discardableResult
    func createPlaylistID(name: String, itemIDs: [String]) async throws -> String {
        let data = try await api.data(
            "POST",
            "/Playlists",
            query: [
                ("Name", name),
                ("Ids", itemIDs.isEmpty ? nil : itemIDs.joined(separator: ",")),
                ("MediaType", "Video")
            ]
        )
        guard let id = EmbyJSON.object(from: data).flatMap({ Self.string($0["Id"]) }) else {
            throw ZelefinError.server("Emby did not create the playlist.")
        }
        return id
    }

    func addToPlaylist(playlistID: String, itemIDs: [String]) async throws {
        try await api.send(
            "POST",
            "/Playlists/\(playlistID)/Items",
            query: [("Ids", itemIDs.joined(separator: ",")), ("UserId", userID)]
        )
    }

    func removeFromPlaylist(playlistID: String, entryIDs: [String]) async throws {
        try await api.send("DELETE", "/Playlists/\(playlistID)/Items", query: [("EntryIds", entryIDs.joined(separator: ","))])
    }

    /// Looking only: the Watchlist playlist is created the first time something is added.
    func watchlistPlaylistID(create: Bool) async throws -> String? {
        let found = try await dtos(
            "/Users/\(userID)/Items",
            query: [
                ("Limit", "20"),
                ("Recursive", "true"),
                ("SearchTerm", Self.watchlistPlaylistName),
                ("IncludeItemTypes", "Playlist")
            ]
        )
        if let existing = found.first(where: {
            $0.name?.caseInsensitiveCompare(Self.watchlistPlaylistName) == .orderedSame
        })?.id {
            return existing
        }
        guard create else { return nil }
        return try await createPlaylistID(name: Self.watchlistPlaylistName, itemIDs: [])
    }

    func watchlistItems() async -> [MediaItem] {
        guard let playlist = try? await watchlistPlaylistID(create: false) else { return [] }
        return ((try? await playlistEntries(playlistID: playlist)) ?? []).map { $0.item.withWatchlisted(true) }
    }

    func setWatchlisted(itemID: String, watchlisted: Bool) async throws {
        if watchlisted {
            guard let playlist = try await watchlistPlaylistID(create: true) else { return }
            try await addToPlaylist(playlistID: playlist, itemIDs: [itemID])
            return
        }
        guard let playlist = try await watchlistPlaylistID(create: false) else { return }
        let ids = try await playlistEntries(playlistID: playlist).filter { $0.item.id == itemID }.map(\.id)
        if !ids.isEmpty {
            try await removeFromPlaylist(playlistID: playlist, entryIDs: ids)
        }
    }

    func addToCollection(collectionID: String, itemIDs: [String]) async throws {
        try await api.send("POST", "/Collections/\(collectionID)/Items", query: [("Ids", itemIDs.joined(separator: ","))])
    }

    func removeFromCollection(collectionID: String, itemIDs: [String]) async throws {
        try await api.send("DELETE", "/Collections/\(collectionID)/Items", query: [("Ids", itemIDs.joined(separator: ","))])
    }

    func createCollection(name: String, itemIDs: [String]) async throws {
        _ = try await createCollectionID(name: name, itemIDs: itemIDs)
    }

    @discardableResult
    func createCollectionID(name: String, itemIDs: [String]) async throws -> String {
        let data = try await api.data(
            "POST",
            "/Collections",
            query: [
                ("Name", name),
                ("Ids", itemIDs.isEmpty ? nil : itemIDs.joined(separator: ",")),
                ("IsLocked", "false")
            ]
        )
        guard let id = EmbyJSON.object(from: data).flatMap({ Self.string($0["Id"]) }) else {
            throw ZelefinError.server("Emby did not create the collection.")
        }
        return id
    }

    func additionalParts(for itemID: String) async -> [MediaItem] {
        ((try? await dtos(
            "/Videos/\(itemID)/AdditionalParts",
            query: [("UserId", userID), ("EnableImageTypes", EmbyFields.imageTypes)]
        )) ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func randomTitle() async -> MediaItem? {
        (try? await userItems([
            ("Limit", "1"),
            ("Recursive", "true"),
            ("Fields", EmbyFields.list),
            ("IncludeItemTypes", "Movie,Series"),
            ("SortBy", "Random")
        ]))?.first
    }

    // MARK: Item administration

    func refreshItemMetadata(itemID: String, replaceImages: Bool) async throws {
        try await api.send(
            "POST",
            "/Items/\(itemID)/Refresh",
            query: [
                ("Recursive", "true"),
                ("MetadataRefreshMode", "FullRefresh"),
                ("ImageRefreshMode", replaceImages ? "FullRefresh" : "Default"),
                ("ReplaceAllMetadata", "false"),
                ("ReplaceAllImages", replaceImages ? "true" : "false")
            ]
        )
    }

    func deleteLibraryItem(itemID: String) async throws {
        try await api.send("DELETE", "/Items/\(itemID)")
    }

    func scanLibraries() async throws {
        try await api.send("POST", "/Library/Refresh")
    }

    func remoteArtwork(for itemID: String, kind: RemoteArtworkKind) async throws -> [RemoteImageChoice] {
        let result = try await api.decode(
            RemoteImageResult.self,
            "/Items/\(itemID)/RemoteImages",
            query: [
                ("Type", kind.jellyfinTypeName),
                ("StartIndex", "0"),
                ("Limit", "40"),
                ("IncludeAllLanguages", "true")
            ]
        )
        return (result.images ?? []).compactMap { info in
            guard let raw = info.url, let url = URL(string: raw) else { return nil }
            return RemoteImageChoice(
                id: "\(kind.rawValue)-\(raw)",
                imageURL: url,
                thumbnailURL: info.thumbnailURL.flatMap(URL.init(string:)),
                provider: info.providerName ?? "Provider",
                typeName: info.type?.rawValue ?? kind.jellyfinTypeName,
                width: info.width,
                height: info.height
            )
        }
    }

    func downloadRemoteArtwork(itemID: String, kind: RemoteArtworkKind, imageURL: URL) async throws {
        try await api.send(
            "POST",
            "/Items/\(itemID)/RemoteImages/Download",
            query: [("Type", kind.jellyfinTypeName), ("ImageUrl", imageURL.absoluteString)]
        )
    }

    func identifyHits(for item: MediaItem) async -> [RemoteIdentifyHit] {
        let route: String
        switch item.kind {
        case .movie: route = "/Items/RemoteSearch/Movie"
        case .series: route = "/Items/RemoteSearch/Series"
        default: return []
        }
        guard let body = try? api.json(Self.identifyQuery(for: item)),
              let results = try? await api.decode([RemoteSearchResult].self, route, method: "POST", body: body)
        else { return [] }
        return results.map(Self.identifyHit(from:))
    }

    static func identifyQuery(for item: MediaItem) -> [String: Any] {
        var info: [String: Any] = ["Name": item.name]
        if let year = item.year { info["Year"] = year }
        if let tmdb = item.tmdbID { info["ProviderIds"] = ["Tmdb": String(tmdb)] }
        return ["SearchInfo": info, "ItemId": item.id, "IncludeDisabledProviders": false]
    }

    func applyIdentify(itemID: String, hit: RemoteIdentifyHit) async throws {
        try await api.send(
            "POST",
            "/Items/RemoteSearch/Apply/\(itemID)",
            query: [("ReplaceAllImages", "true")],
            body: try JSONEncoder().encode(hit.raw)
        )
    }

    /// Emby replaces the whole item on update, so its own JSON goes back with only the edited
    /// fields changed. Genres and tags are sent both as names and as Emby's name/id pairs.
    func updateItemMetadata(itemID: String, draft: ItemMetadataDraft) async throws {
        let data = try await api.data("GET", "/Users/\(userID)/Items/\(itemID)")
        guard let current = EmbyJSON.object(from: data) else {
            throw ZelefinError.server("Emby did not return this title.")
        }
        try await api.send("POST", "/Items/\(itemID)", body: try api.json(Self.applying(draft, to: current)))
    }

    static func applying(_ draft: ItemMetadataDraft, to item: [String: Any]) -> [String: Any] {
        func list(_ raw: String) -> [String] {
            raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        var next = item
        next["Name"] = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next["Overview"] = draft.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        next["ProductionYear"] = Int(draft.year.trimmingCharacters(in: .whitespacesAndNewlines)) ?? NSNull()
        next["OfficialRating"] = draft.officialRating.trimmingCharacters(in: .whitespacesAndNewlines)
        let genres = list(draft.genres)
        let tags = list(draft.tags)
        next["Genres"] = genres
        next["GenreItems"] = genres.map { ["Name": $0] }
        next["Tags"] = tags
        next["TagItems"] = tags.map { ["Name": $0] }
        return next
    }

    private static func identifyHit(from result: RemoteSearchResult) -> RemoteIdentifyHit {
        let name = result.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RemoteIdentifyHit(
            name: name.isEmpty ? "Untitled" : name,
            year: result.productionYear,
            overview: result.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            providerIDs: result.providerIDs ?? [:],
            imageURL: result.imageURL.flatMap(URL.init(string:)),
            raw: result
        )
    }

    // MARK: Display preferences

    func displayPreferenceCustomPrefs() async throws -> [String: String] {
        let prefs = try await displayPreferences()
        return (prefs["CustomPrefs"] as? [String: Any] ?? [:]).compactMapValues { $0 as? String }
    }

    func updateDisplayPreferenceCustomPrefs(_ prefs: [String: String]) async throws {
        var current = (try? await displayPreferences()) ?? [:]
        current["Id"] = DisplayPreferencesSync.preferenceID
        current["Client"] = DeviceIdentity.clientName
        current["CustomPrefs"] = prefs
        try await api.send(
            "POST",
            "/DisplayPreferences/\(DisplayPreferencesSync.preferenceID)",
            query: [("UserId", userID)],
            body: try api.json(current)
        )
    }

    private func displayPreferences() async throws -> [String: Any] {
        let data = try await api.data(
            "GET",
            "/DisplayPreferences/\(DisplayPreferencesSync.preferenceID)",
            query: [("UserId", userID), ("Client", DeviceIdentity.clientName)]
        )
        return EmbyJSON.object(from: data) ?? [:]
    }

    // MARK: Remote control of other sessions

    func playOnSession(sessionID: String, itemIDs: [String], startPosition: TimeInterval?) async throws {
        try await api.send(
            "POST",
            "/Sessions/\(sessionID)/Playing",
            query: [
                ("ItemIds", itemIDs.joined(separator: ",")),
                ("PlayCommand", "PlayNow"),
                ("StartPositionTicks", startPosition.map { String(TickClock.intTicks(from: $0)) })
            ]
        )
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.isEmpty ? nil : text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }
}

extension EmbyLibraryClient: RemoteSessionServing {
    /// Emby has no activity window parameter, so sessions are filtered by their last activity.
    func playbackSessions(activeWithinSeconds: Int) async throws -> [PlaybackSession] {
        let dtos = try await api.decode([SessionInfoDto].self, "/Sessions")
        let cutoff = Date().addingTimeInterval(-TimeInterval(activeWithinSeconds))
        let sessions = dtos.compactMap(PlaybackSession.init(dto:)).filter { session in
            guard let last = session.lastActivity else { return true }
            return last >= cutoff
        }
        return PlaybackSession.sorted(sessions)
    }

    func sendPlaystate(sessionID: String, command: PlaystateCommand, seekPosition: TimeInterval?) async throws {
        var body: [String: Any] = ["Command": command.rawValue, "ControllingUserId": userID]
        if let seekPosition { body["SeekPositionTicks"] = TickClock.intTicks(from: seekPosition) }
        try await api.send("POST", "/Sessions/\(sessionID)/Playing/\(command.rawValue)", json: body)
    }

    func sendSessionCommand(sessionID: String, command: GeneralCommandType) async throws {
        try await api.send("POST", "/Sessions/\(sessionID)/Command/\(command.rawValue)")
    }

    func sendSessionMessage(sessionID: String, text: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await api.send(
            "POST",
            "/Sessions/\(sessionID)/Message",
            query: [("Header", "Zelefin"), ("Text", trimmed), ("TimeoutMs", "8000")]
        )
    }
}

extension EmbyLibraryClient: ServerAdministering {
    var canEditBranding: Bool { false }

    func activityLog(limit: Int) async throws -> [ActivityLogItem] {
        let page = try await api.decode(
            EmbyActivityPage.self,
            "/System/ActivityLog/Entries",
            query: [("StartIndex", "0"), ("Limit", String(limit))]
        )
        return (page.items ?? []).compactMap { entry in
            let title = entry.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            return ActivityLogItem(
                id: entry.id ?? "\(title)-\(entry.date?.timeIntervalSince1970 ?? 0)",
                title: title,
                detail: entry.shortOverview ?? entry.overview,
                date: entry.date,
                type: entry.type
            )
        }
    }

    func scheduledTasks() async throws -> [ScheduledTask] {
        let tasks = try await api.decode([TaskInfo].self, "/ScheduledTasks", query: [("IsHidden", "false")])
        return ScheduledTask.sorted(tasks.compactMap(ScheduledTask.init(dto:)))
    }

    func startScheduledTask(id: String) async throws {
        try await api.send("POST", "/ScheduledTasks/Running/\(id)")
    }

    func stopScheduledTask(id: String) async throws {
        try await api.send("DELETE", "/ScheduledTasks/Running/\(id)")
    }

    func serverBranding() async throws -> ServerBranding {
        let dto = try await api.decode(BrandingOptionsDto.self, "/Branding/Configuration")
        return ServerBranding(
            loginDisclaimer: dto.loginDisclaimer ?? "",
            customCSS: dto.customCss ?? "",
            splashscreenEnabled: false
        )
    }

    func updateServerBranding(_ branding: ServerBranding) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func uploadSplashscreen(_ imageData: Data) async throws {
        throw LibraryServingDefaults.unavailable
    }

    func deleteSplashscreen() async throws {
        throw LibraryServingDefaults.unavailable
    }
}

extension EmbyLibraryClient: LiveTVServing {
    func liveTVInfoEnabled() async throws -> Bool {
        let info = try await api.decode(EmbyLiveTVInfo.self, "/LiveTv/Info")
        return info.isEnabled ?? false
    }

    func liveTVChannels() async throws -> [LiveChannel] {
        try await dtos(
            "/LiveTv/Channels",
            query: [
                ("UserId", userID),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.liveTVImageTypes),
                ("Fields", EmbyFields.liveTV),
                ("EnableUserData", "true"),
                ("SortBy", "SortName"),
                ("EnableFavoriteSorting", "true"),
                ("AddCurrentProgram", "true")
            ]
        ).compactMap(ItemMapper.liveChannel(from:))
    }

    func liveTVRecordings(isInProgress: Bool?, limit: Int) async throws -> [LiveTVRecording] {
        if let isInProgress {
            return try await fetchRecordings(isInProgress: isInProgress, limit: limit)
        }
        async let active = fetchRecordings(isInProgress: true, limit: limit)
        async let completed = fetchRecordings(isInProgress: false, limit: limit)
        let inProgress = (try? await active) ?? []
        let finished = (try? await completed) ?? []
        if inProgress.isEmpty && finished.isEmpty {
            return try await fetchRecordings(isInProgress: nil, limit: limit)
        }
        return LiveTVRecording.merging(inProgress: inProgress, completed: finished)
    }

    private func fetchRecordings(isInProgress: Bool?, limit: Int) async throws -> [LiveTVRecording] {
        try await dtos(
            "/LiveTv/Recordings",
            query: [
                ("UserId", userID),
                ("Limit", String(limit)),
                ("IsInProgress", isInProgress.map { $0 ? "true" : "false" }),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.imageTypes),
                ("Fields", EmbyFields.liveTV),
                ("EnableUserData", "true")
            ]
        ).compactMap { ItemMapper.recordingItem(from: $0, treatAsInProgress: isInProgress == true) }
    }

    func deleteLiveTVRecording(id: String) async throws {
        try await api.send("DELETE", "/LiveTv/Recordings/\(id)")
    }

    func liveTVPrograms(
        channelIDs: [String]?,
        isAiring: Bool?,
        hasAired: Bool?,
        minStartDate: Date?,
        maxStartDate: Date?,
        filter: LiveTVProgramFilter?,
        limit: Int
    ) async throws -> [LiveProgram] {
        try await dtos(
            "/LiveTv/Programs",
            query: EmbyLiveTVQuery.programs(
                userID: userID,
                channelIDs: channelIDs,
                isAiring: isAiring,
                hasAired: hasAired,
                minStartDate: minStartDate,
                maxStartDate: maxStartDate,
                filter: filter,
                limit: limit
            )
        ).compactMap { ItemMapper.liveProgram(from: $0) }
    }

    func liveTVRecommendedPrograms(filter: LiveTVProgramFilter?, isAiring: Bool, limit: Int) async throws -> [LiveProgram] {
        try await dtos(
            "/LiveTv/Programs/Recommended",
            query: [
                ("UserId", userID),
                ("Limit", String(limit)),
                ("IsAiring", isAiring ? "true" : "false"),
                ("EnableImages", "true"),
                ("EnableImageTypes", EmbyFields.liveTVImageTypes),
                ("Fields", EmbyFields.liveTV),
                ("EnableUserData", "true")
            ] + EmbyLiveTVQuery.flags(filter)
        ).compactMap { ItemMapper.liveProgram(from: $0) }
    }

    func liveTVProgram(id: String) async throws -> LiveProgram {
        let dto = try await api.decode(BaseItemDto.self, "/LiveTv/Programs/\(id)", query: [("UserId", userID)])
        guard let program = ItemMapper.liveProgram(from: dto) else {
            throw ZelefinError.server("This program is no longer in the guide.")
        }
        return program
    }

    func liveTVGuide(channelIDs: [String], from start: Date, to end: Date) async throws -> [LiveProgram] {
        guard !channelIDs.isEmpty else { return [] }
        var programs: [LiveProgram] = []
        for chunk in stride(from: 0, to: channelIDs.count, by: 24) {
            let slice = Array(channelIDs[chunk ..< min(chunk + 24, channelIDs.count)])
            programs += try await liveTVPrograms(
                channelIDs: slice,
                isAiring: nil,
                hasAired: nil,
                minStartDate: start.addingTimeInterval(-6 * 3600),
                maxStartDate: end,
                filter: nil,
                limit: 2_000
            )
        }
        return programs
    }
}

extension EmbyFields {
    static let liveTVImageTypes = "Primary,Thumb,Backdrop,Logo,Screenshot,Banner"
    static let liveTV = list + ",ChannelInfo,AirTime"
}

enum EmbyLiveTVQuery {
    static func programs(
        userID: String,
        channelIDs: [String]?,
        isAiring: Bool?,
        hasAired: Bool?,
        minStartDate: Date?,
        maxStartDate: Date?,
        filter: LiveTVProgramFilter?,
        limit: Int
    ) -> [(String, String?)] {
        [
            ("UserId", userID),
            ("ChannelIds", channelIDs.map { $0.joined(separator: ",") }),
            ("IsAiring", isAiring.map { $0 ? "true" : "false" }),
            ("HasAired", hasAired.map { $0 ? "true" : "false" }),
            ("MinStartDate", minStartDate.map(date)),
            ("MaxStartDate", maxStartDate.map(date)),
            ("Limit", String(limit)),
            ("SortBy", "StartDate"),
            ("EnableImages", "true"),
            ("EnableImageTypes", EmbyFields.liveTVImageTypes),
            ("EnableUserData", "true"),
            ("Fields", EmbyFields.liveTV)
        ] + flags(filter)
    }

    static func flags(_ filter: LiveTVProgramFilter?) -> [(String, String?)] {
        switch filter {
        case .movies: [("IsMovie", "true")]
        case .series: [("IsSeries", "true")]
        case .news: [("IsNews", "true")]
        case .kids: [("IsKids", "true")]
        case .sports: [("IsSports", "true")]
        case nil: []
        }
    }

    static func date(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}

struct EmbyLiveTVInfo: Decodable, Sendable {
    var isEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "IsEnabled"
    }
}

/// Emby's activity entries carry numeric ids, which the lenient decoder turns into strings.
struct EmbyActivityPage: Decodable, Sendable {
    struct Entry: Decodable, Sendable {
        var id: String?
        var name: String?
        var overview: String?
        var shortOverview: String?
        var type: String?
        var date: Date?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case overview = "Overview"
            case shortOverview = "ShortOverview"
            case type = "Type"
            case date = "Date"
        }
    }

    var items: [Entry]?

    enum CodingKeys: String, CodingKey {
        case items = "Items"
    }
}
