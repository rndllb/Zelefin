import BackgroundTasks
import Foundation
import Observation
import UserNotifications

extension Notification.Name {
    static let zelefinPlaybackSessions = Notification.Name("zelefin.playbackSessions")
}

@MainActor
@Observable
final class LibraryAlertMonitor {
    static let shared = LibraryAlertMonitor()
    static let backgroundTaskIdentifier = "app.zelefin.client.library-alerts"
    static let sessionPollSeconds: TimeInterval = 5
    static let libraryPollSeconds: TimeInterval = 90
    static var sessionInterval: Duration { .seconds(sessionPollSeconds) }
    static var libraryInterval: Duration { .seconds(libraryPollSeconds) }

    private var pollTask: Task<Void, Never>?
    private var sessionWatch: Task<Void, Never>?
    /// Websocket pushes and the poll can overlap; evaluate one snapshot at a time so a slow fetch cannot rewind “already notified”.
    private var evaluateChain = Task<Void, Never> {}
    private var isPollingLibrary = false
    private var lastLibraryPoll = Date.distantPast
    private weak var attachedSession: SessionStore?

    static func registerBackgroundRefresh() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: backgroundTaskIdentifier,
            using: nil
        ) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                await LibraryAlertMonitor.shared.handleBackground(refresh)
            }
        }
    }

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    func attach(session: SessionStore) {
        attachedSession = session
    }

    func start(session: SessionStore) {
        stop()
        guard session.isSignedIn, !session.isReviewDemo, LibraryAlertSettings.isEnabled else { return }
        Self.scheduleBackgroundRefresh()
        pollTask = Task { [weak self] in
            if await LibraryAlertCenter.shared.authorizationStatus() == .notDetermined {
                _ = await LibraryAlertCenter.shared.requestAuthorization()
            }
            await self?.poll(session: session, includeLibrary: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sessionInterval)
                guard !Task.isCancelled else { return }
                let elapsed = Date().timeIntervalSince(self?.lastLibraryPoll ?? .distantPast)
                await self?.poll(session: session, includeLibrary: elapsed >= Self.libraryPollSeconds)
            }
        }
        sessionWatch = Task { [weak self] in
            for await notification in NotificationCenter.default.notifications(named: .zelefinPlaybackSessions) {
                guard !Task.isCancelled else { return }
                let sessions = notification.object as? [PlaybackSession] ?? []
                await self?.ingest(sessions: sessions, session: session)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        sessionWatch?.cancel()
        sessionWatch = nil
    }

    func handleBackground(_ task: BGAppRefreshTask) async {
        Self.scheduleBackgroundRefresh()
        let work = Task { @MainActor in
            for _ in 0..<20 {
                if Task.isCancelled { return }
                if let session = self.attachedSession, session.isSignedIn, !session.isRestoring {
                    await self.poll(session: session, includeLibrary: true)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        task.expirationHandler = {
            work.cancel()
        }
        await work.value
        task.setTaskCompleted(success: true)
    }

    func poll(session: SessionStore) async {
        await poll(session: session, includeLibrary: true)
    }

    func ingest(sessions: [PlaybackSession], session: SessionStore) async {
        guard session.isSignedIn, !session.isReviewDemo, session.isAdministrator else { return }
        guard LibraryAlertSettings.isEnabled else { return }
        guard LibraryAlertSettings.streams || LibraryAlertSettings.online else { return }
        await evaluate(
            session: session,
            latestItems: nil,
            sessions: sessions,
            requests: nil,
            tasks: nil
        )
    }

    private func poll(session: SessionStore, includeLibrary: Bool) async {
        if includeLibrary {
            guard !isPollingLibrary else { return }
        }
        guard session.isSignedIn, !session.isReviewDemo else { return }
        guard let library = session.library, let saved = session.session else { return }
        let preferences = LibraryAlertSettings.preferences(isAdministrator: session.isAdministrator)
        guard preferences.isEnabled else { return }
        let authorized = await LibraryAlertCenter.shared.authorizationStatus()
        guard authorized == .authorized || authorized == .provisional else { return }

        if includeLibrary { isPollingLibrary = true }
        defer { if includeLibrary { isPollingLibrary = false } }

        let librarySlice = includeLibrary
            ? await fetchLibrarySlice(library: library, accountID: saved.accountID, preferences: preferences)
            : nil
        let sessions = await fetchSessions(library: library, preferences: preferences)

        await evaluate(
            session: session,
            latestItems: librarySlice?.items,
            sessions: sessions,
            requests: librarySlice?.requests,
            tasks: librarySlice?.tasks
        )
    }

    private func fetchLibrarySlice(
        library: JellyfinLibraryClient,
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
        } else {
            slice.requests = []
        }

        if let scheduled = try? await library.scheduledTasks() {
            slice.tasks = scheduled.filter(\.isActive).map {
                LibraryAlertTask(id: $0.id, name: $0.name)
            }
        } else {
            slice.tasks = []
        }
        return slice
    }

    private func fetchSessions(
        library: JellyfinLibraryClient,
        preferences: LibraryAlertPreferences
    ) async -> [PlaybackSession]? {
        guard preferences.isAdministrator, preferences.streams || preferences.online else { return nil }
        return try? await library.playbackSessions()
    }

    private func evaluate(
        session: SessionStore,
        latestItems: [MediaItem]?,
        sessions: [PlaybackSession]?,
        requests: [LibraryAlertRequest]?,
        tasks: [LibraryAlertTask]?
    ) async {
        let prior = evaluateChain
        let work = Task { @MainActor in
            await prior.value
            await self.performEvaluate(
                session: session,
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
        session: SessionStore,
        latestItems: [MediaItem]?,
        sessions: [PlaybackSession]?,
        requests: [LibraryAlertRequest]?,
        tasks: [LibraryAlertTask]?
    ) async {
        guard let saved = session.session else { return }
        let authorized = await LibraryAlertCenter.shared.authorizationStatus()
        guard authorized == .authorized || authorized == .provisional else { return }
        let preferences = LibraryAlertSettings.preferences(isAdministrator: session.isAdministrator)
        guard preferences.isEnabled else { return }

        let previous = LibraryAlertSnapshotStore.load(accountID: saved.accountID)
        let input = LibraryAlertInput(
            latestItems: latestItems,
            sessions: sessions,
            requests: requests,
            tasks: tasks,
            localDeviceID: saved.deviceID
        )
        let result = LibraryAlertEngine.evaluate(
            previous: previous,
            input: input,
            preferences: preferences
        )
        LibraryAlertSnapshotStore.save(result.next, accountID: saved.accountID)
        guard !result.alerts.isEmpty else { return }
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
}

private struct LibraryPollSlice {
    var items: [MediaItem]?
    var requests: [LibraryAlertRequest]?
    var tasks: [LibraryAlertTask]?
}
