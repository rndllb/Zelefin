import Foundation

/// A group of Emby notification events that Settings → Notifications turns on or off together.
struct EmbyAlertCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let events: [String]

    static let all: [EmbyAlertCategory] = [
        EmbyAlertCategory(id: "library", title: "New Media", events: ["library.new"]),
        EmbyAlertCategory(id: "playback", title: "Playback", events: ["playback.start", "playback.stop"]),
        EmbyAlertCategory(id: "livetv", title: "Live TV Recordings", events: ["livetv.recordingstarted", "livetv.recordingended", "livetv.recordingerror"]),
        EmbyAlertCategory(id: "users", title: "Sign-ins", events: ["user.authenticated", "user.authenticationfailed", "user.lockedout"]),
        EmbyAlertCategory(id: "tasks", title: "Scheduled Tasks", events: ["scheduledtasks.completed", "scheduledtasks.failed"]),
        EmbyAlertCategory(id: "server", title: "Server Updates and Backups", events: ["system.updateavailable", "system.updated", "system.serverrestartrequired", "system.backupcompleted", "system.backupfailed"]),
    ]

    static let defaultIDs: Set<String> = ["library", "livetv"]
}

/// This iPhone's Emby alerts for one account: the push service's hook and the matching Emby notification.
struct EmbyAlertRegistration: Codable, Equatable, Sendable {
    var hookID: String
    var url: String
    var token: String
    var entryID: String?
    var categoryIDs: [String]

    var events: [String] {
        EmbyAlertCategory.all.filter { categoryIDs.contains($0.id) }.flatMap(\.events)
    }

    private static func key(for accountID: String) -> String { "zelefin.emby.alerts.\(accountID)" }

    /// Accounts with a registration saved on this device, including ones since signed out.
    static func savedAccountIDs() -> [String] {
        UserDefaults.standard.dictionaryRepresentation().keys
            .filter { $0.hasPrefix("zelefin.emby.alerts.") }
            .map { String($0.dropFirst("zelefin.emby.alerts.".count)) }
    }

    static func saved(for accountID: String) -> EmbyAlertRegistration? {
        guard let data = UserDefaults.standard.data(forKey: key(for: accountID)) else { return nil }
        return try? JSONDecoder().decode(EmbyAlertRegistration.self, from: data)
    }

    static func save(_ registration: EmbyAlertRegistration?, for accountID: String) {
        guard let registration, let data = try? JSONEncoder().encode(registration) else {
            UserDefaults.standard.removeObject(forKey: key(for: accountID))
            return
        }
        UserDefaults.standard.set(data, forKey: key(for: accountID))
    }
}

enum EmbyAlertError: LocalizedError, Equatable {
    /// Emby only let administrators add notifications for this user.
    case notAllowed(url: String)
    case noPushToken
    case relay(String)

    var errorDescription: String? {
        switch self {
        case .notAllowed:
            "This Emby server only lets administrators add notifications. Ask an admin to add this iPhone's address in Emby under Settings → Notifications → Webhooks."
        case .noPushToken:
            "This iPhone has no push token yet. Turn Notifications off and on, then try again."
        case .relay(let message):
            message
        }
    }
}

/// Zelefin's push service hands each phone a private webhook address for Emby or Silo to post to.
enum PushHookRelay {
    static let baseURL = URL(string: "https://push.zelefin.app")!

    enum Service: String {
        case emby
        case silo
    }

    struct Hook: Decodable {
        let hookId: String
        let url: String
    }

    static func register(_ service: Service, token: String, label: String? = nil) async throws -> Hook {
        var body = ["platform": "ios", "token": token]
        if let label { body["label"] = label }
        let data = try await send("POST", "/\(service.rawValue)/v1/hooks", body: body)
        guard let hook = try? JSONDecoder().decode(Hook.self, from: data) else {
            throw EmbyAlertError.relay("Zelefin's push service did not answer. Try again in a moment.")
        }
        return hook
    }

