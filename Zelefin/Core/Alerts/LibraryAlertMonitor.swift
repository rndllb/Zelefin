import BackgroundTasks
import Foundation
import Observation
import UIKit
import UserNotifications

extension Notification.Name {
    static let zelefinPlaybackSessions = Notification.Name("zelefin.playbackSessions")
    static let zelefinLibraryChanged = Notification.Name("zelefin.libraryChanged")
}

@MainActor
@Observable
final class LibraryAlertMonitor {
    static let shared = LibraryAlertMonitor()
    nonisolated static let backgroundTaskIdentifier = "app.zelefin.client.library-alerts"
    static let sessionPollSeconds: TimeInterval = 5
    static let libraryPollSeconds: TimeInterval = 90
    nonisolated static let backgroundRefreshSeconds: TimeInterval = 15 * 60
    static var sessionInterval: Duration { .seconds(sessionPollSeconds) }
    static var libraryInterval: Duration { .seconds(libraryPollSeconds) }

    private var pollTask: Task<Void, Never>?
    private var sessionPollTask: Task<Void, Never>?
    private var sessionWatch: Task<Void, Never>?
    private var libraryWatch: Task<Void, Never>?
    private var libraryChangeDebounce: Task<Void, Never>?
    /// Websocket pushes and the poll can overlap; evaluate one snapshot at a time so a slow fetch cannot rewind “already notified”.
    private var evaluateChain = Task<Void, Never> {}
    private var isPollingLibrary = false
    private var lastLibraryPoll = Date.distantPast
    private weak var attachedSession: SessionStore?

