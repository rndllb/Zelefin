import Foundation

enum LibraryAlertSettings {
    static let enabledKey = "zelefin.alerts.enabled"
    static let libraryAddsKey = "zelefin.alerts.library"
    static let streamsKey = "zelefin.alerts.streams"
    static let onlineKey = "zelefin.alerts.online"
    static let requestsKey = "zelefin.alerts.requests"
    static let scheduledTasksKey = "zelefin.alerts.tasks"
    static let lastAdministratorKey = "zelefin.alerts.last-admin"

    static var isEnabled: Bool {
        get { bool(for: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var libraryAdds: Bool {
        get { bool(for: libraryAddsKey) }
        set { UserDefaults.standard.set(newValue, forKey: libraryAddsKey) }
    }

    static var streams: Bool {
        get { bool(for: streamsKey) }
        set { UserDefaults.standard.set(newValue, forKey: streamsKey) }
    }

    static var online: Bool {
        get { bool(for: onlineKey) }
        set { UserDefaults.standard.set(newValue, forKey: onlineKey) }
    }

    static var requests: Bool {
        get { bool(for: requestsKey) }
        set { UserDefaults.standard.set(newValue, forKey: requestsKey) }
    }

    static var scheduledTasks: Bool {
        get { bool(for: scheduledTasksKey) }
        set { UserDefaults.standard.set(newValue, forKey: scheduledTasksKey) }
    }

    static var lastKnownAdministrator: Bool {
        get { UserDefaults.standard.bool(forKey: lastAdministratorKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastAdministratorKey) }
    }

    static func preferences(isAdministrator: Bool) -> LibraryAlertPreferences {
        LibraryAlertPreferences(
            isEnabled: isEnabled,
            libraryAdds: libraryAdds,
            streams: streams,
            online: online,
            requests: requests,
            scheduledTasks: scheduledTasks,
            isAdministrator: isAdministrator
        )
    }

    private static func bool(for key: String, default fallback: Bool = true) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
}

enum LibraryAlertSnapshotStore {
    static func load(accountID: String) -> LibraryAlertSnapshot {
        let key = storageKey(accountID)
        guard let data = UserDefaults.standard.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(LibraryAlertSnapshot.self, from: data)
        else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: LibraryAlertSnapshot, accountID: String) {
        let key = storageKey(accountID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func storageKey(_ accountID: String) -> String {
        "zelefin.alerts.snapshot.\(accountID)"
    }
}