    /// False when the push service no longer knows the hook, so the caller registers again.
    static func update(_ service: Service, hookID: String, token: String, signingSecret: String? = nil) async -> Bool {
        var body = ["platform": "ios", "token": token]
        if let signingSecret { body["signingSecret"] = signingSecret }
        return (try? await send("PUT", "/\(service.rawValue)/v1/hooks/\(hookID)", body: body)) != nil
    }

    static func remove(_ service: Service, hookID: String) async {
        _ = try? await send("DELETE", "/\(service.rawValue)/v1/hooks/\(hookID)", body: nil)
    }

    private static func send(_ method: String, _ path: String, body: [String: String]?) async throws -> Data {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
            throw EmbyAlertError.relay("Zelefin's push service could not save this iPhone. Try again in a moment.")
        }
        return data
    }
}

extension EmbyLibraryClient {
    static let webhookNotifier = "webhooknotifications"

    /// Whether this server can send webhooks (Emby's Webhooks notifier, part of Emby Premiere).
    func offersWebhooks() async -> Bool {
        struct Service: Decodable {
            let id: String?
            enum CodingKeys: String, CodingKey { case id = "Id" }
        }
        let services = (try? await api.decode([Service].self, "/Notifications/Services", query: [("UserId", userID)])) ?? []
        return services.contains { $0.id == Self.webhookNotifier }
    }

    /// Event ids this user may subscribe to. Emby leaves out what the account is not allowed to see.
    func availableAlertEvents() async -> Set<String> {
        struct Category: Decodable {
            struct Event: Decodable {
                let id: String?
                enum CodingKeys: String, CodingKey { case id = "Id" }
            }
            let events: [Event]?
            enum CodingKeys: String, CodingKey { case events = "Events" }
        }
        let categories = (try? await api.decode([Category].self, "/Notifications/Types", query: [("UserId", userID)])) ?? []
        return Set(categories.flatMap { $0.events ?? [] }.compactMap(\.id))
    }

    /// Adds or updates this user's webhook notification and returns its Emby id.
    func saveAlertWebhook(entryID: String?, url: String, events: [String], name: String) async throws -> String {
        var entry = try await webhookEntry(entryID: entryID)
        let existingID = entry["Id"] as? String
        entry["UserId"] = userID
        entry["FriendlyName"] = name
        entry["Enabled"] = true
        entry["EventIds"] = events
        entry["Options"] = ["Url": url, "EnableMultipartFormData": "false"]
        do {
            try await api.send("POST", "/Notifications/Services/Configured", json: entry)
        } catch let error as EmbyAPIError where error.statusCode == 401 || error.statusCode == 403 {
            throw EmbyAlertError.notAllowed(url: url)
        }
        if let existingID { return existingID }
        guard let saved = try await configuredWebhooks().first(where: { ($0["Options"] as? [String: Any])?["Url"] as? String == url }),
              let id = saved["Id"] as? String
        else {
            throw EmbyAlertError.relay("Emby saved the notification but did not list it. Try again.")
        }
        return id
    }

    func deleteAlertWebhook(entryID: String) async {
        _ = try? await api.data("DELETE", "/Notifications/Services/Configured", query: [("Id", entryID), ("UserId", userID)])
    }

    /// Emby sends its test event through the webhook, and the push service turns it into an alert.
    func testAlertWebhook(url: String, events: [String]) async throws {
        var entry = try await webhookEntry(entryID: nil)
        entry["UserId"] = userID
        entry["EventIds"] = events
        entry["Options"] = ["Url": url, "EnableMultipartFormData": "false"]
        try await api.send("POST", "/Notifications/Services/Test", json: entry)
    }

    /// The saved entry when Emby still has it, else a new one from Emby's defaults (without an `Id`).
    private func webhookEntry(entryID: String?) async throws -> [String: Any] {
        if let entryID, let existing = try await configuredWebhooks().first(where: { $0["Id"] as? String == entryID }) {
            return existing
        }
        let data = try await api.data(
            "GET",
            "/Notifications/Services/Defaults",
            query: [("UserId", userID), ("NotifierKey", Self.webhookNotifier)]
        )
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private func configuredWebhooks() async throws -> [[String: Any]] {
        let data = try await api.data("GET", "/Notifications/Services/Configured", query: [("UserId", userID)])
        return (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }
}
