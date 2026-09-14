import Foundation
import JellyfinAPI
import Network
import Observation

@MainActor
@Observable
final class SessionStore {
    private let vault = SessionVault()
    private let probe = ServerProbe()
    private let snapshotStore: any HomeSnapshotStoring
    private let itemDetailStore: any ItemDetailSnapshotStoring
    private let catalogStore: any CatalogSnapshotStoring
    private var itemDetailMemory: [String: ItemDetailSnapshot] = [:]
    private var prefetchTask: Task<Void, Never>?

    private(set) var session: SavedSession?
    private(set) var accounts: [SavedSession] = []
    private(set) var client: JellyfinClient?
    private(set) var library: JellyfinLibraryClient?
    private(set) var isRestoring = true
    private(set) var serverName: String?
    private(set) var homeLayout = HomeLayout(featured: [], sections: [])
    private(set) var libraries: [MediaLibrary] = []
    private(set) var homeError: String?
    private(set) var isLoadingHome = false
    private(set) var introSkipperAvailable = false
    private(set) var openSubtitlesAvailable = false
    private(set) var jellyfinEnhancedAvailable = false
    private(set) var companionAvailable = false
    private(set) var isAdministrator = false
    private(set) var enableSubtitleManagement = false

    var canManageSubtitles: Bool {
        RemoteSubtitleOffer.canManageSubtitles(
            isAdministrator: isAdministrator,
            enableSubtitleManagement: enableSubtitleManagement
        )
    }

    func shouldShowAddSubtitles(for item: MediaItem) -> Bool {
        RemoteSubtitleOffer.shouldShowAddSubtitles(
            canManageSubtitles: canManageSubtitles,
            pluginAvailable: openSubtitlesAvailable,
            supportsRemote: item.supportsRemoteSubtitles
        )
    }
    private(set) var tmdbCatalog = JellyfinTmdbCatalog()
    private(set) var currentSSID: String?
    private(set) var activeRoute: HomeNetworkRoute = .remote
    let adaptiveBitrate = AdaptiveBitrateStore()
    private var pathMonitor: NWPathMonitor?
    private var playbackLaunchOptions: [String: PlaybackLaunchOptions] = [:]

    private var homeTask: Task<Void, Never>?

    init(
        snapshotStore: any HomeSnapshotStoring = FileHomeSnapshotStore(),
        itemDetailStore: any ItemDetailSnapshotStoring = FileItemDetailSnapshotStore(),
        catalogStore: any CatalogSnapshotStoring = FileCatalogSnapshotStore()
    ) {
        self.snapshotStore = snapshotStore
        self.itemDetailStore = itemDetailStore
        self.catalogStore = catalogStore
    }

    /// Cached full catalog for a Movies/Shows tab, so the grid paints instantly on a cold launch.
    func cachedCatalog(kind: LibraryKind) -> [MediaItem]? {
        guard let session else { return nil }
        return catalogStore.load(userID: session.userID, serverURL: session.serverURL, kind: kind)?.items
    }

    /// Persist a freshly fetched catalog for later cold launches.
    func saveCatalog(_ items: [MediaItem], kind: LibraryKind) {
        guard let session, !items.isEmpty else { return }
        catalogStore.save(
            CatalogSnapshot(
                version: CatalogSnapshot.currentVersion,
                userID: session.userID,
                serverHost: SnapshotCoding.host(from: session.serverURL),
                libraryKind: kind,
                savedAt: Date(),
                items: items
            )
        )
    }

    func launchOptions(for itemID: String) -> PlaybackLaunchOptions {
        playbackLaunchOptions[itemID] ?? PlaybackLaunchOptions()
    }

    func updateLaunchOptions(for itemID: String, _ mutate: (inout PlaybackLaunchOptions) -> Void) {
        var options = launchOptions(for: itemID)
        mutate(&options)
        playbackLaunchOptions[itemID] = options
    }

    /// Wait until Home has finished, then warm each library tab from smallest catalog to
    /// largest. First launch caches the whole library; later launches only fetch newly
    /// added titles.
    private func startPosterPrefetch(for saved: SavedSession) {
        guard let library else { return }
        prefetchTask?.cancel()
        let catalogStore = self.catalogStore
        let knownLibraries = libraries
        prefetchTask = Task(priority: .background) {
            var catalog = knownLibraries
            if catalog.isEmpty {
                catalog = (try? await library.libraries()) ?? []
            }
            guard !catalog.isEmpty, !Task.isCancelled else { return }
            await PosterPrefetcher.run(
                library: library,
                libraries: catalog,
                userID: saved.userID,
                serverURL: saved.serverURL,
                snapshotStore: catalogStore
            )
            guard !Task.isCancelled else { return }
            await refreshTmdbCatalog()
        }
    }

