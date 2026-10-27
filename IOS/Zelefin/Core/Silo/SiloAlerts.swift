import Foundation

/// What a Silo webhook can alert about. Silo only notifies about shows a profile follows and its requests.
struct SiloAlertCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Silo's webhook flags this category turns on.
    let flags: [String]

    static let all: [SiloAlertCategory] = [
        SiloAlertCategory(id: "favorites", title: "New Episodes of Favorites", flags: ["notify_favorites"]),
        SiloAlertCategory(id: "watchlist", title: "New Episodes on Your Watchlist", flags: ["notify_watchlist"]),
        SiloAlertCategory(id: "watching", title: "New Episodes of Shows You're Watching", flags: ["notify_continue_watching", "notify_next_up"]),
        SiloAlertCategory(id: "requests", title: "Request Updates", flags: ["notify_requests"]),
    ]

    static let defaultIDs = Set(all.map(\.id))

    /// Every Silo flag, on or off, for the chosen categories.
    static func flags(for ids: Set<String>) -> [String: Bool] {
        var flags: [String: Bool] = [:]
        for category in all {
            for flag in category.flags {
                flags[flag] = ids.contains(category.id)
            }
        }
        return flags
    }
}

/// This iPhone's Silo alerts for one account: the push service's hook and the webhook on the profile.
struct SiloAlertRegistration: Codable, Equatable, Sendable {
    var hookID: String
    var token: String
    var webhookID: String?
    var categoryIDs: [String]

    private static func key(for accountID: String) -> String { "zelefin.silo.alerts.\(accountID)" }

    /// Accounts with a registration saved on this device, including ones since signed out.
    static func savedAccountIDs() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("zelefin.silo.alerts.") }
            .map { String($0.dropFirst("zelefin.silo.alerts.".count)) }
    }

    static func saved(for accountID: String) -> SiloAlertRegistration? {
        guard let data = UserDefaults.standard.data(forKey: key(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(SiloAlertRegistration.self, from: data)
    }

    static func save(_ registration: SiloAlertRegistration?, for accountID: String) {
        guard let registration, let data = try? JSONEncoder().encode(registration) else {
            UserDefaults.standard.removeObject(forKey: key(for: accountID))
            return
        }
        UserDefaults.standard.set(data, forKey: key(for: accountID))
    }
}