    /// BGTaskScheduler invokes this on a background queue. The method and identifier must
    /// stay nonisolated so Swift does not trap when iOS wakes Zelefin while it is closed.
    nonisolated static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            handleBackgroundLaunch(task)
        }
    }

    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: backgroundRefreshSeconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private static func handleBackgroundLaunch(_ task: BGTask) {
        guard task is BGAppRefreshTask else {
            task.setTaskCompleted(success: false)
            return
        }
        scheduleBackgroundRefresh()
        let completion = BackgroundRefreshCompletion(task)
        let work = Task { @MainActor in
            await LibraryAlertMonitor.shared.pollFromSavedSession()
            completion.finish(success: !Task.isCancelled)
        }
        task.expirationHandler = { @Sendable in
            work.cancel()
            completion.finish(success: false)
        }
    }

    func attach(session: SessionStore) {
        attachedSession = session
    }

    func start(session: SessionStore) {
        stop()
        guard session.isSignedIn, !session.isReviewDemo, LibraryAlertSettings.isEnabled else { return }
        if session.isAdministrator {
            LibraryAlertSettings.lastKnownAdministrator = true
        }
        Self.scheduleBackgroundRefresh()
        sessionPollTask = Task { [weak self] in
            if await LibraryAlertCenter.shared.authorizationStatus() == .notDetermined {
                _ = await LibraryAlertCenter.shared.requestAuthorization()
            }
            _ = await PushNotificationCenter.requestPermissionIfNeeded()
            while !Task.isCancelled {
                await self?.poll(session: session, includeLibrary: false)
                try? await Task.sleep(for: Self.sessionInterval)
            }
        }
        pollTask = Task { [weak self] in
            await self?.poll(session: session, includeLibrary: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.libraryInterval)
                guard !Task.isCancelled else { return }
                await self?.poll(session: session, includeLibrary: true)
            }
        }
        sessionWatch = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .zelefinPlaybackSessions) {
                guard !Task.isCancelled else { return }
                guard let sessions = notification.object as? [PlaybackSession] else { continue }
                await self?.ingest(sessions: sessions, session: session)
            }
        }
        libraryWatch = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .zelefinLibraryChanged) {
                guard !Task.isCancelled else { return }
                self?.noteLibraryChanged(session: session)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        sessionPollTask?.cancel()
        sessionPollTask = nil
        sessionWatch?.cancel()
        sessionWatch = nil
        libraryWatch?.cancel()
        libraryWatch = nil
        libraryChangeDebounce?.cancel()
        libraryChangeDebounce = nil
    }

    func poll(session: SessionStore) async {
        await poll(session: session, includeLibrary: true)
    }

    /// Finishes a Jellyfin check after the user leaves, before iOS suspends the process.
    func pollWhenEnteringBackground() async {
        let application = UIApplication.shared
        var identifier = UIBackgroundTaskIdentifier.invalid
        identifier = application.beginBackgroundTask(withName: Self.backgroundTaskIdentifier) {
            application.endBackgroundTask(identifier)
            identifier = .invalid
        }
        defer {
            if identifier != .invalid {
                application.endBackgroundTask(identifier)
            }
        }
        Self.scheduleBackgroundRefresh()
        await pollFromSavedSession()
    }

    /// Checks Jellyfin using the saved account, without waiting for the UI session to finish restoring.
    func pollFromSavedSession() async {
        guard LibraryAlertSettings.isEnabled else { return }
        let authorized = await LibraryAlertCenter.shared.authorizationStatus()
        guard authorized == .authorized || authorized == .provisional else { return }
        guard let saved = try? SessionVault().load(), !ReviewDemo.isSession(saved) else { return }

        if let session = attachedSession, session.isSignedIn, !session.isRestoring, !session.isReviewDemo {
            await poll(session: session, includeLibrary: true)
            return
        }

        let client = JellyfinNetworking.client(
            url: saved.serverURL,
            accessToken: saved.accessToken,
            deviceID: saved.deviceID
        )
        let library = JellyfinLibraryClient(
            client: client,
            userID: saved.userID,
            serverVersion: saved.serverVersion
        )
        let preferences = LibraryAlertSettings.preferences(
            isAdministrator: LibraryAlertSettings.lastKnownAdministrator
        )
        let librarySlice = await fetchLibrarySlice(
            library: library,
            accountID: saved.accountID,
            preferences: preferences
        )
        let sessions = await fetchSessions(library: library, preferences: preferences)
        await evaluateSaved(
            saved: saved,
            latestItems: librarySlice.items,
            sessions: sessions,
            requests: librarySlice.requests,
            tasks: librarySlice.tasks
        )
    }

    func ingest(sessions: [PlaybackSession], session: SessionStore) async {
        guard session.isSignedIn, !session.isReviewDemo else { return }
        guard LibraryAlertSettings.isEnabled else { return }
        guard LibraryAlertSettings.streams || LibraryAlertSettings.online else { return }
        let isAdmin = session.isAdministrator || LibraryAlertSettings.lastKnownAdministrator
        guard isAdmin else { return }
        await evaluate(
            accountID: session.session?.accountID,
            deviceID: session.session?.deviceID,
            isAdministrator: true,
            latestItems: nil,
            sessions: sessions,
            requests: nil,
            tasks: nil
        )
    }

    private func noteLibraryChanged(session: SessionStore) {
        libraryChangeDebounce?.cancel()
        libraryChangeDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.poll(session: session, includeLibrary: true)
        }
    }

    private func evaluateSaved(
        saved: SavedSession,
        latestItems: [MediaItem]?,
        sessions: [PlaybackSession]?,
        requests: [LibraryAlertRequest]?,
        tasks: [LibraryAlertTask]?
    ) async {
        await evaluate(
            accountID: saved.accountID,
            deviceID: saved.deviceID,
            isAdministrator: LibraryAlertSettings.lastKnownAdministrator,
            latestItems: latestItems,
            sessions: sessions,
            requests: requests,
            tasks: tasks
        )
    }

    private func poll(session: SessionStore, includeLibrary: Bool) async {
        if includeLibrary {
            guard !isPollingLibrary else { return }
            isPollingLibrary = true
        }
        defer { if includeLibrary { isPollingLibrary = false } }
        guard session.isSignedIn, !session.isReviewDemo else { return }
        guard let library = session.library, let saved = session.session else { return }
        if session.isAdministrator {
            LibraryAlertSettings.lastKnownAdministrator = true
        }
        let isAdmin = session.isAdministrator || LibraryAlertSettings.lastKnownAdministrator
        let preferences = LibraryAlertSettings.preferences(isAdministrator: isAdmin)
        guard preferences.isEnabled else { return }
        let authorized = await LibraryAlertCenter.shared.authorizationStatus()
        guard authorized == .authorized || authorized == .provisional else { return }

        let slice: LibraryPollSlice?
        let playbackSessions: [PlaybackSession]?
        if includeLibrary {
            async let fetchedSlice = fetchLibrarySlice(
                library: library,
                accountID: saved.accountID,
                preferences: preferences
            )
            async let fetchedSessions = fetchSessions(library: session.jellyfinLibrary, preferences: preferences)
            slice = await fetchedSlice
            playbackSessions = await fetchedSessions
        } else {
            slice = nil
            playbackSessions = await fetchSessions(library: session.jellyfinLibrary, preferences: preferences)
        }

        await evaluate(
            accountID: saved.accountID,
            deviceID: saved.deviceID,
            isAdministrator: isAdmin,
            latestItems: slice?.items,
            sessions: playbackSessions,
            requests: slice?.requests,
            tasks: slice?.tasks
        )
    }

    private func fetchLibrarySlice(
        library: any LibraryServing,
        accountID: String,
        preferences: LibraryAlertPreferences
    ) async -> LibraryPollSlice {
        lastLibraryPoll = Date()
        var slice = LibraryPollSlice()
        if preferences.libraryAdds {
            slice.items = await library.recentlyAddedForAlerts()
        }
        guard preferences.isAdministrator else { return slice }

        if preferences.requests, let seerr = PluginSettings.seerrClient {
            let previous = LibraryAlertSnapshotStore.load(accountID: accountID)
            slice.requests = await Self.namedRequests(
                from: seerr,
                previousIDs: previous.seenRequestIDSet,
                primed: previous.primedAdmin
            )
        } else if preferences.requests, let silo = library as? SiloLibraryClient {
            slice.requests = await Self.namedSiloRequests(from: SiloRequestClient(api: silo.api))
        } else {
            slice.requests = []
        }

        if let jellyfin = library as? JellyfinLibraryClient,
           let scheduled = try? await jellyfin.scheduledTasks() {
            slice.tasks = scheduled.filter(\.isActive).map {
                LibraryAlertTask(id: $0.id, name: $0.name)
            }
        } else {
            slice.tasks = []
        }
        return slice
    }

    private func fetchSessions(
        library: JellyfinLibraryClient?,
        preferences: LibraryAlertPreferences
    ) async -> [PlaybackSession]? {
        guard preferences.streams || preferences.online else { return nil }
        guard preferences.isAdministrator || LibraryAlertSettings.lastKnownAdministrator else { return nil }
        return try? await library?.playbackSessions()
    }

    private func evaluate(
        accountID: String?,
        deviceID: String?,
        isAdministrator: Bool,
        latestItems: [MediaItem]?,
        sessions: [PlaybackSession]?,
        requests: [LibraryAlertRequest]?,
        tasks: [LibraryAlertTask]?
    ) async {
        let prior = evaluateChain
        let work = Task { @MainActor in
            await prior.value
            await self.performEvaluate(
                accountID: accountID,
                deviceID: deviceID,
                isAdministrator: isAdministrator,
                latestItems: latestItems,
                sessions: sessions,
                requests: requests,
                tasks: tasks
            )
        }
        evaluateChain = work
        await work.value
    }

    private func performEvaluate(
        accountID: String?,
        deviceID: String?,
        isAdministrator: Bool,
        latestItems: [MediaItem]?,
        sessions: [PlaybackSession]?,
        requests: [LibraryAlertRequest]?,
        tasks: [LibraryAlertTask]?
    ) async {
        guard let accountID, let deviceID else { return }
        let authorized = await LibraryAlertCenter.shared.authorizationStatus()
        guard authorized == .authorized || authorized == .provisional else { return }
        let preferences = LibraryAlertSettings.preferences(isAdministrator: isAdministrator)
        guard preferences.isEnabled else { return }

        let previous = LibraryAlertSnapshotStore.load(accountID: accountID)
        let input = LibraryAlertInput(
            latestItems: latestItems,
            sessions: sessions,
            requests: requests,
            tasks: tasks,
            localDeviceID: deviceID
        )
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: input,
            preferences: preferences
        )
        LibraryAlertSnapshotStore.save(result.next, accountID: accountID)
        guard !result.alerts.isEmpty else { return }
        if CompanionSettings.pluginInstalled {
            let leftover = result.alerts.filter { $0.kind == .scheduledTask }
            guard !leftover.isEmpty else { return }
            LibraryAlertCenter.shared.post(leftover)
            return
        }
        LibraryAlertCenter.shared.post(result.alerts)
    }

    private static func namedRequests(
        from seerr: SeerrClient,
        previousIDs: Set<String>,
        primed: Bool
    ) async -> [LibraryAlertRequest] {
        guard let listed = try? await seerr.listedRequests() else { return [] }
        var requests: [LibraryAlertRequest] = []
        for item in listed {
            let id = String(item.id)
            let requester = item.requestedBy?.displayLabel ?? "Someone"
            let kind: SeerrTitle.Kind = item.media.mediaType == "tv" ? .tv : .movie
            let fallback = kind == .tv ? "a show" : "a movie"
            var title = fallback
            if primed, !previousIDs.contains(id), let tmdbID = item.media.tmdbId {
                if let details = try? await seerr.titleDetails(kind: kind, tmdbID: tmdbID) {
                    title = details.name
                }
            }
            requests.append(LibraryAlertRequest(id: id, title: title, requester: requester))
        }
        return requests
    }

    private static func namedSiloRequests(from client: SiloRequestClient) async -> [LibraryAlertRequest] {
        (try? await client.listedAlerts()) ?? []
    }
}

private struct LibraryPollSlice {
    var items: [MediaItem]?
    var requests: [LibraryAlertRequest]?
    var tasks: [LibraryAlertTask]?
}

/// Owns the BGTask so the launch handler can finish it from MainActor or expiration without a sending race.
private final class BackgroundRefreshCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var task: BGTask?

    init(_ task: BGTask) {
        self.task = task
    }

    func finish(success: Bool) {
        lock.lock()
        let task = self.task
        self.task = nil
        lock.unlock()
        task?.setTaskCompleted(success: success)
    }
}