    private(set) var avatarRevision = 0

    var avatarURL: URL? {
        guard let session else { return nil }
        return avatarURL(for: session)
    }

    func avatarURL(for account: SavedSession) -> URL? {
        guard let client else { return nil }
        let revision = account.accountID == session?.accountID ? avatarRevision : 0
        return ArtworkURLBuilder(client: client).userAvatar(
            userID: account.userID,
            tag: account.userImageTag,
            revision: revision
        )
    }

    var isSignedIn: Bool { session != nil && library != nil }

    var isReviewDemo: Bool { ReviewDemo.isSession(session) }

    var homeNetworkProfile: HomeNetworkProfile {
        guard let id = session?.accountID else { return HomeNetworkProfile() }
        return HomeNetworkStore.profile(for: id)
    }

    var activeServerURL: URL? {
        client?.configuration.url ?? session?.serverURL
    }

    var otherAccounts: [SavedSession] {
        accounts.filter { $0.accountID != session?.accountID }
    }

    func restore() async {
        defer { isRestoring = false }
        guard let box = try? vault.loadBox(), let saved = box.current else { return }
        accounts = box.accounts
        apply(saved, serverVersion: saved.serverVersion)
        await refreshSessionCapabilities()
    }

    func addUserOnCurrentServer(username: String, password: String) async throws {
        guard let current = session else { throw ZelefinError.missingUser }
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw ZelefinError.server("Enter a username.")
        }
        guard !password.isEmpty else {
            throw ZelefinError.server("Enter a password.")
        }
        try await connect(
            serverAddress: current.serverURL.absoluteString,
            username: name,
            password: password
        )
    }

    func connect(serverAddress: String, username: String, password: String) async throws {
        let url = try probe.normalizedURL(from: serverAddress)
        let info = try await probe.publicInfo(at: url)
        let deviceID = DeviceIdentity.deviceID()
        let jellyfin = JellyfinNetworking.client(url: url, deviceID: deviceID)
        let auth = try await jellyfin.signIn(username: username, password: password)
        try completeSignIn(
            auth,
            serverURL: url,
            info: info,
            deviceID: deviceID,
            fallbackName: username,
            client: jellyfin
        )
    }

    func connectReviewDemo() {
        guard ReviewDemo.isEnabled else { return }
        let saved = ReviewDemo.session
        apply(saved)
        persist(saved)
    }

    /// Signs in with Quick Connect, calling `presentCode` when the code is ready.
    func connectUsingQuickConnect(
        serverAddress: String,
        presentCode: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        let url = try probe.normalizedURL(from: serverAddress)
        let info = try await probe.publicInfo(at: url)
        let deviceID = DeviceIdentity.deviceID()
        let jellyfin = JellyfinNetworking.client(url: url, deviceID: deviceID)

        guard try await QuickConnectClient.isEnabled(on: jellyfin) else {
            throw ZelefinError.quickConnectDisabled
        }

        let handshake = try await QuickConnectClient.start(on: jellyfin)
        presentCode(handshake.groupedCode)

        let secret = try await QuickConnectClient.waitUntilAuthorized(handshake, on: jellyfin)
        try Task.checkCancellation()

        let auth = try await jellyfin.signIn(quickConnectSecret: secret)
        try completeSignIn(
            auth,
            serverURL: url,
            info: info,
            deviceID: deviceID,
            fallbackName: auth.user?.name ?? "User",
            client: jellyfin
        )
    }

    private func completeSignIn(
        _ auth: AuthenticationResult,
        serverURL: URL,
        info: PublicSystemInfo,
        deviceID: String,
        fallbackName: String,
        client jellyfin: JellyfinClient
    ) throws {
        guard let token = auth.accessToken, let user = auth.user, let userID = user.id else {
            throw ZelefinError.missingUser
        }

        let saved = SavedSession(
            serverURL: serverURL,
            accessToken: token,
            userID: userID,
            userName: user.name ?? fallbackName,
            deviceID: deviceID,
            userImageTag: user.primaryImageTag,
            serverVersion: info.version,
            serverName: info.serverName
        )
        serverName = info.serverName
        apply(saved, client: jellyfin, serverVersion: info.version)
        persist(saved)
    }

    func switchTo(_ account: SavedSession) async {
        guard account.accountID != session?.accountID else { return }
        if let current = session {
            persist(current, select: false)
        }
        apply(account, serverVersion: account.serverVersion)
        persist(account)
    }

    func signOut() async {
        homeTask?.cancel()
        let remote = client
        let companion = remote.map(ZelefinCompanionClient.init)
        let remaining: SavedSession?
        if let id = session?.accountID, var box = try? vault.loadBox() {
            remaining = box.remove(id: id)
            try? vault.persist(box)
            accounts = box.accounts
        } else {
            remaining = nil
            vault.delete()
            accounts = []
        }
        clearLocalSession()
        CompanionSettings.pluginInstalled = false
        if let remaining {
            apply(remaining, serverVersion: remaining.serverVersion)
            persist(remaining)
        }
        Task {
            await companion?.deleteDevice()
            try? await remote?.signOut()
        }
    }

    func changePassword(current: String, new: String) async throws {
        guard let client, let session else { throw ZelefinError.missingUser }
        let currentPassword = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPassword = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            throw ZelefinError.server("Enter your current password and a new password.")
        }
        guard newPassword.count >= 1 else {
            throw ZelefinError.server("Enter a new password.")
        }
        _ = try await client.send(
            Paths.updateUserPassword(
                userID: session.userID,
                .init(currentPw: currentPassword, newPw: newPassword)
            )
        )
    }

    func updateProfileImage(_ jpeg: Data) async throws {
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await updateProfileImage(userID: userID, jpeg: jpeg)
    }

    func updateProfileImage(userID: String, jpeg: Data) async throws {
        guard !jpeg.isEmpty else {
            throw ZelefinError.server("Zelefin could not read that photo.")
        }
        try ensureCanChangePhoto(of: userID)
        try await postProfileImage(jpeg, userID: userID)
        if userID == session?.userID {
            avatarRevision += 1
            await refreshAccount()
        }
    }

    func removeProfileImage() async throws {
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await removeProfileImage(userID: userID)
    }

    func removeProfileImage(userID: String) async throws {
        try ensureCanChangePhoto(of: userID)
        guard let client else { throw ZelefinError.missingUser }
        _ = try await client.send(Paths.deleteUserImage(userID: userID))
        if userID == session?.userID {
            avatarRevision += 1
            await refreshAccount()
        }
    }

    private func ensureCanChangePhoto(of userID: String) throws {
        guard UserImageAdminPolicy.canChangePhoto(
            actorIsAdmin: isAdministrator,
            actorUserID: session?.userID,
            targetUserID: userID
        ) else {
            throw ZelefinError.server("Sign in with an administrator to change another user's photo.")
        }
    }

    func refreshHome() async {
        await loadHome(force: true)
    }

    func markWatched(_ item: MediaItem) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.markPlayed(itemID: item.id)
        removeFromHome(itemID: item.id)
        Task { await refreshHome() }
    }

    func markUnwatched(_ item: MediaItem) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.markUnplayed(itemID: item.id)
        Task { await refreshHome() }
    }

    func hideFromRecentlyWatched(_ item: MediaItem) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.markUnplayed(itemID: item.id)
        removeFromHome(itemID: item.id)
        Task { await refreshHome() }
    }

    func hideFromHomeQueue(_ item: MediaItem) async throws {
        guard jellyfinEnhancedAvailable, let client else {
            throw ZelefinError.server("Jellyfin Enhanced is not installed on this server.")
        }
        let surface = JellyfinEnhancedHomeHide.surface(queueKind: item.queueKind)
        try await JellyfinEnhancedClient(client: client).hideFromHome(itemID: item.id, surface: surface)
        removeFromHome(itemID: item.id)
        Task { await refreshHome() }
    }

    private func removeFromHome(itemID: String) {
        homeLayout = HomeLayoutPreferences.removing(itemID, from: homeLayout)
        persistSnapshot()
    }

    private func refreshAccount() async {
        guard !ReviewDemo.isSession(session) else { return }
        guard let client else { return }
        guard let user = try? await client.send(Paths.getCurrentUser).value else { return }
        guard var saved = session else { return }
        saved.userName = user.name ?? saved.userName
        saved.userImageTag = user.primaryImageTag
        session = saved
        persist(saved)
    }

    private func persist(_ session: SavedSession, select: Bool = true) {
        try? vault.save(session, select: select)
        accounts = (try? vault.loadBox())?.accounts ?? [session]
    }

    private func clearLocalSession() {
        prefetchTask?.cancel()
        prefetchTask = nil
        RemoteControlHub.shared.disconnect()
        session = nil
        client = nil
        library = nil
        serverName = nil
        homeLayout = HomeLayout(featured: [], sections: [])
        libraries = []
        homeError = nil
        isLoadingHome = false
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        companionAvailable = false
        isAdministrator = false
        enableSubtitleManagement = false
        tmdbCatalog = JellyfinTmdbCatalog()
        itemDetailMemory = [:]
        playbackLaunchOptions = [:]
        currentSSID = nil
        activeRoute = .remote
        pathMonitor?.cancel()
        pathMonitor = nil
        PluginSettings.clearSeerrSession()
    }

    private func postProfileImage(_ jpeg: Data, userID: String) async throws {
        guard let session, let client else { throw ZelefinError.missingUser }
        guard var url = ServerURL.resolve(base: client.configuration.url, path: "/UserImage") else {
            throw ZelefinError.invalidServerURL
        }
        url = ServerURL.appending([("userId", userID)], to: url)
        let body = JellyfinImagePayload.requestBody(imageJPEG: jpeg)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")
        request.setValue(session.accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(
            "MediaBrowser Client=\"\(DeviceIdentity.clientName)\", Device=\"\(DeviceIdentity.deviceName)\", DeviceId=\"\(session.deviceID)\", Version=\"\(DeviceIdentity.version)\", Token=\"\(session.accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )
        let (data, response) = try await JellyfinNetworking.apiData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZelefinError.server("The server did not accept the photo.")
        }
        if AccessGateway.isChallenge(response: http, data: data) {
            throw ZelefinError.accessGateway
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw Self.profileImageFailure(statusCode: http.statusCode, data: data)
        }
    }

    private static func profileImageFailure(statusCode: Int, data: Data) -> ZelefinError {
        let detail = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let detail, !detail.isEmpty, !detail.hasPrefix("<") {
            return .server("The server did not accept the photo. \(detail)")
        }
        return .server("The server did not accept the photo. (\(statusCode))")
    }

    private func apply(_ saved: SavedSession, client existing: JellyfinClient? = nil, serverVersion: String? = nil) {
        if PluginSettings.shouldClearSession(switchingFrom: session?.accountID, to: saved.accountID) {
            PluginSettings.clearSeerrSession()
        }
        session = saved
        if ReviewDemo.isSession(saved) {
            applyReviewDemo(saved)
            return
        }
        startHomeNetworkMonitor()
        let endpoint = homeNetworkEndpoint(for: saved)
        activeRoute = endpoint.route
        let jellyfin: JellyfinClient
        if let existing, HomeNetworkResolver.isSameEndpoint(existing.configuration.url, endpoint.url) {
            jellyfin = existing
        } else {
            jellyfin = JellyfinNetworking.client(
                url: endpoint.url,
                accessToken: saved.accessToken,
                deviceID: saved.deviceID
            )
        }
        client = jellyfin
        library = JellyfinLibraryClient(client: jellyfin, userID: saved.userID, serverVersion: serverVersion ?? saved.serverVersion)
        serverName = saved.serverName ?? saved.serverURL.host
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        companionAvailable = false
        isAdministrator = false
        enableSubtitleManagement = false
        itemDetailMemory = [:]
        playbackLaunchOptions = [:]
        restoreSnapshot(for: saved)
        Task { await refreshAccount() }
        Task { await refreshSessionCapabilities() }
        Task { await loadHome(force: true) }
        Task { await refreshHomeNetworkSSID() }
        RemoteControlHub.shared.connect(client: jellyfin, session: saved)
        if serverVersion == nil {
            Task { await refreshServerCapabilities(at: endpoint.url) }
        }
    }

    private func applyReviewDemo(_ saved: SavedSession) {
        let jellyfin = JellyfinNetworking.client(
            url: saved.serverURL,
            accessToken: saved.accessToken,
            deviceID: saved.deviceID
        )
        client = jellyfin
        library = ReviewDemo.libraryClient(deviceID: saved.deviceID)
        serverName = saved.serverName
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        companionAvailable = false
        isAdministrator = false
        enableSubtitleManagement = false
        itemDetailMemory = [:]
        playbackLaunchOptions = [:]
        libraries = ReviewDemoCatalog.libraries
        homeLayout = HomeLayout(
            featured: ReviewDemoCatalog.featured,
            sections: HomeLayoutPreferences.assemble(
                resume: ReviewDemoCatalog.continueWatching,
                nextUp: ReviewDemoCatalog.nextUp,
                merge: HomeLayoutPreferences.mergeContinueAndNextUp,
                libraries: [ReviewDemoCatalog.recentlyAddedMovies, ReviewDemoCatalog.recentlyAddedShows],
                collections: ReviewDemoCatalog.collectionsSection,
                genres: ReviewDemoCatalog.genresSection,
                recentlyWatched: ReviewDemoCatalog.recentlyWatched
            )
        )
        homeError = nil
        isLoadingHome = false
        Task { await loadHome(force: true) }
    }

    func saveHomeNetwork(_ profile: HomeNetworkProfile) {
        guard let id = session?.accountID else { return }
        HomeNetworkStore.save(profile, for: id)
        applyHomeNetworkEndpoint()
    }

    func requestHomeNetworkAccess() async {
        await WiFiSSID.requestAccess()
        await refreshHomeNetworkSSID()
    }

    private func startHomeNetworkMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in
                await self?.refreshHomeNetworkSSID()
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.zelefin.home-network"))
        pathMonitor = monitor
    }

    private func refreshHomeNetworkSSID() async {
        currentSSID = await WiFiSSID.current()
        applyHomeNetworkEndpoint()
    }

    private func applyHomeNetworkEndpoint() {
        guard let saved = session, !ReviewDemo.isSession(saved) else { return }
        let endpoint = homeNetworkEndpoint(for: saved)
        activeRoute = endpoint.route
        if let client, HomeNetworkResolver.isSameEndpoint(client.configuration.url, endpoint.url) {
            return
        }
        let jellyfin = JellyfinNetworking.client(
            url: endpoint.url,
            accessToken: saved.accessToken,
            deviceID: saved.deviceID
        )
        client = jellyfin
        library = JellyfinLibraryClient(client: jellyfin, userID: saved.userID, serverVersion: saved.serverVersion)
        RemoteControlHub.shared.connect(client: jellyfin, session: saved)
    }

    private func homeNetworkEndpoint(for saved: SavedSession) -> (url: URL, route: HomeNetworkRoute) {
        let profile = HomeNetworkStore.profile(for: saved.accountID)
        let route = HomeNetworkResolver.route(
            autoSwitch: profile.autoSwitch,
            hasLocalURL: profile.localURL != nil,
            homeSSIDs: profile.homeSSIDs,
            currentSSID: currentSSID,
            ssidReadable: HomeNetworkCapabilities.canMatchSSID
        )
        return (
            HomeNetworkResolver.activeURL(remote: saved.serverURL, local: profile.localURL, route: route),
            route
        )
    }

    private func refreshServerCapabilities(at url: URL) async {
        guard let info = try? await probe.publicInfo(at: url) else { return }
        serverName = info.serverName
        library?.updateServerVersion(info.version)
        guard var saved = session else { return }
        saved.serverVersion = info.version
        saved.serverName = info.serverName
        session = saved
        persist(saved)
    }

    func detectPlugins() async {
        guard let client else {
            introSkipperAvailable = false
            openSubtitlesAvailable = false
            jellyfinEnhancedAvailable = false
            companionAvailable = false
            CompanionSettings.pluginInstalled = false
            return
        }
        let names = await JellyfinPluginCatalog.activeNames(client: client)
        introSkipperAvailable = IntroSkipperPlugin.isInstalled(names: names)
        openSubtitlesAvailable = RemoteSubtitleOffer.pluginAvailable(
            listed: OpenSubtitlesPlugin.isInstalled(names: names),
            catalogNames: names,
            canManageSubtitles: canManageSubtitles,
            canListPlugins: isAdministrator
        )
        if JellyfinEnhancedPlugin.isInstalled(names: names) {
            jellyfinEnhancedAvailable = true
        } else {
            jellyfinEnhancedAvailable = await JellyfinEnhancedClient(client: client).isReachable()
        }
        var companion = ZelefinCompanionPlugin.isInstalled(names: names)
        if !companion {
            companion = await ZelefinCompanionClient(client: client).config() != nil
        }
        companionAvailable = companion
        CompanionSettings.pluginInstalled = companionAvailable
        if companionAvailable {
            await registerCompanionPush()
        }
    }

    func registerPushToken(_ token: String) async {
        guard companionAvailable, let client else { return }
        await ZelefinCompanionClient(client: client).registerDevice(token: token)
    }

    private func registerCompanionPush() async {
        _ = await PushNotificationCenter.requestPermissionIfNeeded()
        if let token = PushNotificationCenter.storedToken {
            await registerPushToken(token)
        }
    }

    func detectIntroSkipper() async {
        await refreshSessionCapabilities()
    }

    func refreshSessionCapabilities() async {
        await refreshAdministratorStatus()
        await detectPlugins()
    }

    func refreshAdministratorStatus() async {
        guard let client else { return }
        do {
            let user = try await client.send(Paths.getCurrentUser).value
            isAdministrator = user.policy?.isAdministrator == true
            enableSubtitleManagement = user.policy?.enableSubtitleManagement == true
            LibraryAlertSettings.lastKnownAdministrator = isAdministrator
        } catch {
            // Keep the last known admin flag so a blip cannot stop session alerts.
        }
    }

    func userAdminClient() throws -> JellyfinUserAdminClient {
        guard isAdministrator, let client else {
            throw ZelefinError.server("Sign in with an administrator to manage users.")
        }
        return JellyfinUserAdminClient(client: client)
    }

    func applyRenamedCurrentUser(_ name: String) {
        guard var saved = session else { return }
        saved.userName = name
        session = saved
        persist(saved)
    }

    func purgeArtworkCache(_ kind: ArtworkImageKind?) {
        if let kind {
            ArtworkCache.shared.remove(kind)
        } else {
            ArtworkCache.shared.removeAll()
        }
    }

    func purgeMetadataCache(_ folder: MetadataCacheFolder?) {
        CacheInventory.removeMetadata(folder)
        if folder == nil || folder == .itemDetail {
            itemDetailMemory = [:]
        }
        if folder == nil || folder == .home {
            homeLayout = HomeLayout(featured: [], sections: [])
            libraries = []
        }
    }

    func refreshMissingMetadata() async {
        await refreshHome()
        if let session {
            startPosterPrefetch(for: session)
        }
    }

    private func refreshTmdbCatalog() async {
        guard let library else {
            tmdbCatalog = JellyfinTmdbCatalog()
            return
        }
        guard tmdbCatalog.movieIDs.isEmpty, tmdbCatalog.seriesIDs.isEmpty else { return }
        tmdbCatalog = await library.tmdbCatalog()
    }

    private func restoreSnapshot(for saved: SavedSession) {
        guard let snapshot = try? snapshotStore.load(userID: saved.userID, serverURL: saved.serverURL) else {
            return
        }
        guard !snapshot.home.sections.isEmpty else { return }
        homeLayout = HomeLayout(
            featured: snapshot.home.featured,
            sections: snapshot.home.sections.filter { !$0.isRecentlyAddedCollections }
        )
        libraries = snapshot.libraries
        homeError = nil
        isLoadingHome = false
    }

    private func persistSnapshot() {
        guard let session, !homeLayout.sections.isEmpty else { return }
        let snapshot = HomeSnapshot(
            version: HomeSnapshot.currentVersion,
            userID: session.userID,
            serverHost: HomeSnapshot.host(from: session.serverURL),
            savedAt: Date(),
            home: homeLayout,
            libraries: libraries
        )
        try? snapshotStore.save(snapshot)
    }

    func cachedItemDetail(itemID: String) -> ItemDetailSnapshot? {
        if let snapshot = itemDetailMemory[itemID] {
            return snapshot
        }
        guard let session else { return nil }
        guard let snapshot = try? itemDetailStore.load(
            userID: session.userID,
            serverURL: session.serverURL,
            itemID: itemID
        ) else {
            return nil
        }
        itemDetailMemory[itemID] = snapshot
        return snapshot
    }

    func persistItemDetail(
        item: MediaItem,
        trailers: [TitleTrailer],
        related: [MediaItem],
        credits: [CreditPerson],
        collections: [ItemCollectionMembership],
        seasons: [MediaItem],
        episodes: [MediaItem],
        selectedSeasonID: String?
    ) {
        guard let session else { return }
        let snapshot = ItemDetailSnapshot(
            version: ItemDetailSnapshot.currentVersion,
            userID: session.userID,
            serverHost: SnapshotCoding.host(from: session.serverURL),
            itemID: item.id,
            savedAt: Date(),
            item: item,
            trailers: trailers,
            related: related,
            credits: credits,
            collections: collections,
            seasons: seasons,
            episodes: episodes,
            selectedSeasonID: selectedSeasonID
        )
        itemDetailMemory[item.id] = snapshot
        try? itemDetailStore.save(snapshot)
    }

    private func loadHome(force: Bool) async {
        guard let library else { return }
        if !force, !homeLayout.sections.isEmpty || isLoadingHome { return }

        homeTask?.cancel()
        let task = Task { [library] in
            await self.fetchHome(using: library)
        }
        homeTask = task
        await task.value
    }

    private func fetchHome(using library: JellyfinLibraryClient) async {
        let showingCachedHome = !homeLayout.sections.isEmpty
        isLoadingHome = !showingCachedHome
        var continueWatching: [MediaItem] = []
        var nextUp: [MediaItem] = []
        var recentlyWatched: [MediaItem] = []
        var featured: [MediaItem] = []
        var librarySections: [HomeSection] = []
        var collections: HomeSection?
        var genres: HomeSection?
        var catalog: [MediaLibrary] = []

        await withTaskGroup(of: JellyfinLibraryClient.HomeChunk.self) { group in
            group.addTask { .continueWatching(await library.resumeItemsIgnoringErrors()) }
            group.addTask { .nextUp(await library.nextUpItemsIgnoringErrors()) }
            group.addTask { .recentlyWatched(await library.recentlyWatchedIgnoringErrors()) }
            group.addTask { .featured(await library.featuredItemsIgnoringErrors()) }
            group.addTask {
                let bundle = await library.libraryHomeIgnoringErrors()
                return .libraryHome(libraries: bundle.libraries, sections: bundle.sections)
            }
            group.addTask { .collections(await library.collectionsSectionIgnoringErrors()) }
            group.addTask { .genres(await library.genresSectionIgnoringErrors()) }

            for await chunk in group {
                if Task.isCancelled { break }
                switch chunk {
                case let .continueWatching(items):
                    continueWatching = items
                case let .nextUp(items):
                    nextUp = items
                case let .recentlyWatched(items):
                    recentlyWatched = items
                case let .featured(items):
                    featured = items
                case let .libraryHome(items, sections):
                    catalog = items
                    librarySections = sections
                case let .collections(section):
                    collections = section
                case let .genres(section):
                    genres = section
                }

                guard !showingCachedHome else { continue }
                publishHome(
                    continueWatching: continueWatching,
                    nextUp: nextUp,
                    featured: featured,
                    librarySections: librarySections,
                    collections: collections,
                    genres: genres,
                    recentlyWatched: recentlyWatched,
                    catalog: catalog,
                    persist: false
                )
            }
        }

        if Task.isCancelled { return }

        publishHome(
            continueWatching: continueWatching,
            nextUp: nextUp,
            featured: featured,
            librarySections: librarySections,
            collections: collections,
            genres: genres,
            recentlyWatched: recentlyWatched,
            catalog: catalog,
            persist: true
        )

        if homeLayout.sections.isEmpty {
            homeError = "The server did not return any titles."
        }
        isLoadingHome = false
        if let session, !ReviewDemo.isSession(session) {
            startPosterPrefetch(for: session)
        }
    }

    private func publishHome(
        continueWatching: [MediaItem],
        nextUp: [MediaItem],
        featured: [MediaItem],
        librarySections: [HomeSection],
        collections: HomeSection?,
        genres: HomeSection?,
        recentlyWatched: [MediaItem],
        catalog: [MediaLibrary],
        persist: Bool
    ) {
        let merge = HomeLayoutPreferences.mergeContinueAndNextUp
        let sections = HomeLayoutPreferences.assemble(
            resume: continueWatching,
            nextUp: nextUp,
            merge: merge,
            libraries: librarySections,
            collections: collections,
            genres: genres,
            recentlyWatched: recentlyWatched
        )

        if !catalog.isEmpty {
            libraries = catalog
        }

        guard !sections.isEmpty else { return }
        homeLayout = HomeLayout(
            featured: featured,
            sections: sections
        )
        homeError = nil
        isLoadingHome = false
        if persist {
            persistSnapshot()
        }
    }
}
