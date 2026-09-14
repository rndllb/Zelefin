import Foundation
import JellyfinAPI

enum ZelefinCompanionPlugin {
    static func isInstalled(names: [String]) -> Bool {
        names.contains { name in
            let compact = name.lowercased().filter(\.isLetter)
            return compact == "zelefin" || compact.contains("jellyfinpluginzelefin")
        }
    }
}

struct CompanionConfig: Equatable, Sendable, Codable {
    var notificationsReady: Bool = false
}

enum CompanionSettings {
    static let pluginInstalledKey = "zelefin.companion.plugin-installed"

    /// Survives a background launch so local polling does not duplicate plugin push.
    static var pluginInstalled: Bool {
        get { UserDefaults.standard.bool(forKey: pluginInstalledKey) }
        set { UserDefaults.standard.set(newValue, forKey: pluginInstalledKey) }
    }
}

struct ZelefinCompanionClient: Sendable {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func config() async -> CompanionConfig? {
        guard let data = await send(path: "/Zelefin/config", method: "GET") else { return nil }
        return try? JSONDecoder().decode(CompanionConfig.self, from: data)
    }

    func registerDevice(token: String) async {
        let body = try? JSONSerialization.data(withJSONObject: [
            "token": token,
            "deviceId": DeviceIdentity.deviceID()
        ])
        _ = await send(path: "/Zelefin/device", method: "POST", body: body)
    }

    func deleteDevice() async {
        let id = DeviceIdentity.deviceID()
        _ = await send(path: "/Zelefin/device/\(id)", method: "DELETE")
    }

    private func send(path: String, method: String, body: Data? = nil) async -> Data? {
        guard let url = ServerURL.resolve(base: client.configuration.url, path: path, token: client.accessToken) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token = client.accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        do {
            let (data, response) = try await JellyfinNetworking.apiData(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
