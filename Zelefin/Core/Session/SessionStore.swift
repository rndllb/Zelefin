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
    private(set) var siloAPI: SiloAPIClient?
    private(set) var pendingSiloSignIn: SiloPendingSignIn?
    private(set) var householdProfiles: [SiloHouseholdProfile] = []
    private(set) var siloAvatarUploadEnabled = false
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
    /// Whether offline downloads are offered for the active session. Always true
    /// for Jellyfin; for Silo it reflects the server's download capability.
    private(set) var downloadsAvailable = true
    private(set) var openSubtitlesAvailable = false
    private(set) var jellyfinEnhancedAvailable = false
    /// Plugin dashboard switch `Enable "Remove from Continue Watching"`.
    private(set) var jellyfinEnhancedRemoveContinueWatching = false
    private(set) var companionAvailable = false
    private(set) var siloRequestsEnabled = false
    private(set) var siloSeerrPluginAvailable = false
    private(set) var siloArrPluginAvailable = false
    private(set) var siloSubtitleProviders: [String] = []
    private(set) var isAdministrator = false
    private(set) var enableSubtitleManagement = false
    var syncPlayGroupID: String?
    var syncPlayGroupName: String?
    var syncPlayPlaylistItemID: String?
    var pendingPlayerItem: MediaItem?

    var canManageSubtitles: Bool {
        RemoteSubtitleOffer.canManageSubtitles(
            isAdministrator: isAdministrator,
            enableSubtitleManagement: enableSubtitleManagement
        )
    }

    func shouldShowAddSubtitles(for item: MediaItem) -> Bool {
        if usesSilo { return false }
        return RemoteSubtitleOffer.shouldShowAddSubtitles(
            canManageSubtitles: canManageSubtitles,
            pluginAvailable: openSubtitlesAvailable,
            supportsRemote: item.supportsRemoteSubtitles
        )
    }

    var isDiscoverAvailable: Bool {
        if usesSilo {
            return SiloRequestSource.discoverAvailable(
                requestsEnabled: siloRequestsEnabled,
                seerr: siloSeerrPluginAvailable,
                arr: siloArrPluginAvailable,
                preferred: PluginSettings.siloRequestSource
            )
        }
        return PluginSettings.isSeerrConfigured
    }

    var requestCatalog: SiloRequestClient? {
        guard usesSilo, isDiscoverAvailable, let siloAPI else { return nil }
        return SiloRequestClient(api: siloAPI)
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
        if account.usesSilo {
            guard account.accountID == session?.accountID else { return nil }
            return householdProfiles.first(where: { $0.id == account.profileID })?.avatarURL
        }
        guard let client else { return nil }
        let revision = account.accountID == session?.accountID ? avatarRevision : 0
        return ArtworkURLBuilder(client: client).userAvatar(
            userID: account.userID,
            tag: account.userImageTag,
            revision: revision
        )
    }

    var isSignedIn: Bool { session != nil && library != nil }

    var usesSilo: Bool { session?.usesSilo == true }

    var canAdministerSilo: Bool {
        usesSilo && isAdministrator
    }

    var canChangeSiloPassword: Bool {
        usesSilo && (session?.isPrimaryProfile == true || session?.profileID == nil)
    }

    var jellyfinLibrary: JellyfinLibraryClient? { library as? JellyfinLibraryClient }

    func makePlaybackReporter(for plan: PlaybackPlan) -> (any PlaybackReporting)? {
        guard OfflinePlaybackPolicy.shouldReportToServer(isLocalFile: plan.streamURL.isFileURL) else {
            return nil
        }
        if let api = siloAPI, let sessionID = plan.playSessionID, !sessionID.isEmpty {
            return SiloPlaybackReporter(api: api, sessionID: sessionID)
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
            throw ZelefinError.server(current.usesSilo ? "Enter an email or username." : "Enter a username.")
        }
        guard !password.isEmpty else {
            throw ZelefinError.server("Enter a password.")
        }
        try await connect(
            serverAddress: current.serverURL.absoluteString,
            username: name,
            password: password,
            backend: current.backend
        )
    }

    func connect(
        serverAddress: String,
        username: String,
        password: String,
        backend: MediaBackend
    ) async throws {
        let url = try probe.normalizedURL(from: serverAddress)
        switch backend {
        case .silo:
            guard let health = try? await probe.siloHealth(at: url), health.isReady else {
                throw ZelefinError.server("This address is not a Silo server. Use Sign in with Jellyfin, or check the URL.")
            }
            try await connectSilo(
                url: url,
                health: health,
                username: username,
                password: password
            )
        case .jellyfin:
            if let health = try? await probe.siloHealth(at: url), health.isReady {
                throw ZelefinError.server("This address is a Silo server. Use Sign in with Silo.")
            }
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
    }

    func cancelSiloProfilePick() {
        pendingSiloSignIn = nil
    }

    func selectSiloProfile(_ profile: SiloHouseholdProfile, pin: String?) async throws {
        guard let pending = pendingSiloSignIn else {
            throw ZelefinError.missingUser
        }
        try await finishSiloSignIn(pending, profile: profile, pin: pin)
    }

    private func connectSilo(
        url: URL,
        health: SiloHealth,
        username: String,
        password: String
    ) async throws {
        let deviceID = DeviceIdentity.deviceID()
        let api = SiloAPIClient(baseURL: url, deviceID: deviceID)
        let auth = try await api.login(username: username, password: password)
        let profiles = try await api.profiles()
        let pending = SiloPendingSignIn(
            serverURL: url,
            accessToken: auth.accessToken,
            refreshToken: auth.refreshToken,
            userID: String(auth.user.id),
            userName: auth.user.username,
            deviceID: deviceID,
            serverName: health.displayName,
            serverVersion: health.version,
            userRole: auth.user.role,
            profiles: profiles
        )
        pendingSiloSignIn = pending
    }

    private func finishSiloSignIn(
        _ pending: SiloPendingSignIn,
        profile: SiloHouseholdProfile,
        pin: String?
    ) async throws {
        let api = SiloAPIClient(
            baseURL: pending.serverURL,
            accessToken: pending.accessToken,
            refreshToken: pending.refreshToken,
            deviceID: pending.deviceID
        )
        var profileToken: String?
        if profile.hasPin {
            let trimmed = pin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ZelefinError.server("Enter this profile's PIN.")
            }
            let result = try await api.verifyPIN(profileID: profile.id, pin: trimmed)
            guard result.valid else {
                throw ZelefinError.server("That PIN is not correct.")
            }
            profileToken = result.profileToken
        }
        await api.setProfile(id: profile.id, token: profileToken)
        let saved = SavedSession(
            serverURL: pending.serverURL,
            accessToken: pending.accessToken,
            userID: pending.userID,
            userName: profile.name.isEmpty ? pending.userName : profile.name,
            deviceID: pending.deviceID,
            userImageTag: nil,
            serverVersion: pending.serverVersion,
            serverName: pending.serverName,
            backend: .silo,
            refreshToken: pending.refreshToken,
            profileID: profile.id,
            profileToken: profileToken,
            profileName: profile.name,
            userRole: pending.userRole,
            isPrimaryProfile: profile.isPrimary
        )
        pendingSiloSignIn = nil
        householdProfiles = pending.profiles
        apply(saved, siloAPI: api, serverVersion: pending.serverVersion)
        persist(saved)
        beginFirstRunSetupIfNeeded(for: saved)
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

    func applySiloProfile(_ profile: SiloHouseholdProfile, pin: String?) async throws {
        guard var saved = session, saved.usesSilo, let api = siloAPI else {
            throw ZelefinError.missingUser
        }
        var profileToken: String?
        if profile.hasPin {
            let trimmed = pin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else {
                throw ZelefinError.server("Enter this profile's PIN.")
            }
            let result = try await api.verifyPIN(profileID: profile.id, pin: trimmed)
            guard result.valid else {
                throw ZelefinError.server("That PIN is not correct.")
            }
            profileToken = result.profileToken
        }
        await api.setProfile(id: profile.id, token: profileToken)
        saved.profileID = profile.id
        saved.profileToken = profileToken
        saved.profileName = profile.name
        saved.isPrimaryProfile = profile.isPrimary
        if !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saved.userName = profile.name
        }
        apply(saved, siloAPI: api, serverVersion: saved.serverVersion)
        persist(saved)
    }

    func createSiloProfile(name: String, pin: String?, isChild: Bool) async throws {
        guard let api = siloAPI else { throw ZelefinError.missingUser }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ZelefinError.server("Enter a profile name.")
        }
        let created = try await api.createProfile(name: trimmed, pin: pin, isChild: isChild)
        householdProfiles = (try? await api.profiles()) ?? [created]
        try await applySiloProfile(created, pin: pin)
    }

    func changePassword(current: String, new: String) async throws {
        let currentPassword = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPassword = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            throw ZelefinError.server("Enter your current password and a new password.")
        }
        if usesSilo {
            guard let api = siloAPI else { throw ZelefinError.missingUser }
            guard canChangeSiloPassword else {
                throw ZelefinError.server("Switch to the primary household profile to change this password.")
            }
            let capability = try? await api.passwordCapability()
            let minimum = capability?.minimumLength ?? 8
            guard newPassword.count >= minimum else {
                throw ZelefinError.server("Use at least \(minimum) characters for the new password.")
            }
            if capability?.canChange == false {
                throw ZelefinError.server("This profile cannot change the account password.")
            }
            try await api.changePassword(current: currentPassword, new: newPassword)
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
        if usesSilo {
            try await updateSiloAvatar(jpeg: jpeg)
            return
        }
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await updateProfileImage(userID: userID, jpeg: jpeg)
    }

    func updateSiloAvatarPreset(_ presetID: String) async throws {
        guard let api = siloAPI, let profileID = session?.profileID else {
            throw ZelefinError.missingUser
        }
        let updated = try await api.updateProfileAvatar(
            id: profileID,
            preset: SiloProfileAvatars.presetRef(presetID)
        )
        applyUpdatedHouseholdProfile(updated)
    }

    func updateSiloAvatar(jpeg: Data) async throws {
        guard jpeg.count <= 10 * 1_024 * 1_024 else {
            throw ZelefinError.server("Choose a photo smaller than 10 MB.")
        }
        guard let api = siloAPI, let profileID = session?.profileID else {
            throw ZelefinError.missingUser
        }
        let updated = try await api.uploadProfileAvatar(id: profileID, jpeg: jpeg)
        applyUpdatedHouseholdProfile(updated)
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
        if usesSilo {
            try await removeSiloAvatar()
            return
        }
        guard let userID = session?.userID else { throw ZelefinError.missingUser }
        try await removeProfileImage(userID: userID)
    }

    func removeSiloAvatar() async throws {
        guard let api = siloAPI, let profileID = session?.profileID else {
            throw ZelefinError.missingUser
        }
        let current = householdProfiles.first(where: { $0.id == profileID })
        if current?.isUploadedAvatar == true {
            try await api.deleteProfileAvatar(id: profileID)
            await refreshHouseholdProfiles()
            avatarRevision += 1
        } else {
            let updated = try await api.updateProfileAvatar(id: profileID, preset: nil)
            applyUpdatedHouseholdProfile(updated)
        }
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
            case .stop:
                try await library.syncPlayStop()
            default:
                break
            }
        } catch {
            // Keep local playback going if the group command fails.
        }
    }

    func presentSyncPlayItem(id: String) async {
        guard let loaded = try? await library?.item(id: id) else { return }
        if pendingPlayerItem?.id != loaded.id {
            pendingPlayerItem = loaded
        }
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
        siloAPI = nil
        pendingSiloSignIn = nil
        householdProfiles = []
        siloAvatarUploadEnabled = false
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
        siloRequestsEnabled = false
        siloSeerrPluginAvailable = false
        siloArrPluginAvailable = false
        siloSubtitleProviders = []
        isAdministrator = false
        enableSubtitleManagement = false
        syncPlayGroupID = nil
        syncPlayGroupName = nil
        syncPlayPlaylistItemID = nil
        pendingPlayerItem = nil
        needsFirstRunSetup = false
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

    private func apply(
        _ saved: SavedSession,
        client existing: JellyfinClient? = nil,
        siloAPI existingSilo: SiloAPIClient? = nil,
        serverVersion: String? = nil
    ) {
        if PluginSettings.shouldClearSession(switchingFrom: session?.accountID, to: saved.accountID) {
            PluginSettings.clearSeerrSession()
        }
        // Landing in a working session clears any stale "session expired" notice.
        authNotice = nil
        session = saved
        if ReviewDemo.isSession(saved) {
            applyReviewDemo(saved)
            return
        }
        if saved.usesSilo {
            applySilo(saved, api: existingSilo, serverVersion: serverVersion)
            return
        }
        siloAPI = nil
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
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        siloRequestsEnabled = false
        siloSeerrPluginAvailable = false
        siloArrPluginAvailable = false
        siloSubtitleProviders = []
        isAdministrator = false
        enableSubtitleManagement = false
        itemDetailMemory = [:]
        playbackLaunchOptions = [:]
        restoreSnapshot(for: saved)
        Task { await refreshAccount() }
        Task { await refreshSessionCapabilities() }
        Task { await pullDisplayPreferences() }
        Task { await loadHome(force: true) }
        Task { await refreshHomeNetworkSSID() }
        RemoteControlHub.shared.connect(client: jellyfin, session: saved)
        if serverVersion == nil {
            Task { await refreshServerCapabilities(at: endpoint.url) }
        }
    }

    private func applySilo(
        _ saved: SavedSession,
        api existing: SiloAPIClient?,
        serverVersion: String?
    ) {
        RemoteControlHub.shared.disconnect()
        startHomeNetworkMonitor()
        let endpoint = homeNetworkEndpoint(for: saved)
        activeRoute = endpoint.route
        let api: SiloAPIClient
        if let existing {
            api = existing
            Task {
                await api.setBaseURL(endpoint.url)
                await api.setProfile(id: saved.profileID, token: saved.profileToken)
            }
        } else {
            api = SiloAPIClient(
                baseURL: endpoint.url,
                accessToken: saved.accessToken,
                refreshToken: saved.refreshToken,
                profileID: saved.profileID,
                profileToken: saved.profileToken,
                deviceID: saved.deviceID
            )
        }
        bindSiloTokenUpdates(api)
        bindSiloSessionRevoked(api)
        client = nil
        siloAPI = api
        library = SiloLibraryClient(api: api, profileID: saved.profileID ?? "")
        serverName = saved.serverName ?? saved.serverURL.host
        introSkipperAvailable = false
        downloadsAvailable = false
        openSubtitlesAvailable = true
        jellyfinEnhancedAvailable = false
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        siloRequestsEnabled = false
        siloSeerrPluginAvailable = false
        siloArrPluginAvailable = false
        siloSubtitleProviders = []
        isAdministrator = (saved.userRole ?? "").lowercased() == "admin" && saved.isPrimaryProfile
        enableSubtitleManagement = true
        itemDetailMemory = [:]
        playbackLaunchOptions = [:]
        restoreSnapshot(for: saved)
        Task { await loadHome(force: true) }
        Task { await refreshHomeNetworkSSID() }
        Task { await refreshHouseholdProfiles() }
        Task { await refreshSessionCapabilities() }
    }

    private func bindSiloTokenUpdates(_ api: SiloAPIClient) {
        Task {
            await api.setTokenHandler { [weak self] access, refresh in
                Task { @MainActor in
                    guard var saved = self?.session, saved.usesSilo else { return }
                    saved.accessToken = access
                    if let refresh {
                        saved.refreshToken = refresh
                    }
                    self?.session = saved
                    self?.persist(saved)
                }
            }
        }
    }

    private func bindSiloSessionRevoked(_ api: SiloAPIClient) {
        Task {
            await api.setSessionRevokedHandler { [weak self] in
                Task { @MainActor in
                    self?.handleSiloSessionRevoked()
                }
            }
        }
    }

    @MainActor
    private func handleSiloSessionRevoked() {
        // The notifier is one-shot per client, but guard anyway: only act while
        // a Silo session is actually signed in.
        guard let saved = session, saved.usesSilo else { return }
        Task { await signOut() }
        authNotice = "Your Silo session expired. Please sign in again."
    }

    private func applyReviewDemo(_ saved: SavedSession) {
        let jellyfin = JellyfinNetworking.client(
            url: saved.serverURL,
            accessToken: saved.accessToken,
            deviceID: saved.deviceID
        )
        client = jellyfin
        library = ReviewDemo.libraryClient(deviceID: saved.deviceID)
        siloAPI = nil
        serverName = saved.serverName
        introSkipperAvailable = false
        openSubtitlesAvailable = false
        jellyfinEnhancedAvailable = false
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        siloRequestsEnabled = false
        siloSeerrPluginAvailable = false
        siloArrPluginAvailable = false
        siloSubtitleProviders = []
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
        if saved.usesSilo {
            Task { await siloAPI?.setBaseURL(endpoint.url) }
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
        guard !usesSilo else { return }
        guard let info = try? await probe.publicInfo(at: url) else { return }
        serverName = info.serverName
        library?.updateServerVersion(info.version)
        guard var saved = session else { return }
        saved.serverVersion = info.version
        saved.serverName = info.serverName
        session = saved
        persist(saved)
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
        guard !usesSilo, let client, let userID = session?.userID else { return }
        var config = (try? await client.send(Paths.getCurrentUser).value.configuration) ?? UserConfiguration()
        let audio = audioCode == PlaybackLanguage.automaticCode ? "" : audioCode
        let subtitle = (subtitleCode == PlaybackLanguage.automaticCode || subtitleCode == PlaybackLanguage.offCode)
            ? ""
            : subtitleCode
        config.audioLanguagePreference = audio
        config.isPlayDefaultAudioTrack = audio.isEmpty
        config.subtitleLanguagePreference = subtitle
        config.subtitleMode = subtitleCode == PlaybackLanguage.offCode
            ? SubtitlePlaybackMode.none
            : subtitle.isEmpty ? .default : .smart
        _ = try? await client.send(Paths.updateUserConfiguration(userID: userID, config))
    }

    func installZelefinPlugin() async throws {
        guard isAdministrator, let client, !usesSilo else {
            throw ZelefinError.server("Sign in as a Jellyfin administrator to install the Zelefin plugin.")
        }
        try await ZelefinPluginInstaller(client: client).install()
        await detectPlugins()
    }

    func restartJellyfinAfterPluginInstall() async throws {
        guard isAdministrator, let client, !usesSilo else {
            throw ZelefinError.server("Sign in as a Jellyfin administrator to restart this server.")
        }
        try await ZelefinPluginInstaller(client: client).restartServer()
    }

    func detectPlugins() async {
        if usesSilo {
            await detectSiloPlugins()
            return
        }
        guard let client else {
            introSkipperAvailable = false
            openSubtitlesAvailable = false
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
        siloRequestsEnabled = false
        siloSeerrPluginAvailable = false
        siloArrPluginAvailable = false
        siloSubtitleProviders = []
        if companionAvailable {
            await registerCompanionPush()
        }
    }

    private func detectSiloPlugins() async {
        introSkipperAvailable = false
        jellyfinEnhancedAvailable = false
        jellyfinEnhancedRemoveContinueWatching = false
        companionAvailable = false
        CompanionSettings.pluginInstalled = false
        openSubtitlesAvailable = false
        siloSubtitleProviders = []
        enableSubtitleManagement = false
        guard let api = siloAPI else {
            siloRequestsEnabled = false
            siloSeerrPluginAvailable = false
            siloArrPluginAvailable = false
            return
        }
        var pluginIDs: [String] = []
        if let listed = try? await api.siloPluginSettings() {
            pluginIDs.append(contentsOf: listed.filter(\.isEnabled).map(\.pluginID))
        }
        if isAdministrator, let admin = try? await api.siloAdminPluginInstallations() {
            pluginIDs.append(contentsOf: admin.filter(\.isEnabled).map(\.pluginID))
        }
        siloSeerrPluginAvailable = pluginIDs.contains { SiloRequestSource.matches($0, source: .seerr) }
        siloArrPluginAvailable = pluginIDs.contains { SiloRequestSource.matches($0, source: .arr) }
        if let status = try? await api.siloRequestStatus() {
            siloRequestsEnabled = status.isEnabled
        } else {
            siloRequestsEnabled = siloSeerrPluginAvailable || siloArrPluginAvailable
        }
    }

    func registerPushToken(_ token: String) async {
        guard companionAvailable, let client else { return }
        await ZelefinCompanionClient(client: client).registerDevice(token: token)
    }

    func registerCompanionPushIfNeeded() async {
        guard companionAvailable else { return }
        await registerCompanionPush()
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
        downloadsAvailable = await (library?.downloadsAvailable() ?? true)
    }

    func refreshAdministratorStatus() async {
        if usesSilo {
            await refreshSiloAdministratorStatus()
            return
        }
        guard let client else { return }
        do {
            let user = try await client.send(Paths.getCurrentUser).value
            isAdministrator = user.policy?.isAdministrator == true
            enableSubtitleManagement = user.policy?.enableSubtitleManagement == true
        } catch {
            // Keep the last known admin flag so a blip cannot hide admin tools.
        }
    }

    private func refreshSiloAdministratorStatus() async {
        if let me = try? await siloAPI?.currentUser(), var saved = session {
            saved.userRole = me.role
            session = saved
            persist(saved)
        }
        isAdministrator = (session?.userRole ?? "").lowercased() == "admin"
            && (session?.isPrimaryProfile ?? false)
    }

    private func refreshHouseholdProfiles() async {
        guard let api = siloAPI else { return }
        let list = try? await api.profileList()
        householdProfiles = list?.entries ?? []
        siloAvatarUploadEnabled = list?.avatarUploadEnabled ?? false
        guard var saved = session, let profileID = saved.profileID,
              let current = householdProfiles.first(where: { $0.id == profileID }) else { return }
        var changed = false
        if saved.isPrimaryProfile != current.isPrimary {
            saved.isPrimaryProfile = current.isPrimary
            changed = true
        }
        if saved.profileName != current.name {
            saved.profileName = current.name
            changed = true
        }
        if changed {
            session = saved
            persist(saved)
            isAdministrator = (saved.userRole ?? "").lowercased() == "admin" && saved.isPrimaryProfile
        }
    }

    private func applyUpdatedHouseholdProfile(_ updated: SiloHouseholdProfile) {
        if let index = householdProfiles.firstIndex(where: { $0.id == updated.id }) {
            householdProfiles[index] = updated
        } else {
            householdProfiles.append(updated)
        }
        avatarRevision += 1
        Task { await refreshHouseholdProfiles() }
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
}
