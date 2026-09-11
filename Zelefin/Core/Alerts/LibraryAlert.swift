import Foundation

struct LibraryAlert: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case newTitle
        case streamStarted
        case userOnline
        case seerrRequest
        case scheduledTask
    }

    var kind: Kind
    var title: String
    var body: String
    var itemID: String?
    var id: String

    var opensScheduledTasks: Bool { kind == .scheduledTask }
}

extension LibraryAlert {
    static func addedToLibrary(body: String, itemID: String?, id: String) -> LibraryAlert {
        LibraryAlert(kind: .newTitle, title: "Added to library", body: body, itemID: itemID, id: id)
    }

    static func streamStarted(user: String, title: String, itemID: String?, key: String) -> LibraryAlert {
        LibraryAlert(
            kind: .streamStarted,
            title: "Now playing",
            body: "\(user) started \(title).",
            itemID: itemID,
            id: "stream-\(key)"
        )
    }

    static func userOnline(user: String, device: String, sessionID: String) -> LibraryAlert {
        LibraryAlert(
            kind: .userOnline,
            title: "User online",
            body: "\(user) is on \(device).",
            itemID: nil,
            id: "online-\(sessionID)"
        )
    }

    static func seerrRequest(requester: String, title: String, id: String) -> LibraryAlert {
        LibraryAlert(
            kind: .seerrRequest,
            title: "New request",
            body: "\(requester) requested \(title).",
            itemID: nil,
            id: "request-\(id)"
        )
    }

    static func scheduledTaskStarted(name: String, id: String) -> LibraryAlert {
        LibraryAlert(
            kind: .scheduledTask,
            title: "Scheduled task started",
            body: "\(name) is running.",
            itemID: nil,
            id: "task-\(id)"
        )
    }
}

struct LibraryAlertRequest: Equatable, Hashable, Sendable {
    var id: String
    var title: String
    var requester: String
}

struct LibraryAlertPreferences: Equatable, Sendable {
    var isEnabled: Bool
    var libraryAdds: Bool
    var streams: Bool
    var online: Bool
    var requests: Bool
    var scheduledTasks: Bool
    var isAdministrator: Bool

    static let allOff = LibraryAlertPreferences(
        isEnabled: false,
        libraryAdds: false,
        streams: false,
        online: false,
        requests: false,
        scheduledTasks: false,
        isAdministrator: false
    )
}

struct LibraryAlertSnapshot: Codable, Equatable, Sendable {
    var seenItemIDs: [String]
    var playingKeys: [String]
    var onlineSessionIDs: [String]
    var seenRequestIDs: [String]
    var runningTaskIDs: [String]
    var primedLibrary: Bool
    var primedAdmin: Bool
    var primedSessions: Bool

    static let empty = LibraryAlertSnapshot(
        seenItemIDs: [],
        playingKeys: [],
        onlineSessionIDs: [],
        seenRequestIDs: [],
        runningTaskIDs: [],
        primedLibrary: false,
        primedAdmin: false,
        primedSessions: false
    )

    var seenItemIDSet: Set<String> { Set(seenItemIDs) }
    var playingKeySet: Set<String> { Set(playingKeys) }
    var onlineSessionIDSet: Set<String> { Set(onlineSessionIDs) }
    var seenRequestIDSet: Set<String> { Set(seenRequestIDs) }
    var runningTaskIDSet: Set<String> { Set(runningTaskIDs) }

