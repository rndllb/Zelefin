import Foundation

actor SiloAPIClient {
    private var baseURL: URL
    private var accessToken: String
    private var refreshToken: String?
    private var profileID: String?
    private var profileToken: String?
    private let deviceID: String
    private let deviceName: String
    private let session: URLSession
    private let playbackSession: URLSession
    private var refreshTask: Task<Void, Error>?
    private var cachedHomeSections: SiloHomeSectionsResponse?
    private var cachedHomeSectionsAt: Date?

    var onTokensChanged: (@Sendable (String, String?) -> Void)?

    func setTokenHandler(_ handler: (@Sendable (String, String?) -> Void)?) {
        onTokensChanged = handler
    }

    /// Fired once when the server has revoked this session and a token refresh
    /// cannot recover it. The owner (SessionStore) uses it to force re-auth.
    var onSessionRevoked: (@Sendable () -> Void)?
    private var didNotifySessionRevoked = false

    func setSessionRevokedHandler(_ handler: (@Sendable () -> Void)?) {
        onSessionRevoked = handler
    }

    private func notifySessionRevoked() {
        guard !didNotifySessionRevoked else { return }
        didNotifySessionRevoked = true
        onSessionRevoked?()
    }

    init(
        baseURL: URL,
        accessToken: String = "",
        refreshToken: String? = nil,
        profileID: String? = nil,
        profileToken: String? = nil,
        deviceID: String = DeviceIdentity.deviceID(),
        deviceName: String = DeviceIdentity.deviceName,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.profileID = profileID
        self.profileToken = profileToken
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.session = session
        if session === URLSession.shared {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 90
            configuration.timeoutIntervalForResource = 300
            configuration.waitsForConnectivity = true
            self.playbackSession = URLSession(configuration: configuration)
        } else {
            self.playbackSession = session
        }
    }

    func setBaseURL(_ url: URL) {
        baseURL = url
    }

    func applyTokens(access: String, refresh: String?) {
        accessToken = access
        if let refresh {
            refreshToken = refresh
        }
        // A successful token change means the session is healthy again; re-arm
        // the revoked notifier so a later genuine revocation is still reported.
        didNotifySessionRevoked = false
    }

    func setProfile(id: String?, token: String?) {
        profileID = id
        profileToken = token
    }

    func health() async throws -> SiloHealth {
        try await get("/api/v1/health", authorized: false)
    }

    func homeSections() async throws -> SiloHomeSectionsResponse {
        if let cachedHomeSections, let cachedHomeSectionsAt,
           Date().timeIntervalSince(cachedHomeSectionsAt) < 8 {
            return cachedHomeSections
        }
        let query = ["image_size": "large"]
        var response: SiloHomeSectionsResponse = try await getFirst(
            ["/api/v2/home/sections", "/api/v1/home/sections"],
            query: query
        )
        response = await hydrateHomeSections(response)
        cachedHomeSections = response
        cachedHomeSectionsAt = Date()
        return response
    }

    func homeSectionItems(id: String) async throws -> [SiloCatalogItem] {
        let encoded = Self.path(id)
        let paths = [
            "/api/v2/home/sections/\(encoded)/items",
            "/api/v1/home/sections/\(encoded)/items"
        ]
        let query = ["image_size": "large"]
        for path in paths {
            guard let data = try? await getData(path, query: query) else { continue }
            if let section = try? SiloJSON.decoder.decode(SiloHomeSection.self, from: data),
               !section.entries.isEmpty {
                return section.entries
            }
            if let envelope = try? SiloJSON.decoder.decode(SiloHomeSectionItemsEnvelope.self, from: data),
               !envelope.entries.isEmpty {
                return envelope.entries
            }
            if let catalog = try? SiloJSON.decoder.decode(SiloCatalogResponse.self, from: data),
               !catalog.entries.isEmpty {
                return catalog.entries
            }
        }
        return []
    }

    func login(username: String, password: String) async throws -> SiloAuthResponse {
        let response: SiloAuthResponse = try await post(
            "/api/v1/auth/login",
            body: SiloLoginRequest(username: username, password: password),
            authorized: false
        )
        applyTokens(access: response.accessToken, refresh: response.refreshToken)
        return response
    }

    func refreshAccessToken() async throws {
        if let refreshTask {
            try await refreshTask.value
            return
        }
        let task = Task {
            try await performTokenRefresh()
        }
        refreshTask = task
        do {
            try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func performTokenRefresh() async throws {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw ZelefinError.missingUser
        }
        let response: SiloAuthResponse = try await post(
            "/api/v1/auth/refresh",
            body: SiloRefreshRequest(refreshToken: refreshToken),
            authorized: false,
            allowsRefreshRetry: false
        )
        applyTokens(access: response.accessToken, refresh: response.refreshToken ?? refreshToken)
        onTokensChanged?(response.accessToken, response.refreshToken ?? refreshToken)
    }

    func profiles() async throws -> [SiloHouseholdProfile] {
        try await profileList().entries
    }

    func profileList() async throws -> SiloProfilesResponse {
        var lastError: Error?
        for path in ["/api/v2/profiles", "/api/v1/profiles"] {
            do {
                let envelope: SiloProfilesResponse = try await get(path)
                return envelope.resolved(against: baseURL)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ZelefinError.server("The Silo server did not return household profiles.")
    }

    func updateProfileAvatar(id: String, preset: String?) async throws -> SiloHouseholdProfile {
        let encoded = Self.path(id)
        let body = SiloProfileAvatarUpdate(avatar: preset)
        var lastError: Error?
        for path in ["/api/v2/profiles/\(encoded)", "/api/v1/profiles/\(encoded)"] {
            do {
                let data = try await sendData(
                    path: path,
                    method: "PATCH",
                    query: [:],
                    body: body,
                    authorized: true,
                    allowsRefreshRetry: true
                )
                return try await decodeProfile(id: id, from: data)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ZelefinError.server("The Silo server did not update this avatar.")
    }

    func uploadProfileAvatar(id: String, jpeg: Data) async throws -> SiloHouseholdProfile {
        let encoded = Self.path(id)
        let boundary = "Boundary-\(UUID().uuidString)"
        var payload = Data()
        func append(_ value: String) {
            payload.append(Data(value.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        payload.append(jpeg)
        append("\r\n--\(boundary)--\r\n")

        var request = try makeRequest(
            path: "/api/v2/profiles/\(encoded)/avatar",
            method: "PUT",
            query: [:],
            body: nil as EmptyJSON?,
            authorized: true
        )
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("\(payload.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = payload
        let data = try await perform(request, allowsRefreshRetry: true)
        return try await decodeProfile(id: id, from: data)
    }

    func deleteProfileAvatar(id: String) async throws {
        let encoded = Self.path(id)
        try await delete("/api/v2/profiles/\(encoded)/avatar")
    }

    private func decodeProfile(id: String, from data: Data) async throws -> SiloHouseholdProfile {
        if !data.isEmpty,
           let profile = try? SiloJSON.decoder.decode(SiloHouseholdProfile.self, from: data) {
            return profile.resolved(against: baseURL)
        }
        if let match = try await profileList().entries.first(where: { $0.id == id }) {
            return match
        }
        throw ZelefinError.server("The Silo server did not return this profile.")
    }

    func createProfile(name: String, pin: String?, isChild: Bool) async throws -> SiloHouseholdProfile {
        try await post(
            "/api/v1/profiles",
            body: SiloCreateProfileRequest(
                name: name,
                pin: {
                    let trimmed = pin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return trimmed.isEmpty ? nil : trimmed
                }(),
                isChild: isChild
            )
        )
    }

    func currentUser() async throws -> SiloUser {
        try await get("/api/v1/auth/me")
    }

    func passwordCapability() async throws -> SiloPasswordCapability {
        try await getFirst([
            "/api/v2/account/password/capability",
            "/api/v1/auth/account/capability"
        ])
    }

    func changePassword(current: String, new: String) async throws {
        let body = SiloChangePasswordRequest(currentPassword: current, newPassword: new)
        do {
            try await postVoid("/api/v2/account/password", body: body)
        } catch {
            try await postVoid("/api/v1/auth/account/password", body: body)
        }
    }

    func adminUsers() async throws -> [SiloAdminUser] {
        let envelope: SiloAdminUsersResponse = try await getFirst([
            "/api/v2/admin/users",
            "/api/v1/admin/users"
        ], query: ["limit": "200"])
        return envelope.entries.filter { !$0.id.isEmpty }
    }

    func createAdminUser(_ body: SiloAdminUserCreateRequest) async throws {
        try await postVoid("/api/v2/admin/users", body: body)
    }

    func updateAdminUser(id: String, _ body: SiloAdminUserUpdateRequest) async throws {
        let encoded = Self.path(id)
        do {
            try await putVoid("/api/v2/admin/users/\(encoded)", body: body)
        } catch {
            try await putVoid("/api/v1/admin/users/\(encoded)", body: body)
        }
    }

    func deleteAdminUser(id: String) async throws {
        let encoded = Self.path(id)
        do {
            try await delete("/api/v2/admin/users/\(encoded)")
        } catch {
            try await delete("/api/v1/admin/users/\(encoded)")
        }
    }

    func adminTasks() async throws -> [SiloAdminTask] {
        let envelope: SiloPageCollection<SiloAdminTask> = try await get("/api/v2/admin/tasks")
        return envelope.entries
    }

    func runAdminTask(key: String) async throws {
        try await postVoid("/api/v2/admin/tasks/\(Self.path(key))/run", body: EmptyJSON.body)
    }

    func cancelAdminTask(key: String) async throws {
        try await postVoid("/api/v2/admin/tasks/\(Self.path(key))/cancel", body: EmptyJSON.body)
    }

    func adminDevices() async throws -> [SiloAdminDevice] {
        let envelope: SiloPageCollection<SiloAdminDevice> = try await get(
            "/api/v2/admin/devices",
            query: ["limit": "200"]
        )
        return envelope.entries
    }

    func adminAuditLogs() async throws -> [SiloAuditLog] {
        let envelope: SiloPageCollection<SiloAuditLog> = try await get(
            "/api/v2/admin/logs/audit",
            query: ["limit": "50"]
        )
        return envelope.entries
    }

    func adminLibraries() async throws -> [SiloAdminLibrary] {
        do {
            let envelope: SiloPageCollection<SiloAdminLibrary> = try await get("/api/v2/libraries")
            if !envelope.entries.isEmpty { return envelope.entries.filter { !$0.id.isEmpty } }
        } catch is DecodingError {
            // Fall back to the signed-in catalog.
        } catch let error as SiloHTTPError where error.isMissing {
            // Older Silo builds only expose user libraries.
        }
        return try await libraries().map {
            SiloAdminLibrary(id: String($0.id), name: $0.name, type: $0.type ?? $0.kind)
        }
    }

    func adminInvitations() async throws -> [SiloAdminInvitation] {
        let envelope: SiloPageCollection<SiloAdminInvitation> = try await get(
            "/api/v2/admin/invitations",
            query: ["limit": "50"]
        )
        return envelope.entries.filter { !$0.id.isEmpty }
    }

    func createInvitation(_ body: SiloInvitationCreateRequest) async throws -> SiloInvitationDelivery {
        try await post("/api/v2/admin/invitations", body: body)
    }

    func resendInvitation(id: String) async throws -> SiloInvitationDelivery {
        try await post(
            "/api/v2/admin/invitations/\(Self.path(id))/resend",
            body: EmptyJSON.body
        )
    }

    func revokeInvitation(id: String) async throws {
        try await delete("/api/v2/admin/invitations/\(Self.path(id))")
    }

    func adminSessions() async throws -> [SiloAdminSession] {
        let envelope: SiloPageCollection<SiloAdminSession> = try await get(
            "/api/v2/admin/sessions",
            query: ["limit": "100"]
        )
        return envelope.entries.filter { !$0.id.isEmpty }
    }

    func terminateAdminSession(id: String) async throws {
        try await postVoid(
            "/api/v2/admin/sessions/\(Self.path(id))/terminate",
            body: EmptyJSON.body
        )
    }

    func adminNodes() async throws -> [SiloAdminNode] {
        let envelope: SiloPageCollection<SiloAdminNode> = try await get(
            "/api/v2/admin/nodes",
            query: ["limit": "100"]
        )
        return envelope.entries.filter { !$0.id.isEmpty }
    }

    func checkAdminNode(id: String) async throws {
        try await postVoid("/api/v2/admin/nodes/\(Self.path(id))/check", body: EmptyJSON.body)
    }

    func adminOperationalLogs() async throws -> [SiloOperationalLog] {
        let envelope: SiloPageCollection<SiloOperationalLog> = try await get(
            "/api/v2/admin/logs/app",
            query: ["limit": "50"]
        )
        return envelope.entries
    }

    func refreshLibraryMetadata(libraryID: String, full: Bool) async throws {
        let path = "/api/v2/libraries/\(Self.path(libraryID))/refresh-metadata"
        if full {
            try await postVoid(path, body: ["mode": "full"])
        } else {
            try await postVoid(path, body: EmptyJSON.body)
        }
    }

    func refreshItemMetadata(itemID: String) async throws {
        try await postVoid(
            "/api/v2/admin/items/\(Self.path(itemID))/refresh-metadata",
            body: EmptyJSON.body
        )
    }

    func verifyPIN(profileID: String, pin: String) async throws -> SiloPINResult {
        try await post(
            "/api/v1/profiles/\(Self.path(profileID))/verify-pin",
            body: SiloPINVerification(pin: pin)
        )
    }

    func libraries() async throws -> [SiloLibraryRecord] {
        do {
            let envelope: SiloLibrariesEnvelope = try await get("/api/v1/user/libraries")
            if let libraries = envelope.libraries {
                return libraries
            }
        } catch is DecodingError {
            // Some builds return a bare array.
        }
        return try await get("/api/v1/user/libraries")
    }

    func catalog(query: [String: String]) async throws -> SiloCatalogResponse {
        do {
            return try await get("/api/v2/catalog", query: Self.v2CatalogQuery(query))
        } catch {
            return try await get("/api/v1/catalog", query: query)
        }
    }

    func catalogItem(id: String) async throws -> SiloCatalogItem {
        let encoded = Self.path(id)
        let v2 = await loadCatalogItem(path: "/api/v2/catalog/items/\(encoded)")
        if let v2, !(v2.versions ?? []).isEmpty { return v2 }
        let v1 = await loadCatalogItem(path: "/api/v1/catalog/items/\(encoded)")
        if let v1, !(v1.versions ?? []).isEmpty { return v1 }
        if let v2 { return v2 }
        if let v1 { return v1 }
        throw ZelefinError.server("This title was not found on the Silo server.")
    }

    func seasons(seriesID: String) async throws -> [SiloSeasonRecord] {
        let encoded = Self.path(seriesID)
        let paths = [
            "/api/v2/catalog/series/\(encoded)/seasons",
            "/api/v1/catalog/items/\(encoded)/seasons"
        ]
        var lastError: Error?
        for path in paths {
            do {
                let response: SiloSeasonsResponse = try await get(path)
                if !response.entries.isEmpty { return response.entries }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    func episodes(
        seriesID: String,
        seasonNumber: Int? = nil,
        seasonContentID: String? = nil
    ) async throws -> [SiloEpisodeRecord] {
        let seasonID = seasonContentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if seasonNumber == nil, seasonID.isEmpty {
            let seasons = (try? await seasons(seriesID: seriesID)) ?? []
            if !seasons.isEmpty {
                let collected = await episodes(seriesID: seriesID, seasons: seasons)
                if !collected.isEmpty { return collected }
            }
        }
        return try await episodeList(
            seriesID: seriesID,
            seasonNumber: seasonNumber,
            seasonContentID: seasonContentID
        )
    }

    func episodes(seriesID: String, seasons: [SiloSeasonRecord]) async -> [SiloEpisodeRecord] {
        guard !seasons.isEmpty else {
            return (try? await episodeList(seriesID: seriesID, seasonNumber: nil, seasonContentID: nil)) ?? []
        }
        var collected: [SiloEpisodeRecord] = []
        await withTaskGroup(of: [SiloEpisodeRecord].self) { group in
            for season in seasons {
                group.addTask {
                    (try? await self.episodeList(
                        seriesID: seriesID,
                        seasonNumber: season.seasonNumber,
                        seasonContentID: season.contentID ?? season.id
                    )) ?? []
                }
            }
            for await batch in group {
                collected.append(contentsOf: batch)
            }
        }
        if !collected.isEmpty { return collected }
        return (try? await episodeList(seriesID: seriesID, seasonNumber: nil, seasonContentID: nil)) ?? []
    }

    private func episodeList(
        seriesID: String,
        seasonNumber: Int?,
        seasonContentID: String?
    ) async throws -> [SiloEpisodeRecord] {
        let seriesPath = Self.path(seriesID)
        let seasonPath = seasonContentID.map(Self.path)
        var query: [String: String] = [:]
        if let seasonNumber {
            query["season"] = String(seasonNumber)
        }
        var paths: [String] = []
        if let seasonNumber {
            paths.append("/api/v2/catalog/series/\(seriesPath)/seasons/\(seasonNumber)/episodes")
        }
        if let seasonPath, !seasonPath.isEmpty {
            paths.append("/api/v2/catalog/items/\(seasonPath)/episodes")
            paths.append("/api/v1/catalog/items/\(seasonPath)/episodes")
        }
        paths.append("/api/v2/catalog/items/\(seriesPath)/episodes")
        paths.append("/api/v1/catalog/items/\(seriesPath)/episodes")

        var lastError: Error?
        var seen = Set<String>()
        for path in paths where seen.insert(path).inserted {
            do {
                let response: SiloEpisodesResponse = try await get(
                    path,
                    query: path.contains("/api/v1/") ? query : [:]
                )
                if !response.entries.isEmpty { return response.entries }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    func versions(itemID: String) async throws -> [SiloMediaVersion] {
        let encoded = Self.path(itemID)
        let paths = [
            "/api/v2/catalog/items/\(encoded)/versions",
            "/api/v2/catalog/items/\(encoded)",
            "/api/v1/catalog/items/\(encoded)/versions",
            "/api/v1/catalog/items/\(encoded)"
        ]
        for path in paths {
            if let data = try? await getData(path) {
                let versions = SiloMediaVersion.versions(from: data)
                if !versions.isEmpty { return versions }
            }
        }
        return try await catalogItem(id: itemID).versions ?? []
    }

    func watchVersions(itemID: String) async throws -> [SiloMediaVersion] {
        let encoded = Self.path(itemID)
        var lastError: Error?
        for path in ["/api/v2/watch/\(encoded)", "/api/v1/watch/\(encoded)"] {
            do {
                let versions = SiloMediaVersion.versions(from: try await getData(path))
                if !versions.isEmpty { return versions }
            } catch let error as SiloHTTPError where error.isMissing {
                lastError = error
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    func similarItems(id: String) async throws -> [SiloCatalogItem] {
        let encoded = Self.path(id)
        let entries = await similarEntries(encoded: encoded)
        guard !entries.isEmpty else { return [] }
        // The recommendation endpoint returns scored ids, not full items, so
        // resolve each to a catalog item (in parallel, preserving relevance order).
        return await withTaskGroup(of: (Int, SiloCatalogItem?).self) { group -> [SiloCatalogItem] in
            for (index, entry) in entries.prefix(12).enumerated() {
                if let inlined = entry.inlinedItem {
                    group.addTask { (index, inlined) }
                } else {
                    let entryID = entry.id
                    group.addTask { (index, try? await self.catalogItem(id: entryID)) }
                }
            }
            var collected: [(Int, SiloCatalogItem)] = []
            for await (index, item) in group {
                if let item { collected.append((index, item)) }
            }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// Same-genre catalog titles, used to populate a "Related" row when the
    /// recommendation engine has nothing for a title. One small page, filtered
    /// to the item's own media type.
    func genreRelated(genre: String, type: String, excluding contentID: String, limit: Int = 12) async -> [SiloCatalogItem] {
        let trimmed = genre.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var query: [String: String] = [
            "genre": trimmed,
            "limit": String(limit + 4),
            "offset": "0"
        ]
        if !type.isEmpty { query["type"] = type }
        guard let response = try? await catalog(query: query) else { return [] }
        return Array(response.entries.filter { $0.contentID != contentID }.prefix(limit))
    }

    private func similarEntries(encoded: String) async -> [SiloSimilarEntry] {
        let paths = [
            "/api/v1/recommendations/similar/\(encoded)",
            "/api/v2/recommendations/similar/\(encoded)"
        ]
        for path in paths {
            if let response: SiloSimilarResponse = try? await get(path, query: ["limit": "12"]),
               !response.entries.isEmpty {
                return response.entries
            }
        }
        return []
    }

    func catalogFilters() async throws -> SiloCatalogFilters {
        try await getFirst(
            ["/api/v2/catalog/filters", "/api/v1/catalog/filters"],
            query: ["skip_technical": "true"]
        )
    }

    func forYouMain() async throws -> SiloRecommendationRow {
        try await get("/api/v2/recommendations/for-you/main")
    }

    func recommendationRows() async throws -> [SiloRecommendationRow] {
        let response: SiloRecommendationRowsResponse = try await getFirst([
            "/api/v2/recommendations/for-you/rows",
            "/api/v2/recommendations/discover",
            "/api/v1/recommendations/for-you/rows",
            "/api/v1/recommendations/discover"
        ])
        return response.entries
    }

    func personalCollections() async throws -> [SiloPersonalCollection] {
        let response: SiloPersonalCollectionsResponse = try await getFirst([
            "/api/v2/collections",
            "/api/v1/collections"
        ])
        return response.entries
    }

    func calendar(start: String, end: String, timezone: String) async throws -> SiloCalendar {
        try await get(
            "/api/v2/calendar",
            query: [
                "start": start,
                "end": end,
                "timezone": timezone,
                "filter": "all"
            ]
        )
    }

    func progress() async throws -> SiloProgressResponse {
        try await get("/api/v1/progress")
    }

    func markWatched(id: String) async throws {
        cachedHomeSections = nil
        try await postVoid("/api/v1/watched/\(Self.path(id))", body: EmptyJSON.body)
    }

    func markUnwatched(id: String) async throws {
        cachedHomeSections = nil
        try await delete("/api/v1/watched/\(Self.path(id))")
    }

    func setFavorite(id: String, isFavorite: Bool) async throws {
        cachedHomeSections = nil
        let encoded = Self.path(id)
        if isFavorite {
            try await putVoid("/api/v1/favorites/\(encoded)", body: EmptyJSON.body)
        } else {
            try await delete("/api/v1/favorites/\(encoded)")
        }
    }

    func startPlayback(_ body: some Encodable) async throws -> SiloPlaybackDecision {
        let data = try await sendData(
            path: "/api/v1/playback/start",
            method: "POST",
            query: [:],
            body: body,
            authorized: true,
            allowsRefreshRetry: true,
            timeout: 90
        )
        if var decision = try? SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: data) {
            if decision.resolvedStreamPath == nil {
                decision.scrapedStreamURL = SiloPlaybackStart.scrapeStreamURL(from: data)
            }
            return decision
        }
        if let scraped = SiloPlaybackStart.scrapeStreamURL(from: data) {
            var decision = SiloPlaybackDecision()
            decision.scrapedStreamURL = scraped
            return decision
        }
        return try SiloJSON.decoder.decode(SiloPlaybackDecision.self, from: data)
    }

    func playbackCapability() async throws -> SiloPlaybackCapability {
        try await get("/api/v1/playback/capability")
    }

    func reportProgress(sessionID: String, position: TimeInterval, isPaused: Bool) async throws {
        cachedHomeSections = nil
        try await postVoid(
            "/api/v1/playback/\(Self.path(sessionID))/progress",
            body: SiloProgressReport(position: position, isPaused: isPaused)
        )
    }

    func stopPlayback(sessionID: String) async throws {
        cachedHomeSections = nil
        try await delete("/api/v1/playback/\(Self.path(sessionID))")
    }

    func get<T: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        authorized: Bool = true
    ) async throws -> T {
        try await send(path: path, method: "GET", query: query, body: nil as EmptyJSON?, authorized: authorized)
    }

    private func hydrateHomeSections(_ response: SiloHomeSectionsResponse) async -> SiloHomeSectionsResponse {
        var sections = response.rows
        guard !sections.isEmpty else { return response }
        await withTaskGroup(of: (Int, [SiloCatalogItem]).self) { group in
            for (index, section) in sections.enumerated() where section.entries.isEmpty {
                let id = section.resolvedID
                guard !id.isEmpty else { continue }
                group.addTask {
                    let items = (try? await self.homeSectionItems(id: id)) ?? []
                    return (index, items)
                }
            }
            for await (index, items) in group where !items.isEmpty {
                sections[index].items = items
            }
        }
        return SiloHomeSectionsResponse(sections: sections, items: nil)
    }

    private static func v2CatalogQuery(_ query: [String: String]) -> [String: String] {
        var converted = query
        if let sort = converted["sort"], let order = converted.removeValue(forKey: "order"),
           order.lowercased() == "desc", !sort.hasPrefix("-") {
            converted["sort"] = "-\(sort)"
        }
        return converted
    }

    private func getFirst<T: Decodable>(
        _ paths: [String],
        query: [String: String] = [:]
    ) async throws -> T {
        var lastError: Error?
        for path in paths {
            do {
                return try await get(path, query: query)
            } catch let error as SiloHTTPError where error.isMissing {
                lastError = error
            } catch is DecodingError {
                lastError = DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "Unexpected payload for \(path)")
                )
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ZelefinError.server("The Silo server did not return this resource.")
    }

    func post<T: Decodable, Body: Encodable>(
        _ path: String,
        body: Body,
        authorized: Bool = true,
        allowsRefreshRetry: Bool = true,
        timeout: TimeInterval = 60
    ) async throws -> T {
        try await send(
            path: path,
            method: "POST",
            body: body,
            authorized: authorized,
            allowsRefreshRetry: allowsRefreshRetry,
            timeout: timeout
        )
    }

    private func loadCatalogItem(path: String) async -> SiloCatalogItem? {
        guard let data = try? await getData(path) else { return nil }
        if let item = try? SiloJSON.decoder.decode(SiloCatalogItem.self, from: data) {
            return item.withFileIDs(from: data)
        }
        if let envelope = try? SiloJSON.decoder.decode(SiloItemEnvelope.self, from: data),
           let item = envelope.item {
            return item.withFileIDs(from: data)
        }
        if let envelope = try? SiloJSON.decoder.decode(SiloWatchEnvelope.self, from: data),
           let item = envelope.item ?? envelope.nestedItem?.item {
            return item.withFileIDs(from: data)
        }
        return SiloCatalogItem.salvage(from: data)
    }

    func getData(_ path: String, query: [String: String] = [:]) async throws -> Data {
        try await sendData(
            path: path,
            method: "GET",
            query: query,
            body: nil as EmptyJSON?,
            authorized: true,
            allowsRefreshRetry: true
        )
    }

    func bitrateTestBytes(size: Int, fallbackURL: URL?) async throws -> Data {
        let bounded = min(max(size, 32_000), 8_000_000)
        do {
            let data = try await sendData(
                path: "/api/v1/playback/bitrate-test",
                method: "GET",
                query: ["size": String(bounded)],
                body: nil as EmptyJSON?,
                authorized: true,
                allowsRefreshRetry: true,
                timeout: 25
            )
            if data.count >= 16_000 { return data }
        } catch let error as SiloHTTPError where error.isMissing {
            // Native Silo has no dedicated probe endpoint; fall through.
        }
        if let fallbackURL {
            let data = try await downloadLimited(from: fallbackURL, limit: bounded)
            if data.count >= 16_000 { return data }
        }
        var collected = Data()
        collected.reserveCapacity(bounded)
        var round = 0
        while collected.count < bounded, round < 24 {
            round += 1
            let chunk = try await sendData(
                path: "/api/v2/home/sections",
                method: "GET",
                query: [
                    "image_size": "large",
                    "_probe": "\(Int(Date().timeIntervalSince1970))-\(round)"
                ],
                body: nil as EmptyJSON?,
                authorized: true,
                allowsRefreshRetry: true,
                timeout: 25
            )
            collected.append(chunk)
            try Task.checkCancellation()
        }
        guard collected.count >= 16_000 else {
            throw ZelefinError.bitrateTestFailed
        }
        return collected
    }

    private func downloadLimited(from url: URL, limit: Int) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("bytes=0-\(max(limit - 1, 0))", forHTTPHeaderField: "Range")
        for (name, value) in streamHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        AccessGateway.apply(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ZelefinError.bitrateTestFailed
        }
        if data.count <= limit { return data }
        return Data(data.prefix(limit))
    }

    func postData<Body: Encodable>(
        _ path: String,
        body: Body,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        try await sendData(
            path: path,
            method: "POST",
            query: [:],
            body: body,
            authorized: true,
            allowsRefreshRetry: true,
            timeout: timeout
        )
    }

    func postVoid<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: SiloEmptyResponse = try await post(path, body: body)
    }

    func putVoid<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: SiloEmptyResponse = try await send(path: path, method: "PUT", body: body, authorized: true)
    }

    func patchVoid<Body: Encodable>(_ path: String, body: Body) async throws {
        let _: SiloEmptyResponse = try await send(path: path, method: "PATCH", body: body, authorized: true)
    }

    // MARK: - Managed downloads (contract: /api/v1/downloads)

    func downloadCapability() async throws -> SiloDownloadCapability {
        try await get("/api/v1/downloads/capability")
    }

    func createDownload(_ request: SiloCreateDownloadRequest) async throws -> [SiloDownloadRow] {
        let response: SiloDownloadsResponse = try await post("/api/v1/downloads", body: request)
        return response.entries
    }

    func downloadRows() async throws -> [SiloDownloadRow] {
        let response: SiloDownloadsResponse = try await get("/api/v1/downloads")
        return response.entries
    }

    func patchDownloadStatus(id: String, status: String) async throws {
        try await patchVoid("/api/v1/downloads/\(Self.path(id))", body: ["status": status])
    }

    func deleteDownload(id: String) async throws {
        try await delete("/api/v1/downloads/\(Self.path(id))")
    }

    /// Absolute URL for a ready download's bytes, resolved against the server
    /// origin (preserving any base path the user's server URL carries).
    func downloadFileURL(id: String) -> URL? {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let basePath = components.percentEncodedPath
        let trimmed = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        components.percentEncodedPath = trimmed + "/api/v1/downloads/\(Self.path(id))/file"
        return components.url
    }

    func delete(_ path: String) async throws {
        let _: SiloEmptyResponse = try await send(
            path: path,
            method: "DELETE",
            body: nil as EmptyJSON?,
            authorized: true
        )
    }

    func streamHeaders() -> [String: String] {
        var headers = identityHeaders()
        headers["Authorization"] = "Bearer \(accessToken)"
        if let profileID {
            headers["X-Profile-Id"] = profileID
        }
        if let profileToken {
            headers["X-Profile-Token"] = profileToken
        }
        return headers
    }

    func resolveURL(_ raw: String) -> URL? {
        Self.mediaURL(baseURL: baseURL, raw: raw)
    }

    /// Proxy origins are LAN addresses. Asking for them while connected through
    /// a public HTTPS hostname makes play work on the local IP and fail remotely.
    func allowsAuthorizedMediaOrigins(_ capability: SiloPlaybackCapability?) -> Bool {
        guard capability?.authorizedMediaOrigins == true else { return false }
        return ServerURL.isInternalHost(baseURL.host ?? "")
    }

    /// Silo v3 plans return API-local paths like `/stream/{session}`. The iOS
    /// client prefixes `/api/v1`; resolving against the server root 404s.
    static func mediaURL(baseURL: URL, raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let absolute = URL(string: trimmed),
           let scheme = absolute.scheme?.lowercased(),
           scheme == "http" || scheme == "https",
           absolute.host != nil {
            let rewritten = ServerURL.rewriteIfNeeded(absolute, publicBase: baseURL)
            return pinnedAPIStreamURL(rewritten, apiBase: baseURL)
        }
        guard !trimmed.hasPrefix("//") else { return nil }
        var relative = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        if relative.hasPrefix("/stream/v3/") {
            relative = "/api/v1/stream/" + relative.dropFirst("/stream/v3/".count)
        } else if !relative.hasPrefix("/api/") {
            relative = "/api/v1" + relative
        }
        guard var base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = URLComponents(string: relative)
        let path = parts?.percentEncodedPath.isEmpty == false ? parts!.percentEncodedPath : relative
        let basePath = base.percentEncodedPath
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        base.percentEncodedPath = trimmedBase + path
        base.percentEncodedQuery = parts?.percentEncodedQuery
        base.fragment = nil
        return base.url
    }

    /// `/stream/v3/{session}` is the media-proxy listener. The hostname the user
    /// typed is the API, so pin those grants onto `/api/v1/stream/{session}`.
    static func pinnedAPIStreamURL(_ url: URL, apiBase: URL) -> URL {
        guard let apiHost = apiBase.host, let host = url.host,
              host.caseInsensitiveCompare(apiHost) == .orderedSame else {
            return url
        }
        let prefix = "/stream/v3/"
        guard url.path.hasPrefix(prefix) else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let rest = url.path.dropFirst(prefix.count)
        var apiPath = apiBase.path
        while apiPath.count > 1, apiPath.hasSuffix("/") {
            apiPath.removeLast()
        }
        if apiPath == "/" { apiPath = "" }
        components.scheme = apiBase.scheme
        components.host = apiHost
        components.port = apiBase.port
        components.path = apiPath + "/api/v1/stream/" + rest
        return components.url ?? url
    }

    private func send<T: Decodable, Body: Encodable>(
        path: String,
        method: String,
        query: [String: String] = [:],
        body: Body?,
        authorized: Bool,
        allowsRefreshRetry: Bool = true,
        timeout: TimeInterval = 60
    ) async throws -> T {
        let data = try await sendData(
            path: path,
            method: method,
            query: query,
            body: body,
            authorized: authorized,
            allowsRefreshRetry: allowsRefreshRetry,
            timeout: timeout
        )
        if let empty = SiloEmptyResponse() as? T {
            return empty
        }
        do {
            return try SiloJSON.decoder.decode(T.self, from: data)
        } catch {
            if let empty = SiloEmptyResponse() as? T {
                return empty
            }
            throw error
        }
    }

    private func sendData<Body: Encodable>(
        path: String,
        method: String,
        query: [String: String],
        body: Body?,
        authorized: Bool,
        allowsRefreshRetry: Bool,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        let request = try makeRequest(
            path: path,
            method: method,
            query: query,
            body: body,
            authorized: authorized
        )
        return try await perform(request, allowsRefreshRetry: allowsRefreshRetry, timeout: timeout)
    }

    private func perform(
        _ request: URLRequest,
        allowsRefreshRetry: Bool,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        var request = request
        request.timeoutInterval = timeout
        let urlSession = timeout > 60 ? playbackSession : session
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZelefinError.server("The Silo server did not return a valid response.")
        }
        if http.statusCode == 401, allowsRefreshRetry, refreshToken != nil {
            do {
                try await refreshAccessToken()
            } catch {
                // The refresh endpoint rejected our refresh token — the session
                // is dead and no amount of retrying will bring it back.
                if let siloError = error as? SiloHTTPError,
                   siloError.statusCode == 401 || siloError.statusCode == 403 {
                    notifySessionRevoked()
                }
                throw error
            }
            var retry = request
            retry.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            return try await perform(retry, allowsRefreshRetry: false, timeout: timeout)
        }
        if (200..<300).contains(http.statusCode) {
            return data
        }
        let error = SiloJSON.error(statusCode: http.statusCode, data: data)
        if error.isSessionRevoked {
            notifySessionRevoked()
        }
        throw error
    }

    private func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        query: [String: String],
        body: Body?,
        authorized: Bool
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ZelefinError.invalidServerURL
        }
        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        let basePath = components.percentEncodedPath
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        components.percentEncodedPath = trimmedBase + normalizedPath
        if !query.isEmpty {
            components.queryItems = query
                .filter { !$0.value.isEmpty }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw ZelefinError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.assumesHTTP3Capable = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in identityHeaders() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        AccessGateway.apply(&request)
        if authorized {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            if let profileID {
                request.setValue(profileID, forHTTPHeaderField: "X-Profile-Id")
            }
            if let profileToken {
                request.setValue(profileToken, forHTTPHeaderField: "X-Profile-Token")
            }
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try SiloJSON.encoder.encode(body)
        }
        return request
    }

    private func identityHeaders() -> [String: String] {
        let channel: String
        #if DEBUG
        channel = "dev"
        #else
        channel = "release"
        #endif
        return [
            "X-Silo-Device-Id": deviceID,
            "X-Silo-Device-Name": deviceName,
            "X-Silo-Device-Platform": "iOS",
            "X-Silo-Client-Family": DeviceIdentity.clientFamily,
            "X-Silo-Client": DeviceIdentity.clientName,
            "X-Silo-Client-Version": DeviceIdentity.version,
            "X-Silo-Client-Build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "X-Silo-Client-Channel": channel
        ]
    }

    static func path(_ component: String) -> String {
        let trimmed = component.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return trimmed }
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
    }
}

enum SiloJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(TimeInterval.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let raw = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) ?? ISO8601DateFormatter().date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date \(raw)")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static func error(statusCode: Int, data: Data) -> SiloHTTPError {
        let body = (try? decoder.decode(SiloAPIErrorBody.self, from: data))
        let message = body?.resolvedMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = [message, fallback].compactMap { value -> String? in
            let trimmed = value ?? ""
            return trimmed.isEmpty || trimmed.hasPrefix("<") ? nil : trimmed
        }.first
        return SiloHTTPError(
            statusCode: statusCode,
            code: body?.resolvedCode,
            message: resolved ?? "The Silo server returned HTTP \(statusCode)."
        )
    }
}

private struct EmptyJSON: Encodable, Sendable {
    static let body = EmptyJSON()
}

private struct SiloEmptyResponse: Decodable, Sendable {
    init() {}
}

private struct SiloProgressReport: Encodable, Sendable {
    var position: TimeInterval
    var isPaused: Bool
}
