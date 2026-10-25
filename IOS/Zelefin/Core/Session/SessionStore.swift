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
    private(set) var library: (any LibraryServing)?
    /// Silo sign-in waiting for "Who's watching?".
    private(set) var pendingSiloSignIn: SiloPendingSignIn?
    /// Household profiles of the signed-in Silo account, when Zelefin signed in through Silo.
    private(set) var siloProfiles: [SiloProfile] = []
    private(set) var siloAvatarUploadEnabled = false
    private var siloClient: SiloAccountClient?
    private(set) var isRestoring = true
    private(set) var needsFirstRunSetup = false
    private(set) var serverName: String?
    private(set) var homeLayout = HomeLayout(featured: [], sections: [])
    private(set) var libraries: [MediaLibrary] = []
    private(set) var homeError: String?
    /// Set when the server revoked the active session and we signed out
    /// automatically. Shown on the login screen so the user knows why.
    var authNotice: String?
    private(set) var isLoadingHome = false
    private(set) var introSkipperAvailable = false
    /// Whether offline downloads are offered for the active session.
    private(set) var downloadsAvailable = true
    private(set) var openSubtitlesAvailable = false
    private(set) var jellyfinEnhancedAvailable = false
    /// Plugin dashboard switch `Enable "Remove from Continue Watching"`.
    private(set) var jellyfinEnhancedRemoveContinueWatching = false
    private(set) var companionAvailable = false
    private(set) var isAdministrator = false
    private(set) var enableSubtitleManagement = false
    var syncPlayGroupID: String?
    var syncPlayGroupName: String?
    var syncPlayPlaylistItemID: String?
    var pendingPlayerItem: MediaItem?
    /// Last title the player started. Drives the native tab-bar mini player after the full player dismisses.
    /// Persisted per account so it comes back after reopen and cold start.
    var nowPlayingItem: MediaItem? {
        didSet { persistNowPlaying() }
    }
    var incomingSessionMessage: SessionDisplayMessage?
    /// Library tab cards, covers, and counts. Kept for the life of the process so revisiting
    /// the tab does not refetch; a force quit or an account switch starts fresh.
    var libraryPage = LibraryPageCache()

    func presentNowPlaying() {
        guard let nowPlayingItem else { return }
        pendingPlayerItem = nowPlayingItem
    }

    /// Every Play button opens the one root player, so closing it always shrinks into the mini player.
    func presentPlayer(_ item: MediaItem) {
        pendingPlayerItem = item
    }

    func clearNowPlaying() {
        nowPlayingItem = nil
    }

    func rememberNowPlaying(_ item: MediaItem) {
        nowPlayingItem = item
    }

    func updateNowPlayingPosition(_ position: TimeInterval) {
        guard var item = nowPlayingItem, position > 0 else { return }
        item.playbackPosition = position
        nowPlayingItem = item
    }

    var canManageSubtitles: Bool {
        RemoteSubtitleOffer.canManageSubtitles(
            isAdministrator: isAdministrator,
            enableSubtitleManagement: enableSubtitleManagement
        )
    }

    func shouldShowAddSubtitles(for item: MediaItem) -> Bool {
        // Silo's Jellyfin-compatible API delivers subtitles but has no remote subtitle search.
        guard !isSiloServer else { return false }
        return RemoteSubtitleOffer.shouldShowAddSubtitles(
            canManageSubtitles: canManageSubtitles,
            pluginAvailable: openSubtitlesAvailable,
            supportsRemote: item.supportsRemoteSubtitles
        )
    }

    var isDiscoverAvailable: Bool {
        PluginSettings.isSeerrConfigured
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
    private(set) var artworkRevision = 0

    var avatarURL: URL? {
        guard let session else { return nil }
        return avatarURL(for: session)
    }

    func avatarURL(for account: SavedSession) -> URL? {
        if account.accountID == session?.accountID, let link = account.siloLink,
           let avatar = siloProfiles.first(where: { $0.id == link.profileID })?.avatarURL {
            return avatar
        }
        let builder: ArtworkURLBuilder
        if account.isEmbyServer {
            builder = ArtworkURLBuilder(serverURL: account.serverURL, accessToken: account.accessToken)
        } else if let client {
            builder = ArtworkURLBuilder(client: client)
        } else {
            return nil
        }
        let revision = account.accountID == session?.accountID ? avatarRevision : 0
        return builder.userAvatar(
            userID: account.userID,
            tag: account.userImageTag,
            revision: revision
        )
    }

    var isSignedIn: Bool { session != nil && library != nil }

    /// Signed in to a Silo server through its Jellyfin-compatible API, which serves no Jellyfin
    /// administration, SyncPlay, playlists, remote control, or Live TV.
    var isSiloServer: Bool { session?.isSiloServer == true }

    /// Signed in through Silo's own sign-in, so profiles and profile pictures go through Silo.
    var hasSiloLink: Bool { session?.siloLink != nil }

    var currentSiloProfileID: String? { session?.siloLink?.profileID }

    /// Signed in to an Emby server through Emby's own API. There is no Jellyfin `client`.
    var isEmbyServer: Bool { session?.isEmbyServer == true }

    /// Neither Silo's Jellyfin-compatible API nor Emby has SyncPlay, Quick Connect, or Jellyfin
    /// plugins (Zelefin's notifications, Intro Skipper, Jellyfin Enhanced).
    var lacksJellyfinOnlyFeatures: Bool { isSiloServer || isEmbyServer }

    /// Silo serves no Live TV; on Emby it shows only when the server has Live TV turned on.
    var hidesLiveTV: Bool { isSiloServer || (isEmbyServer && !embyLiveTVEnabled) }

    private(set) var embyLiveTVEnabled = false

    var jellyfinLibrary: JellyfinLibraryClient? { library as? JellyfinLibraryClient }

    var embyLibrary: EmbyLibraryClient? { library as? EmbyLibraryClient }

    var liveTVLibrary: (any LiveTVServing)? { library as? any LiveTVServing }

    var remoteSessions: (any RemoteSessionServing)? { library as? any RemoteSessionServing }

    var serverAdmin: (any ServerAdministering)? { library as? any ServerAdministering }

    /// Jellyfin's Open Subtitles plugin, or Emby's own subtitle providers.
    func remoteSubtitleSearcher() -> (any RemoteSubtitleSearching)? {
        if let embyLibrary {
            return EmbySubtitleClient(api: embyLibrary.api, userID: embyLibrary.userID)
        }
        return client.map(OpenSubtitlesClient.init(client:))
    }

    func makePlaybackReporter(for plan: PlaybackPlan) -> (any PlaybackReporting)? {
        guard OfflinePlaybackPolicy.shouldReportToServer(isLocalFile: plan.streamURL.isFileURL) else {
            return nil
        }
        if let embyLibrary {
            return EmbyPlaybackReporter(api: embyLibrary.api, plan: plan)
        }
        if let client {
            return PlaybackReporter(client: client, plan: plan)
        }
        return nil
    }

    var isReviewDemo: Bool { ReviewDemo.isSession(session) }

    var homeNetworkProfile: HomeNetworkProfile {
        guard let id = session?.accountID else { return HomeNetworkProfile() }
        return HomeNetworkStore.profile(for: id)
    }

    var activeServerURL: URL? {
        client?.configuration.url ?? embyLibrary?.api.serverURL ?? session?.serverURL
    }

    var otherAccounts: [SavedSession] {
        accounts.filter { $0.accountID != session?.accountID }
    }

    func restore() async {
        defer { isRestoring = false }
        guard let box = try? vault.loadBox() else { return }
        if box.retiredSiloAccounts > 0 {
            try? vault.persist(box)
            authNotice = "Silo now signs in through its Jellyfin-compatible API. Sign in again."
        }
        guard let saved = box.current else { return }
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
            password: password,
            serverType: current.isEmbyServer ? .emby : .jellyfin
        )
    }

    func connect(
        serverAddress: String,
        username: String,
        password: String,
        serverType: SignInServerType = .jellyfin
    ) async throws {
        let url = try probe.normalizedURL(from: serverAddress)
        if serverType == .emby {
            try await connectEmby(url: url, username: username, password: password)
            return
        }
        let isSiloMainAddress = await SiloAccountClient.isSiloAddress(url)
        switch serverType {
        case .silo:
            if isSiloMainAddress {
                try await startSiloSignIn(url: url, username: username, password: password)
                return
            }
            guard await probe.isSiloServer(at: url) else {
                throw ZelefinError.server("This isn't a Silo server. Choose Jellyfin, or check the address.")
            }
        case .jellyfin:
            if isSiloMainAddress {
                throw ZelefinError.server("This is Silo's main address. Choose Silo, or enter Silo's Jellyfin-compatible address.")
            }
            if await EmbyAPI.isEmbyServer(at: url) {
                throw ZelefinError.server("This is an Emby server. Choose Emby.")
            }
        case .emby:
            break
        }
        let info = try await probe.publicInfo(at: url)
        let isSilo = await probe.isSiloServer(at: url)
        let deviceID = DeviceIdentity.deviceID()
        let jellyfin = JellyfinNetworking.client(url: url, deviceID: deviceID)
        let auth = try await jellyfin.signIn(username: username, password: password)
        try completeSignIn(
            auth,
            serverURL: url,
            info: info,
            isSiloServer: isSilo,
            deviceID: deviceID,
            fallbackName: username,
            client: jellyfin
        )
    }

    private func connectEmby(url: URL, username: String, password: String) async throws {
        let info: EmbyPublicInfo
        do {
            info = try await EmbyAPI.publicInfo(at: url)
        } catch ZelefinError.accessGateway {
            throw ZelefinError.accessGateway
        } catch {
            throw ZelefinError.server("This isn't an Emby server. Choose Jellyfin, or check the address.")
        }
        guard info.isEmby else {
            throw ZelefinError.server("This isn't an Emby server. Choose Jellyfin, or check the address.")
        }
        let deviceID = DeviceIdentity.deviceID()
        let auth = try await EmbyAPI.authenticate(url: url, username: username, password: password, deviceID: deviceID)
        let saved = SavedSession(
            serverURL: url,
            accessToken: auth.accessToken,
            userID: auth.user.id,
            userName: auth.user.name ?? username,
            deviceID: deviceID,
            userImageTag: auth.user.primaryImageTag,
            serverVersion: info.version,
            serverName: info.serverName,
            serverKind: .emby
        )
        serverName = info.serverName
        apply(saved, serverVersion: info.version)
        persist(saved)
        beginFirstRunSetupIfNeeded(for: saved)
    }

    /// Silo's own sign-in: the account, its household profiles, and where its Jellyfin-compatible API is.
    private func startSiloSignIn(url: URL, username: String, password: String) async throws {
        let client = SiloAccountClient(baseURL: url)
        try await client.login(username: username, password: password)
        async let collection = client.profiles()
        async let info = client.connectInfo()
        let compatURL = try await info.compatibleURL()
        let profiles = try await collection
        pendingSiloSignIn = SiloPendingSignIn(
            client: client,
            nativeURL: url,
            compatURL: compatURL,
            profiles: profiles.items,
            avatarUploadEnabled: profiles.avatarUploadEnabled
        )
    }

    func cancelSiloProfilePick() {
        if let client = pendingSiloSignIn?.client {
            Task { await client.logout() }
        }
        pendingSiloSignIn = nil
    }

    func selectSiloProfile(_ profile: SiloProfile, pin: String?) async throws {
        guard let pending = pendingSiloSignIn else { throw ZelefinError.missingUser }
        try await signInSiloProfile(
            profile,
            pin: pin,
            client: pending.client,
            nativeURL: pending.nativeURL,
            compatURL: pending.compatURL,
            replacing: nil
        )
        siloProfiles = pending.profiles
        siloAvatarUploadEnabled = pending.avatarUploadEnabled
        pendingSiloSignIn = nil
    }

    /// Switches the Silo account to another household profile without the password.
    func switchSiloProfile(_ profile: SiloProfile, pin: String?) async throws {
        guard let current = session, let link = current.siloLink, let client = siloClient else {
            throw ZelefinError.missingUser
        }
        guard profile.id != link.profileID else { return }
        try await signInSiloProfile(
            profile,
            pin: pin,
            client: client,
            nativeURL: link.nativeURL,
            compatURL: current.serverURL,
            replacing: current
        )
    }

    /// Approves a Jellyfin Quick Connect code for the profile through Silo's own API, then
    /// collects it, so the Jellyfin-compatible session belongs to exactly that profile.
    private func signInSiloProfile(
        _ profile: SiloProfile,
        pin: String?,
        client: SiloAccountClient,
        nativeURL: URL,
        compatURL: URL,
        replacing previous: SavedSession?
    ) async throws {
        var profileToken: String?
        if profile.hasPin {
            let trimmed = pin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { throw ZelefinError.server("Enter this profile's PIN.") }
            profileToken = try await client.verifyPIN(profileID: profile.id, pin: trimmed)
        }
        let info = try await probe.publicInfo(at: compatURL)
        let deviceID = DeviceIdentity.deviceID()
        let jellyfin = JellyfinNetworking.client(url: compatURL, deviceID: deviceID)
        let handshake = try await QuickConnectClient.start(on: jellyfin)
        try await client.approveHandoff(code: handshake.code, profileID: profile.id, profileToken: profileToken)
        let secret = try await QuickConnectClient.waitUntilAuthorized(
            handshake,
            on: jellyfin,
            pollInterval: .milliseconds(500),
            maximumPolls: 40
        )
        let auth = try await jellyfin.signIn(quickConnectSecret: secret)
        let link = SiloLink(
            nativeURL: nativeURL,
            accessToken: await client.accessToken,
            refreshToken: await client.refreshToken,
            profileID: profile.id,
            profileName: profile.name,
            profileHasPin: profile.hasPin,
            profileToken: profileToken
        )
        try completeSignIn(
            auth,
            serverURL: compatURL,
            info: info,
            isSiloServer: true,
            siloLink: link,
            deviceID: deviceID,
            fallbackName: profile.name,
            client: jellyfin
        )
        guard let previous, previous.accountID != session?.accountID else { return }
        if var box = try? vault.loadBox() {
            _ = box.remove(id: previous.accountID)
            if let session { box.upsert(session) }
            try? vault.persist(box)
            accounts = box.accounts
        }
        let stale = JellyfinNetworking.client(
            url: previous.serverURL,
            accessToken: previous.accessToken,
            deviceID: previous.deviceID
        )
        Task { try? await stale.signOut() }
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
        if await SiloAccountClient.isSiloAddress(url) {
            throw ZelefinError.siloNativeAddress
        }
        if await EmbyAPI.isEmbyServer(at: url) {
            throw ZelefinError.server("This is an Emby server. Choose Emby.")
        }
        let info = try await probe.publicInfo(at: url)
        let isSilo = await probe.isSiloServer(at: url)
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
            isSiloServer: isSilo,
            deviceID: deviceID,
            fallbackName: auth.user?.name ?? "User",
            client: jellyfin
        )
    }

    private func completeSignIn(
        _ auth: AuthenticationResult,
        serverURL: URL,
        info: PublicSystemInfo,
        isSiloServer: Bool,
        siloLink: SiloLink? = nil,
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
            userName: siloLink?.profileName
                ?? SavedSession.displayName(user.name ?? fallbackName, isSiloServer: isSiloServer),
            deviceID: deviceID,
            userImageTag: user.primaryImageTag,
            serverVersion: info.version,
            serverName: info.serverName,
            isSiloServer: isSiloServer,
            siloLink: siloLink
        )
        serverName = info.serverName
        apply(saved, client: jellyfin, serverVersion: info.version)
        persist(saved)
        beginFirstRunSetupIfNeeded(for: saved)
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
        if let silo = siloClient {
            Task { await silo.logout() }
        }
        let remote = client
        let emby = embyLibrary?.api
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
            await emby?.signOut()
        }
    }

    func changePassword(current: String, new: String) async throws {
        let currentPassword = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPassword = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            throw ZelefinError.server("Enter your current password and a new password.")
        }
        if let embyLibrary {
            try await embyLibrary.changePassword(current: currentPassword, new: newPassword)
            return
        }
        guard let client, let session else { throw ZelefinError.missingUser }
        _ = try await client.send(
            Paths.updateUserPassword(
                userID: session.userID,
                .init(currentPw: currentPassword, newPw: newPassword)
            )
        )
    }

    func updateProfileImage(_ jpeg: Data) async throws {
        if let link = session?.siloLink, let siloClient {
            guard jpeg.count <= 10 * 1_024 * 1_024 else {
                throw ZelefinError.server("Choose a photo smaller than 10 MB.")
            }
            let updated = try await siloClient.uploadAvatar(
                profileID: link.profileID,
                profileToken: link.profileToken,
                jpeg: jpeg
            )
            replaceSiloProfile(updated)
            avatarRevision += 1
            return
        }
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await updateProfileImage(userID: userID, jpeg: jpeg)
    }

    func updateProfileImage(userID: String, jpeg: Data) async throws {
        guard !jpeg.isEmpty else {
            throw ZelefinError.server("Zelefin could not read that photo.")
        }
        try ensureCanChangePhoto(of: userID)
        if let embyLibrary {
            try await embyLibrary.uploadUserImage(userID: userID, jpeg: jpeg)
        } else {
            try await postProfileImage(jpeg, userID: userID)
        }
        if userID == session?.userID {
            avatarRevision += 1
            await refreshAccount()
        }
    }

    func removeProfileImage() async throws {
        if let link = session?.siloLink, let siloClient {
            let current = siloProfiles.first(where: { $0.id == link.profileID })
            if current?.hasUploadedAvatar == true {
                try await siloClient.deleteAvatar(profileID: link.profileID, profileToken: link.profileToken)
                await refreshSiloProfiles()
            } else {
                replaceSiloProfile(
                    try await siloClient.setAvatarPreset(profileID: link.profileID, profileToken: link.profileToken, preset: nil)
                )
            }
            avatarRevision += 1
            return
        }
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await removeProfileImage(userID: userID)
    }

    func removeProfileImage(userID: String) async throws {
        try ensureCanChangePhoto(of: userID)
        if let embyLibrary {
            try await embyLibrary.deleteUserImage(userID: userID)
        } else {
            guard let client else { throw ZelefinError.missingUser }
            _ = try await client.send(Paths.deleteUserImage(userID: userID))
        }
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
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        let surface = JellyfinEnhancedHomeHide.surface(queueKind: item.queueKind)
        if surface == .continueWatching, !jellyfinEnhancedRemoveContinueWatching {
            throw ZelefinError.server("Remove from Continue Watching is turned off in Jellyfin Enhanced.")
        }
        HomeQueueHideStore.insert(item.id, userID: userID, surface: surface)
        removeFromHome(itemID: item.id)
        do {
            try await JellyfinEnhancedClient(client: client).hideFromHome(itemID: item.id, surface: surface)
        } catch {
            HomeQueueHideStore.remove(item.id, userID: userID)
            Task { await refreshHome() }
            throw error
        }
        Task { await refreshHome() }
    }

    func noteHomeQueueResumed(_ itemID: String) {
        guard let userID = session?.userID else { return }
        HomeQueueHideStore.remove(itemID, userID: userID)
    }

    func toggleFavorite(_ item: MediaItem) async throws -> MediaItem {
        guard let library else { throw ZelefinError.missingUser }
        let next = !item.isFavorite
        let saved = try await library.markFavorite(itemID: item.id, isFavorite: next)
        return item.withFavorite(saved)
    }

    func toggleWatchlist(_ item: MediaItem) async throws -> MediaItem {
        guard let library else { throw ZelefinError.missingUser }
        let next = !item.isWatchlisted
        try await library.setWatchlisted(itemID: item.id, watchlisted: next)
        return item.withWatchlisted(next)
    }

    func setLikes(_ item: MediaItem, likes: Bool?) async throws -> MediaItem {
        guard let library else { throw ZelefinError.missingUser }
        let saved = try await library.setLikes(itemID: item.id, likes: likes)
        return item.withLikes(saved)
    }

    func playOnSession(sessionID: String, item: MediaItem) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.playOnSession(
            sessionID: sessionID,
            itemIDs: [item.id],
            startPosition: item.playbackPosition > 5 ? item.playbackPosition : nil
        )
    }

    func pullDisplayPreferences() async {
        guard let library, !isReviewDemo else { return }
        guard let prefs = try? await library.displayPreferenceCustomPrefs() else { return }
        DisplayPreferencesSync.apply(prefs)
    }

    func pushDisplayPreferences() async {
        guard let library, !isReviewDemo else { return }
        try? await library.updateDisplayPreferenceCustomPrefs(DisplayPreferencesSync.customPrefs())
    }

    func noteSyncPlayJoined(groupID: String?, name: String?) {
        syncPlayGroupID = groupID
        if let name, !name.isEmpty {
            syncPlayGroupName = name
        }
    }

    func noteSyncPlayLeft() {
        syncPlayGroupID = nil
        syncPlayGroupName = nil
        syncPlayPlaylistItemID = nil
    }

    func noteSyncPlayPlaylistItem(_ playlistItemID: String?) {
        syncPlayPlaylistItemID = playlistItemID
    }

    func createSyncPlayGroup(name: String) async throws {
        guard let library else { throw ZelefinError.missingUser }
        let group = try await library.syncPlayCreateGroup(name: name)
        syncPlayGroupID = group.id
        syncPlayGroupName = group.name
    }

    func joinSyncPlayGroup(_ group: SyncPlayGroupInfo) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.syncPlayJoinGroup(id: group.id)
        syncPlayGroupID = group.id
        syncPlayGroupName = group.name
    }

    func leaveSyncPlayGroup() async throws {
        try await library?.syncPlayLeaveGroup()
        noteSyncPlayLeft()
    }

    /// Regular Play while already in a group should queue the title for everyone.
    @discardableResult
    func playIfSyncPlay(_ item: MediaItem) -> Bool {
        guard syncPlayGroupID != nil, !lacksJellyfinOnlyFeatures else { return false }
        Task { try? await playInSyncPlay(item) }
        return true
    }

    func playInSyncPlay(_ item: MediaItem, createGroupNamed name: String? = nil) async throws {
        if let name, syncPlayGroupID == nil {
            try await createSyncPlayGroup(name: name)
        }
        guard syncPlayGroupID != nil, let library else {
            throw ZelefinError.server("Join or create a SyncPlay group first.")
        }
        try await library.syncPlaySetQueue(
            itemIDs: [item.id],
            startPosition: item.playbackPosition > 5 ? item.playbackPosition : 0
        )
        pendingPlayerItem = item
    }

    func forwardSyncPlay(_ action: RemotePlaybackAction) async {
        guard syncPlayGroupID != nil, let library else { return }
        do {
            switch action {
            case .pause:
                try await library.syncPlayPause()
            case .play, .playPause:
                try await library.syncPlayUnpause()
            case .seek(let time):
                try await library.syncPlaySeek(to: time)
                try? await library.syncPlayReady(
                    isPlaying: true,
                    playlistItemID: syncPlayPlaylistItemID,
                    position: time
                )
            case .stop:
                try await library.syncPlayStop()
            default:
                break
            }
        } catch {
            // Keep local playback going if the group command fails.
        }
    }

    func presentSyncPlayItem(id: String, start: TimeInterval? = nil) async {
        guard let loaded = try? await library?.item(id: id) else { return }
        var item = loaded
        if let start {
            item.playbackPosition = start
        }
        if pendingPlayerItem?.id != item.id {
            pendingPlayerItem = item
        } else if let start {
            var current = pendingPlayerItem
            current?.playbackPosition = start
            pendingPlayerItem = current
        }
    }

    private func removeFromHome(itemID: String) {
        homeLayout = HomeLayoutPreferences.removing(itemID, from: homeLayout)
        persistSnapshot()
    }

    private func refreshAccount() async {
        guard !ReviewDemo.isSession(session) else { return }
        if let embyLibrary {
            guard let user = try? await embyLibrary.currentUser(), var saved = session, saved.isEmbyServer else { return }
            if let name = user.name { saved.userName = name }
            saved.userImageTag = user.primaryImageTag
            session = saved
            persist(saved)
            return
        }
        guard let client else { return }
        guard let user = try? await client.send(Paths.getCurrentUser).value else { return }
        guard var saved = session else { return }
        if let link = saved.siloLink {
            saved.userName = link.profileName
        } else if let name = user.name {
            saved.userName = SavedSession.displayName(name, isSiloServer: saved.isSiloServer)
        }
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
        incomingSessionMessage = nil
        session = nil
        client = nil
        library = nil
        siloClient = nil
        siloProfiles = []
        siloAvatarUploadEnabled = false
        pendingSiloSignIn = nil
        serverName = nil
        homeLayout = HomeLayout(featured: [], sections: [])
        libraries = []
        homeError = nil
        isLoadingHome = false
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        isAdministrator = false
        embyLiveTVEnabled = false
        enableSubtitleManagement = false
        syncPlayGroupID = nil
        syncPlayGroupName = nil
        syncPlayPlaylistItemID = nil
        pendingPlayerItem = nil
        nowPlayingItem = nil
        needsFirstRunSetup = false
        tmdbCatalog = JellyfinTmdbCatalog()
        itemDetailMemory = [:]
        libraryPage = LibraryPageCache()
        playbackLaunchOptions = [:]
        currentSSID = nil
        activeRoute = .remote
        pathMonitor?.cancel()
        pathMonitor = nil
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

    private func apply(
        _ saved: SavedSession,
        client existing: JellyfinClient? = nil,
        serverVersion: String? = nil
    ) {
        if PluginSettings.shouldClearSession(switchingFrom: session?.accountID, to: saved.accountID) {
            PluginSettings.clearSeerrSession()
        } else if PluginSettings.seerrSession != nil, PluginSettings.seerrOwnerAccountID == nil {
            PluginSettings.seerrOwnerAccountID = saved.accountID
        }
        // Landing in a working session clears any stale "session expired" notice.
        authNotice = nil
        session = saved
        restoreNowPlaying()
        if ReviewDemo.isSession(saved) {
            applyReviewDemo(saved)
            return
        }
        applySiloLink(saved)
        startHomeNetworkMonitor()
        let endpoint = homeNetworkEndpoint(for: saved)
        activeRoute = endpoint.route
        let jellyfin: JellyfinClient?
        if saved.isEmbyServer {
            jellyfin = nil
            library = Self.makeEmbyLibrary(for: saved, url: endpoint.url)
        } else if let existing, HomeNetworkResolver.isSameEndpoint(existing.configuration.url, endpoint.url) {
            jellyfin = existing
        } else {
            jellyfin = JellyfinNetworking.client(
                url: endpoint.url,
                accessToken: saved.accessToken,
                deviceID: saved.deviceID
            )
        }
        client = jellyfin
        if let jellyfin {
            library = JellyfinLibraryClient(client: jellyfin, userID: saved.userID, serverVersion: serverVersion ?? saved.serverVersion)
        }
        serverName = saved.serverName ?? saved.serverURL.host
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        isAdministrator = false
        embyLiveTVEnabled = false
        enableSubtitleManagement = false
        itemDetailMemory = [:]
        libraryPage = LibraryPageCache()
        playbackLaunchOptions = [:]
        restoreSnapshot(for: saved)
        Task { await refreshAccount() }
        Task { await refreshSessionCapabilities() }
        Task { await pullDisplayPreferences() }
        Task { await loadHome(force: true) }
        Task { await refreshHomeNetworkSSID() }
        if let jellyfin {
            RemoteControlHub.shared.connect(client: jellyfin, session: saved)
        } else if let embyLibrary {
            RemoteControlHub.shared.connect(emby: embyLibrary.api)
        }
        Task { await refreshServerCapabilities(at: endpoint.url) }
    }

    private static func makeEmbyLibrary(for saved: SavedSession, url: URL) -> EmbyLibraryClient {
        EmbyLibraryClient(
            api: EmbyAPI(serverURL: url, accessToken: saved.accessToken, deviceID: saved.deviceID),
            userID: saved.userID
        )
    }

    private func applySiloLink(_ saved: SavedSession) {
        guard let link = saved.siloLink else {
            siloClient = nil
            siloProfiles = []
            siloAvatarUploadEnabled = false
            return
        }
        let client = SiloAccountClient(
            baseURL: link.nativeURL,
            accessToken: link.accessToken,
            refreshToken: link.refreshToken
        )
        siloClient = client
        let accountID = saved.accountID
        Task {
            await client.setTokenHandler { [weak self] access, refresh in
                Task { @MainActor in
                    self?.storeSiloTokens(access: access, refresh: refresh, accountID: accountID)
                }
            }
            await refreshSiloProfiles()
        }
    }

    private func storeSiloTokens(access: String, refresh: String, accountID: String) {
        guard var saved = session, saved.accountID == accountID, var link = saved.siloLink else { return }
        link.accessToken = access
        link.refreshToken = refresh
        saved.siloLink = link
        session = saved
        persist(saved)
    }

    /// Picks one of Silo's preset avatars (DiceBear styles) for the current profile.
    func updateSiloAvatarPreset(_ presetID: String) async throws {
        guard let link = session?.siloLink, let siloClient else { throw ZelefinError.missingUser }
        replaceSiloProfile(
            try await siloClient.setAvatarPreset(
                profileID: link.profileID,
                profileToken: link.profileToken,
                preset: SiloProfileAvatars.presetRef(presetID)
            )
        )
        avatarRevision += 1
    }

    private func replaceSiloProfile(_ updated: SiloProfile) {
        if let index = siloProfiles.firstIndex(where: { $0.id == updated.id }) {
            siloProfiles[index] = updated
        } else {
            siloProfiles.append(updated)
        }
    }

    func refreshSiloProfiles() async {
        guard let siloClient, let collection = try? await siloClient.profiles() else { return }
        siloProfiles = collection.items
        siloAvatarUploadEnabled = collection.avatarUploadEnabled
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
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        isAdministrator = false
        embyLiveTVEnabled = false
        enableSubtitleManagement = false
        itemDetailMemory = [:]
        libraryPage = LibraryPageCache()
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
        if saved.isEmbyServer {
            if let embyLibrary, HomeNetworkResolver.isSameEndpoint(embyLibrary.api.serverURL, endpoint.url) {
                return
            }
            let emby = Self.makeEmbyLibrary(for: saved, url: endpoint.url)
            library = emby
            RemoteControlHub.shared.connect(emby: emby.api)
            return
        }
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
        if isEmbyServer {
            guard let info = try? await EmbyAPI.publicInfo(at: url), var saved = session, saved.isEmbyServer else { return }
            serverName = info.serverName ?? serverName
            saved.serverVersion = info.version ?? saved.serverVersion
            saved.serverName = info.serverName ?? saved.serverName
            session = saved
            persist(saved)
            return
        }
        guard let info = try? await probe.publicInfo(at: url) else { return }
        let isSilo = await probe.isSiloServer(at: url)
        serverName = info.serverName
        library?.updateServerVersion(info.version)
        guard var saved = session else { return }
        let flavorChanged = saved.isSiloServer != isSilo
        saved.serverVersion = info.version
        saved.serverName = info.serverName
        saved.isSiloServer = isSilo
        session = saved
        persist(saved)
        if flavorChanged {
            await refreshSessionCapabilities()
        }
    }

    func beginFirstRunSetupIfNeeded(for saved: SavedSession) {
        guard !ReviewDemo.isSession(saved) else {
            needsFirstRunSetup = false
            return
        }
        needsFirstRunSetup = !FirstRunSetupStore.hasCompleted(accountID: saved.accountID)
    }

    func completeFirstRunSetup() {
        if let id = session?.accountID {
            FirstRunSetupStore.markCompleted(accountID: id)
        }
        needsFirstRunSetup = false
    }

    func applyPlaybackLanguages(audioCode: String, subtitleCode: String) async {
        PlaybackPreferences.audioLanguageCode = audioCode
        PlaybackPreferences.subtitleLanguageCode = subtitleCode
        let audio = audioCode == PlaybackLanguage.automaticCode ? "" : ServerLanguageCode.toServer(audioCode)
        let subtitle = (subtitleCode == PlaybackLanguage.automaticCode || subtitleCode == PlaybackLanguage.offCode)
            ? ""
            : ServerLanguageCode.toServer(subtitleCode)
        let mode: SubtitlePlaybackMode = subtitleCode == PlaybackLanguage.offCode
            ? .none
            : subtitle.isEmpty ? .default : .smart
        if let embyLibrary {
            var preferences = JellyfinPlaybackPreferences()
            preferences.audioLanguage = ServerLanguageCode.fromServer(audio)
            preferences.playDefaultAudioTrack = audio.isEmpty
            preferences.subtitleLanguage = ServerLanguageCode.fromServer(subtitle)
            preferences.subtitleMode = mode
            try? await embyLibrary.updatePlaybackPreferences(preferences)
            return
        }
        guard let client, let userID = session?.userID else { return }
        var config = (try? await client.send(Paths.getCurrentUser).value.configuration) ?? UserConfiguration()
        config.audioLanguagePreference = audio
        config.isPlayDefaultAudioTrack = audio.isEmpty
        config.subtitleLanguagePreference = subtitle
        config.subtitleMode = mode
        _ = try? await client.send(Paths.updateUserConfiguration(userID: userID, config))
    }

    func jellyfinPlaybackPreferences() async throws -> JellyfinPlaybackPreferences {
        if let embyLibrary {
            return JellyfinPlaybackPreferences(configuration: try await embyLibrary.userConfiguration())
        }
        guard let client else {
            throw ZelefinError.server("Sign in to a Jellyfin server to change these settings.")
        }
        let config = try await client.send(Paths.getCurrentUser).value.configuration ?? UserConfiguration()
        return JellyfinPlaybackPreferences(configuration: config)
    }

    /// Jellyfin picks the starting streams from these, so the device-side language picks
    /// step aside; otherwise an older local pick would override what the user just chose.
    func saveJellyfinPlaybackPreferences(_ preferences: JellyfinPlaybackPreferences) async throws {
        if let embyLibrary {
            try await embyLibrary.updatePlaybackPreferences(preferences)
            PlaybackPreferences.audioLanguageCode = PlaybackLanguage.automaticCode
            PlaybackPreferences.subtitleLanguageCode = PlaybackLanguage.automaticCode
            return
        }
        guard let client, let userID = session?.userID else {
            throw ZelefinError.server("Sign in to a Jellyfin server to change these settings.")
        }
        let current = try await client.send(Paths.getCurrentUser).value.configuration ?? UserConfiguration()
        _ = try await client.send(Paths.updateUserConfiguration(userID: userID, preferences.applying(to: current)))
        PlaybackPreferences.audioLanguageCode = PlaybackLanguage.automaticCode
        PlaybackPreferences.subtitleLanguageCode = PlaybackLanguage.automaticCode
    }

    func installZelefinPlugin() async throws {
        guard isAdministrator, let client, !isSiloServer else {
            throw ZelefinError.server("Sign in as a Jellyfin administrator to install the Zelefin plugin.")
        }
        try await ZelefinPluginInstaller(client: client).install()
        await detectPlugins()
    }

    func restartJellyfinAfterPluginInstall() async throws {
        guard isAdministrator, let client, !isSiloServer else {
            throw ZelefinError.server("Sign in as a Jellyfin administrator to restart this server.")
        }
        try await ZelefinPluginInstaller(client: client).restartServer()
    }

    func detectPlugins() async {
        guard let client else {
            introSkipperAvailable = false
            // Emby searches subtitles with its own providers; there is no plugin to look for.
            openSubtitlesAvailable = isEmbyServer && canManageSubtitles
            jellyfinEnhancedAvailable = false
            jellyfinEnhancedRemoveContinueWatching = false
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
        if jellyfinEnhancedAvailable {
            jellyfinEnhancedRemoveContinueWatching = await JellyfinEnhancedClient(client: client)
                .removeContinueWatchingEnabled()
        } else {
            jellyfinEnhancedRemoveContinueWatching = false
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
        guard companionAvailable, LibraryAlertSettings.isEnabled, let client else { return }
        await ZelefinCompanionClient(client: client).registerDevice(token: token)
    }

    /// Registers this iPhone again, then asks the plugin to push a test alert to it.
    func sendCompanionTestAlert() async -> String? {
        guard companionAvailable, let client else { return "Install the Zelefin plugin first." }
        guard let token = PushNotificationCenter.storedToken else {
            return "This iPhone has no push token yet. Turn Notifications off and on, then try again."
        }
        let companion = ZelefinCompanionClient(client: client)
        await companion.registerDevice(token: token)
        return await companion.sendTest()
    }

    func registerCompanionPushIfNeeded() async {
        guard companionAvailable else { return }
        await registerCompanionPush()
    }

    /// Removes this phone from the plugin so it stops sending alerts here. The Notifications
    /// switch calls this; the plugin only knows the switch is off once the row is gone.
    func unregisterCompanionPush() async {
        guard let client else { return }
        await ZelefinCompanionClient(client: client).deleteDevice()
    }

    private func registerCompanionPush() async {
        guard LibraryAlertSettings.isEnabled else { return }
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
        downloadsAvailable = await (library?.downloadsAvailable() ?? true)
        if let embyLibrary {
            embyLiveTVEnabled = (try? await embyLibrary.liveTVInfoEnabled()) ?? false
        }
    }

    func refreshAdministratorStatus() async {
        if let embyLibrary {
            guard let user = try? await embyLibrary.currentUser() else { return }
            isAdministrator = user.policy?.isAdministrator == true
            enableSubtitleManagement = user.policy?.enableSubtitleManagement == true
            return
        }
        guard let client else { return }
        do {
            let user = try await client.send(Paths.getCurrentUser).value
            // Silo's Jellyfin-compatible API has no administration routes, so its admins get none of Zelefin's server tools.
            isAdministrator = user.policy?.isAdministrator == true && !isSiloServer
            enableSubtitleManagement = user.policy?.enableSubtitleManagement == true
        } catch {
            // Keep the last known admin flag so a blip cannot hide admin tools.
        }
    }

    func userAdminClient() throws -> any UserAdministering {
        guard isAdministrator else {
            throw ZelefinError.server("Sign in with an administrator to manage users.")
        }
        if let embyLibrary {
            return EmbyUserAdminClient(api: embyLibrary.api)
        }
        guard let client else {
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
        artworkRevision += 1
    }

    /// Jellyfin keeps the same image URL after a replace until tags change, so
    /// evict the cached bytes and ask on-screen posters to load again.
    func noteLibraryArtworkChanged(for item: MediaItem, refreshed: MediaItem? = nil) {
        evictArtwork(for: item)
        if let refreshed {
            evictArtwork(for: refreshed)
            homeLayout = homeLayout.replacing(refreshed)
            if var snapshot = itemDetailMemory[refreshed.id] {
                snapshot.item = refreshed
                itemDetailMemory[refreshed.id] = snapshot
            }
        }
        artworkRevision += 1
    }

    private func evictArtwork(for item: MediaItem) {
        guard let library else { return }
        var urls = library.cacheableArtworkURLs(for: item)
        for height in [480, 900] {
            if let url = library.primaryURL(for: item, maxHeight: height) {
                urls.append(url)
            }
        }
        ArtworkCache.shared.remove(urls: urls)
    }

    func purgeMetadataCache(_ folder: MetadataCacheFolder?) {
        CacheInventory.removeMetadata(folder)
        if folder == nil || folder == .itemDetail {
            itemDetailMemory = [:]
        }
        if folder == nil || folder == .home {
            homeLayout = HomeLayout(featured: [], sections: [])
            libraries = []
            libraryPage = LibraryPageCache()
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
        extras: [TitleExtra] = [],
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
            extras: extras,
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

    private func fetchHome(using library: any LibraryServing) async {
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
        var recommendations: [HomeSection] = []
        var upcoming: [MediaItem] = []

        await withTaskGroup(of: HomeFeedChunk.self) { group in
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
            group.addTask { .recommendations(await library.movieRecommendationsIgnoringErrors()) }
            group.addTask { .upcoming(await library.upcomingEpisodesIgnoringErrors()) }

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
                case let .recommendations(sections):
                    recommendations = sections
                case let .upcoming(items):
                    upcoming = items
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
                    recommendations: recommendations,
                    upcoming: upcoming,
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
            recommendations: recommendations,
            upcoming: upcoming,
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
        recommendations: [HomeSection],
        upcoming: [MediaItem],
        persist: Bool
    ) {
        let continueWatching = HomeQueueHideStore.filter(
            continueWatching,
            userID: session?.userID,
            surface: .continueWatching
        )
        let nextUp = HomeQueueHideStore.filter(
            nextUp,
            userID: session?.userID,
            surface: .nextUp
        )
        let merge = HomeLayoutPreferences.mergeContinueAndNextUp
        let sections = HomeLayoutPreferences.assemble(
            resume: continueWatching,
            nextUp: nextUp,
            merge: merge,
            libraries: librarySections,
            collections: collections,
            genres: genres,
            recentlyWatched: recentlyWatched,
            recommendations: recommendations,
            upcoming: upcoming
        )

        if !catalog.isEmpty {
            libraries = catalog
        }

        guard !sections.isEmpty else { return }
        homeLayout = HomeLayout(
            featured: HomeLayoutPreferences.hero(
                recentlyAdded: featured,
                continueWatching: continueWatching,
                nextUp: nextUp,
                recentlyWatched: recentlyWatched,
                recommendations: recommendations
            ),
            sections: sections
        )
        homeError = nil
        isLoadingHome = false
        if persist {
            persistSnapshot()
        }
    }

    private func persistNowPlaying() {
        guard let accountID = session?.accountID else { return }
        NowPlayingStore.save(nowPlayingItem, for: accountID)
    }

    private func restoreNowPlaying() {
        nowPlayingItem = session.flatMap { NowPlayingStore.item(for: $0.accountID) }
    }
}

struct LibraryPageCache: Equatable, Sendable {
    var catalog: [MediaLibrary] = []
    var covers: [String: [MediaItem]] = [:]
    var roomCounts: [String: LibraryRoomCounts] = [:]
    var catalogCounts: ServerCatalogCounts?
    var detailedLibraryIDs: Set<String> = []
    var isLoaded = false
}

enum NowPlayingStore: Sendable {
    static func item(for accountID: String, defaults: UserDefaults = .standard) -> MediaItem? {
        guard let data = defaults.data(forKey: key(accountID)) else { return nil }
        return try? JSONDecoder().decode(MediaItem.self, from: data)
    }

    static func save(_ item: MediaItem?, for accountID: String, defaults: UserDefaults = .standard) {
        guard let item, let data = try? JSONEncoder().encode(item) else {
            defaults.removeObject(forKey: key(accountID))
            return
        }
        defaults.set(data, forKey: key(accountID))
    }

    static func key(_ accountID: String) -> String {
        "zelefin.now-playing.\(accountID)"
    }
}

/// Silo sign-in after the password, before a household profile is picked.
struct SiloPendingSignIn: Sendable {
    let client: SiloAccountClient
    let nativeURL: URL
    let compatURL: URL
    let profiles: [SiloProfile]
    let avatarUploadEnabled: Bool
}