    init(
        seenItemIDs: [String],
        playingKeys: [String],
        onlineSessionIDs: [String],
        seenRequestIDs: [String],
        runningTaskIDs: [String],
        primedLibrary: Bool,
        primedAdmin: Bool,
        primedSessions: Bool
    ) {
        self.seenItemIDs = seenItemIDs
        self.playingKeys = playingKeys
        self.onlineSessionIDs = onlineSessionIDs
        self.seenRequestIDs = seenRequestIDs
        self.runningTaskIDs = runningTaskIDs
        self.primedLibrary = primedLibrary
        self.primedAdmin = primedAdmin
        self.primedSessions = primedSessions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seenItemIDs = try container.decodeIfPresent([String].self, forKey: .seenItemIDs) ?? []
        playingKeys = try container.decodeIfPresent([String].self, forKey: .playingKeys) ?? []
        onlineSessionIDs = try container.decodeIfPresent([String].self, forKey: .onlineSessionIDs)
            ?? container.decodeIfPresent([String].self, forKey: .onlineUserIDs)
            ?? []
        seenRequestIDs = try container.decodeIfPresent([String].self, forKey: .seenRequestIDs) ?? []
        runningTaskIDs = try container.decodeIfPresent([String].self, forKey: .runningTaskIDs) ?? []
        primedLibrary = try container.decodeIfPresent(Bool.self, forKey: .primedLibrary) ?? false
        primedAdmin = try container.decodeIfPresent(Bool.self, forKey: .primedAdmin) ?? false
        primedSessions = try container.decodeIfPresent(Bool.self, forKey: .primedSessions) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seenItemIDs, forKey: .seenItemIDs)
        try container.encode(playingKeys, forKey: .playingKeys)
        try container.encode(onlineSessionIDs, forKey: .onlineSessionIDs)
        try container.encode(seenRequestIDs, forKey: .seenRequestIDs)
        try container.encode(runningTaskIDs, forKey: .runningTaskIDs)
        try container.encode(primedLibrary, forKey: .primedLibrary)
        try container.encode(primedAdmin, forKey: .primedAdmin)
        try container.encode(primedSessions, forKey: .primedSessions)
    }

    private enum CodingKeys: String, CodingKey {
        case seenItemIDs
        case playingKeys
        case onlineSessionIDs
        case seenRequestIDs
        case runningTaskIDs
        case primedLibrary
        case primedAdmin
        case primedSessions
        case onlineUserIDs
    }
}

struct LibraryAlertTask: Equatable, Hashable, Sendable {
    var id: String
    var name: String
}

struct LibraryAlertInput: Sendable {
    var latestItems: [MediaItem]?
    var sessions: [PlaybackSession]?
    var requests: [LibraryAlertRequest]?
    var tasks: [LibraryAlertTask]?
    var localDeviceID: String
}

enum LibraryAlertEngine {
    static let maxItemAlerts = 3
    static let seenItemCap = 500
    static let seenRequestCap = 200

    static func evaluate(
        previous: LibraryAlertSnapshot,
        input: LibraryAlertInput,
        preferences: LibraryAlertPreferences
    ) -> (alerts: [LibraryAlert], next: LibraryAlertSnapshot) {
        guard preferences.isEnabled else {
            return ([], previous)
        }

        var next = previous
        var alerts: [LibraryAlert] = []

        if preferences.libraryAdds, let items = input.latestItems {
            let result = libraryAlerts(previous: next, items: items)
            alerts.append(contentsOf: result.alerts)
            next = result.next
        }

        if preferences.isAdministrator {
            let admin = adminAlerts(previous: next, input: input, preferences: preferences)
            alerts.append(contentsOf: admin.alerts)
            next = admin.next
        }

        return (alerts, next)
    }

    private static func libraryAlerts(
        previous: LibraryAlertSnapshot,
        items: [MediaItem]
    ) -> (alerts: [LibraryAlert], next: LibraryAlertSnapshot) {
        var next = previous
        let incoming = collapsedLibraryItems(items)
        next.seenItemIDs = mergeSeen(
            previous: previous.seenItemIDs,
            incoming: incoming.map(\.id),
            cap: seenItemCap
        )

        guard previous.primedLibrary else {
            next.primedLibrary = true
            return ([], next)
        }

        let fresh = incoming.filter { !previous.seenItemIDSet.contains($0.id) }
        guard !fresh.isEmpty else { return ([], next) }

        let visible = Array(fresh.prefix(maxItemAlerts))
        var alerts = visible.map { item in
            LibraryAlert.addedToLibrary(body: item.title, itemID: item.id, id: "library-\(item.id)")
        }
        let overflow = fresh.count - visible.count
        if overflow > 0 {
            let body = overflow == 1 ? "1 more new title." : "\(overflow) more new titles."
            alerts.append(LibraryAlert.addedToLibrary(body: body, itemID: nil, id: "library-overflow-\(overflow)"))
        }
        return (alerts, next)
    }

