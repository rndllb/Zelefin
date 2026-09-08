import Foundation

struct HomeNetworkProfile: Codable, Equatable, Sendable {
    var autoSwitch = false
    var localURLString = ""
    var homeSSIDs: [String] = []

    var localURL: URL? {
        try? ServerURL.normalizeLanAddress(localURLString)
    }
}

enum HomeNetworkRoute: String, Equatable, Sendable {
    case remote
    case local

    var title: String {
        switch self {
        case .remote: "Remote URL"
        case .local: "Local URL"
        }
    }
}

enum HomeNetworkCapabilities {
    static var canMatchSSID: Bool {
        true
    }
}

enum HomeNetworkStore {
    static func profile(for accountID: String) -> HomeNetworkProfile {
        guard let data = UserDefaults.standard.data(forKey: key(accountID)),
              let profile = try? JSONDecoder().decode(HomeNetworkProfile.self, from: data)
        else {
            return HomeNetworkProfile()
        }
        return profile
    }

    static func save(_ profile: HomeNetworkProfile, for accountID: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key(accountID))
    }

    private static func key(_ accountID: String) -> String {
        "zelefin.home-network.\(accountID)"
    }
}

enum HomeNetworkResolver {
    static func route(
        autoSwitch: Bool,
        hasLocalURL: Bool,
        homeSSIDs: [String],
        currentSSID: String?,
        ssidReadable: Bool
    ) -> HomeNetworkRoute {
        guard autoSwitch, hasLocalURL else { return .remote }
        if !ssidReadable {
            return .local
        }
        guard let currentSSID, isHome(currentSSID, in: homeSSIDs) else {
            return .remote
        }
        return .local
    }

    static func activeURL(remote: URL, local: URL?, route: HomeNetworkRoute) -> URL {
        if route == .local, let local {
            return local
        }
        return remote
    }

    static func isHome(_ ssid: String, in homeSSIDs: [String]) -> Bool {
        homeSSIDs.contains { $0.caseInsensitiveCompare(ssid) == .orderedSame }
    }

    static func adding(_ ssid: String, to homeSSIDs: [String]) -> [String] {
        let name = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isHome(name, in: homeSSIDs) else { return homeSSIDs }
        return (homeSSIDs + [name]).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func isSameEndpoint(_ a: URL, _ b: URL) -> Bool {
        trimmed(a).caseInsensitiveCompare(trimmed(b)) == .orderedSame
    }

    private static func trimmed(_ url: URL) -> String {
        var value = url.absoluteString
        while value.count > 1, value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
