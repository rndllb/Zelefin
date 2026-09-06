import Foundation
import JellyfinAPI
import Observation

@MainActor
@Observable
final class SessionStore {
    private let vault = SessionVault()
    private let probe = ServerProbe()
    private let snapshotStore: any HomeSnapshotStoring
    private let itemDetailStore: any ItemDetailSnapshotStoring
    private var itemDetailMemory: [String: ItemDetailSnapshot] = [:]

    private(set) var session: SavedSession?
    private(set) var client: JellyfinClient?
    private(set) var library: JellyfinLibraryClient?
    private(set) var isRestoring = true
    private(set) var serverName: String?
    private(set) var homeLayout = HomeLayout(featured: [], sections: [])
    private(set) var libraries: [MediaLibrary] = []
    private(set) var homeError: String?
    private(set) var isLoadingHome = false
    private(set) var introSkipperAvailable = false
    private(set) var tmdbCatalog = JellyfinTmdbCatalog()

    private var homeTask: Task<Void, Never>?

    init(
        snapshotStore: any HomeSnapshotStoring = FileHomeSnapshotStore(),
        itemDetailStore: any ItemDetailSnapshotStoring = FileItemDetailSnapshotStore()
    ) {
        self.snapshotStore = snapshotStore
        self.itemDetailStore = itemDetailStore
    }

    var avatarURL: URL? {
        guard let session, let client else { return nil }
        return ArtworkURLBuilder(client: client).userAvatar(userID: session.userID, tag: session.userImageTag)
    }

    var isSignedIn: Bool { session != nil && library != nil }

    func restore() async {
        defer { isRestoring = false }
        guard let saved = try? vault.load() else { return }
        apply(saved, serverVersion: saved.serverVersion)
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
            serverVersion: info.version
        )
        serverName = info.serverName
        apply(saved, client: jellyfin, serverVersion: info.version)
        try vault.save(saved)
    }

    func signOut() async {
        homeTask?.cancel()
        try? await client?.signOut()
        vault.delete()
        session = nil
        client = nil
        library = nil
        serverName = nil
        homeLayout = HomeLayout(featured: [], sections: [])
        libraries = []
        homeError = nil
        isLoadingHome = false
        introSkipperAvailable = false
        tmdbCatalog = JellyfinTmdbCatalog()
        itemDetailMemory = [:]
        PluginSettings.clearSeerrSession()
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

    func hideFromRecentlyWatched(_ item: MediaItem) async throws {
        guard let library else { throw ZelefinError.missingUser }
        try await library.markUnplayed(itemID: item.id)
        removeFromHome(itemID: item.id)
        Task { await refreshHome() }
    }

    private func removeFromHome(itemID: String) {
        homeLayout = HomeLayoutPreferences.removing(itemID, from: homeLayout)
        persistSnapshot()
    }

    private func refreshAccount() async {
        guard let client else { return }
        guard let user = try? await client.send(Paths.getCurrentUser).value else { return }
        guard var saved = session else { return }
        saved.userName = user.name ?? saved.userName
        saved.userImageTag = user.primaryImageTag
        session = saved
        try? vault.save(saved)
    }

    private func apply(_ saved: SavedSession, client existing: JellyfinClient? = nil, serverVersion: String? = nil) {
        let jellyfin = existing ?? JellyfinNetworking.client(
            url: saved.serverURL,
            accessToken: saved.accessToken,
            deviceID: saved.deviceID
        )
        session = saved
        client = jellyfin
        library = JellyfinLibraryClient(client: jellyfin, userID: saved.userID, serverVersion: serverVersion)
        introSkipperAvailable = false
        itemDetailMemory = [:]
        restoreSnapshot(for: saved)
        Task { await refreshAccount() }
        Task { await loadHome(force: true) }
        Task { await detectIntroSkipper() }
        if serverVersion == nil {
            Task { await refreshServerCapabilities(at: saved.serverURL) }
        }
    }

    private func refreshServerCapabilities(at url: URL) async {
        guard let info = try? await probe.publicInfo(at: url) else { return }
        serverName = info.serverName
        library?.updateServerVersion(info.version)
        guard var saved = session else { return }
        saved.serverVersion = info.version
        session = saved
        try? vault.save(saved)
    }

    func detectIntroSkipper() async {
        guard let client else {
            introSkipperAvailable = false
            return
        }
        introSkipperAvailable = await IntroSkipperClient(client: client).isInstalled()
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
        var librarySections: [HomeSection] = []
        var collections: HomeSection?
        var genres: HomeSection?
        var catalog: [MediaLibrary] = []

        await withTaskGroup(of: JellyfinLibraryClient.HomeChunk.self) { group in
            group.addTask { .continueWatching(await library.resumeItemsIgnoringErrors()) }
            group.addTask { .nextUp(await library.nextUpItemsIgnoringErrors()) }
            group.addTask { .recentlyWatched(await library.recentlyWatchedIgnoringErrors()) }
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
        Task { await refreshTmdbCatalog() }
    }

    private func publishHome(
        continueWatching: [MediaItem],
        nextUp: [MediaItem],
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
            featured: HomeLayoutPreferences.featured(
                resume: continueWatching,
                nextUp: nextUp,
                merge: merge
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