    private static func adminAlerts(
        previous: LibraryAlertSnapshot,
        input: LibraryAlertInput,
        preferences: LibraryAlertPreferences
    ) -> (alerts: [LibraryAlert], next: LibraryAlertSnapshot) {
        var next = previous
        var alerts: [LibraryAlert] = []

        if let sessions = input.sessions {
            let sessionResult = sessionAlerts(
                previous: next,
                sessions: sessions,
                preferences: preferences,
                localDeviceID: input.localDeviceID
            )
            alerts.append(contentsOf: sessionResult.alerts)
            next = sessionResult.next
        }

        if let requestIDs = input.requests?.map(\.id) {
            next.seenRequestIDs = mergeSeen(previous: next.seenRequestIDs, incoming: requestIDs, cap: seenRequestCap)
        }
        if let runningTaskIDs = input.tasks?.map(\.id) {
            next.runningTaskIDs = runningTaskIDs
        }

        guard previous.primedAdmin else {
            next.primedAdmin = true
            return (alerts, next)
        }

        if preferences.requests, let requests = input.requests {
            alerts.append(contentsOf: newRequestAlerts(requests, previouslySeen: previous.seenRequestIDSet))
        }
        if preferences.scheduledTasks, let tasks = input.tasks {
            alerts.append(contentsOf: newTaskAlerts(tasks, previouslyRunning: previous.runningTaskIDSet))
        }

        return (alerts, next)
    }

    private static func sessionAlerts(
        previous: LibraryAlertSnapshot,
        sessions: [PlaybackSession],
        preferences: LibraryAlertPreferences,
        localDeviceID: String
    ) -> (alerts: [LibraryAlert], next: LibraryAlertSnapshot) {
        var next = previous
        let remote = sessions.filter { !$0.isThisDevice(localDeviceID) }
        let playing = remote.filter(\.isPlaying)
        next.playingKeys = playing.map(playingKey)
        next.onlineSessionIDs = remote.map(\.id)

        guard previous.primedSessions else {
            next.primedSessions = true
            return ([], next)
        }

        var alerts: [LibraryAlert] = []
        if preferences.streams {
            let previousKeys = previous.playingKeySet
            alerts.append(contentsOf: playing.compactMap { session in
                let key = playingKey(session)
                guard !previousKeys.contains(key) else { return nil }
                let itemID = session.nowPlaying.map { $0.seriesDetailItemID ?? $0.id }
                return LibraryAlert.streamStarted(
                    user: session.userLabel,
                    title: session.title,
                    itemID: itemID,
                    key: key
                )
            })
        }
        if preferences.online {
            let previousOnline = previous.onlineSessionIDSet
            alerts.append(contentsOf: remote.compactMap { session in
                guard !previousOnline.contains(session.id) else { return nil }
                return LibraryAlert.userOnline(
                    user: session.userLabel,
                    device: session.deviceLabel,
                    sessionID: session.id
                )
            })
        }
        return (alerts, next)
    }

    private static func newRequestAlerts(
        _ requests: [LibraryAlertRequest],
        previouslySeen: Set<String>
    ) -> [LibraryAlert] {
        requests.compactMap { request in
            guard !previouslySeen.contains(request.id) else { return nil }
            return LibraryAlert.seerrRequest(requester: request.requester, title: request.title, id: request.id)
        }
    }

    private static func newTaskAlerts(
        _ tasks: [LibraryAlertTask],
        previouslyRunning: Set<String>
    ) -> [LibraryAlert] {
        tasks.compactMap { task in
            guard !previouslyRunning.contains(task.id) else { return nil }
            return LibraryAlert.scheduledTaskStarted(name: task.name, id: task.id)
        }
    }

    private struct CollapsedItem {
        var id: String
        var title: String
    }

    private static func collapsedLibraryItems(_ items: [MediaItem]) -> [CollapsedItem] {
        var seen = Set<String>()
        return items.compactMap { item in
            let id = item.seriesDetailItemID ?? item.id
            guard seen.insert(id).inserted else { return nil }
            return CollapsedItem(id: id, title: libraryTitle(for: item))
        }
    }

    private static func libraryTitle(for item: MediaItem) -> String {
        if item.kind == .episode, let series = item.seriesName, !series.isEmpty {
            return series
        }
        if let year = item.year, item.kind != .episode {
            return "\(item.name) (\(year))"
        }
        return item.name
    }

    private static func playingKey(_ session: PlaybackSession) -> String {
        let itemID = session.nowPlaying?.id ?? session.nowPlayingName ?? ""
        return "\(session.id)|\(itemID)"
    }

    private static func mergeSeen(previous: [String], incoming: [String], cap: Int) -> [String] {
        var seen = Set<String>()
        var merged: [String] = []
        for id in incoming + previous where seen.insert(id).inserted {
            merged.append(id)
            if merged.count >= cap { break }
        }
        return merged
    }
}
