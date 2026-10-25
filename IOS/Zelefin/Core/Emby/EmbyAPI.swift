import Foundation
import JellyfinAPI

/// Emby's own REST API. Emby forked from Jellyfin's ancestor and has drifted, so requests are
/// built here by hand; responses decode leniently into the shared DTOs so `ItemMapper` still applies.
final class EmbyAPI: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> Data

    let serverURL: URL
    let accessToken: String
    let deviceID: String
    private let transport: Transport

    init(serverURL: URL, accessToken: String, deviceID: String, transport: @escaping Transport = EmbyAPI.perform) {
        self.serverURL = serverURL
        self.accessToken = accessToken
        self.deviceID = deviceID
        self.transport = transport
    }

    static func authorization(deviceID: String) -> String {
        let device = DeviceIdentity.deviceName.replacingOccurrences(of: "\"", with: "'")
        return "MediaBrowser Client=\"\(DeviceIdentity.clientName)\", Device=\"\(device)\", DeviceId=\"\(deviceID)\", Version=\"\(DeviceIdentity.version)\""
    }

    func data(
        _ method: String = "GET",
        _ path: String,
        query: [(String, String?)] = [],
        body: Data? = nil,
        contentType: String = "application/json"
    ) async throws -> Data {
        try await transport(request(method, path, query: query, body: body, contentType: contentType))
    }

    func request(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        body: Data? = nil,
        contentType: String = "application/json"
    ) throws -> URLRequest {
        guard let base = ServerURL.resolve(base: serverURL, path: path) else {
            throw ZelefinError.invalidServerURL
        }
        var request = URLRequest(url: ServerURL.appending(query.filter { $0.1 != nil }, to: base))
        request.httpMethod = method
        request.setValue(accessToken, forHTTPHeaderField: "X-Emby-Token")
        request.setValue(Self.authorization(deviceID: deviceID), forHTTPHeaderField: "X-Emby-Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    func decode<T: Decodable>(
        _ type: T.Type,
        _ path: String,
        query: [(String, String?)] = [],
        method: String = "GET",
        body: Data? = nil
    ) async throws -> T {
        try EmbyJSON.decode(T.self, from: await data(method, path, query: query, body: body))
    }

    func send(
        _ method: String,
        _ path: String,
        query: [(String, String?)] = [],
        json: [String: Any]? = nil,
        body: Data? = nil
    ) async throws {
        let encoded = try body ?? json.map { try JSONSerialization.data(withJSONObject: $0) }
        _ = try await data(method, path, query: query, body: encoded)
    }

    /// Media, image, and download URLs carry the token as `api_key`, which players and
    /// `PlaybackHTTPHeaders` read back off the URL.
    func mediaURL(_ path: String, query: [(String, String?)] = []) -> URL? {
        guard let base = ServerURL.resolve(base: serverURL, path: path, token: accessToken) else { return nil }
        return ServerURL.appending(query.filter { $0.1 != nil }, to: base)
    }

    func signOut() async {
        _ = try? await data("POST", "/Sessions/Logout")
    }

    static func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await JellyfinNetworking.apiData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZelefinError.server("Emby did not answer.")
        }
        if AccessGateway.isChallenge(response: http, data: data) {
            throw ZelefinError.accessGateway
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw EmbyAPIError(statusCode: http.statusCode, body: data)
        }
        return data
    }

    /// `/System/Info/Public` needs no sign-in.
    static func publicInfo(at url: URL) async throws -> EmbyPublicInfo {
        guard let endpoint = ServerURL.resolve(base: url, path: "/System/Info/Public") else {
            throw ZelefinError.invalidServerURL
        }
        var request = URLRequest(url: endpoint)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return try EmbyPublicInfo(data: await perform(request))
    }

    static func isEmbyServer(at url: URL) async -> Bool {
        (try? await publicInfo(at: url))?.isEmby == true
    }

    static func authenticate(
        url: URL,
        username: String,
        password: String,
        deviceID: String
    ) async throws -> EmbyAuthentication {
        guard let endpoint = ServerURL.resolve(base: url, path: "/Users/AuthenticateByName") else {
            throw ZelefinError.invalidServerURL
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(authorization(deviceID: deviceID), forHTTPHeaderField: "X-Emby-Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["Username": username, "Pw": password])
        let data: Data
        do {
            data = try await perform(request)
        } catch let error as EmbyAPIError where error.statusCode == 401 {
            throw ZelefinError.server("Emby did not accept that username and password.")
        }
        let auth = try EmbyJSON.decode(EmbyAuthentication.self, from: data)
        guard !auth.accessToken.isEmpty, !auth.user.id.isEmpty else { throw ZelefinError.missingUser }
        return auth
    }
}

struct EmbyAPIError: LocalizedError, Sendable {
    let statusCode: Int
    let message: String?

    init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        message = text.isEmpty || text.hasPrefix("<") ? nil : String(text.prefix(200))
    }

    var errorDescription: String? {
        if statusCode == 401 { return "Emby rejected this session. Sign in again." }
        if let message { return "Emby returned an error (\(statusCode)): \(message)" }
        return "Emby returned an error (\(statusCode))."
    }
}

struct EmbyPublicInfo: Sendable, Equatable {
    var serverName: String?
    var version: String?
    var id: String?
    var productName: String?

    init(serverName: String? = nil, version: String? = nil, id: String? = nil, productName: String? = nil) {
        self.serverName = serverName
        self.version = version
        self.id = id
        self.productName = productName
    }

    init(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ZelefinError.server("The server did not describe itself.")
        }
        self.init(json: json)
    }

    init(json: [String: Any]) {
        serverName = json["ServerName"] as? String
        version = json["Version"] as? String
        id = json["Id"] as? String
        productName = json["ProductName"] as? String
    }

    /// Jellyfin (and Silo's Jellyfin-compatible API) always names itself in `ProductName`
    /// ("Jellyfin Server") and is on 10.x or later; Emby leaves the field out and is on 4.x.
    var isEmby: Bool {
        if let productName = productName?.trimmingCharacters(in: .whitespacesAndNewlines), !productName.isEmpty {
            return productName.range(of: "emby", options: .caseInsensitive) != nil
        }
        guard let major = version?.split(separator: ".").first.flatMap({ Int($0) }) else { return false }
        return (4 ..< 10).contains(major)
    }
}

struct EmbyAuthentication: Decodable, Sendable {
    struct User: Decodable, Sendable {
        struct Policy: Decodable, Sendable {
            var isAdministrator: Bool?

            enum CodingKeys: String, CodingKey {
                case isAdministrator = "IsAdministrator"
            }
        }

        var id: String
        var name: String?
        var primaryImageTag: String?
        var policy: Policy?

        enum CodingKeys: String, CodingKey {
            case id = "Id"
            case name = "Name"
            case primaryImageTag = "PrimaryImageTag"
            case policy = "Policy"
        }
    }

    var accessToken: String
    var serverID: String?
    var user: User

    enum CodingKeys: String, CodingKey {
        case accessToken = "AccessToken"
        case serverID = "ServerId"
        case user = "User"
    }
}

/// Decodes Emby JSON into the shared Jellyfin-shaped models. Emby sends numeric ids where
/// Jellyfin sends strings, enum values Jellyfin never defined, and its HDR flavor in
/// `ExtendedVideoType`; those are normalized first, and any value that still fails to decode
/// is dropped (with every sibling holding the same value) until the document decodes.
enum EmbyJSON {
    private static let maxRepairs = 64

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JellyfinJSONDate.decoder
        guard var root = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return try decoder.decode(T.self, from: data)
        }
        root = normalized(root)
        var lastError: Error?
        for _ in 0 ..< maxRepairs {
            let attempt = try JSONSerialization.data(withJSONObject: root, options: [.fragmentsAllowed])
            do {
                return try decoder.decode(T.self, from: attempt)
            } catch let error as DecodingError {
                lastError = error
                guard let path = offendingPath(error), !path.isEmpty else { throw error }
                let offending = value(at: path[...], in: root)
                var changed = false
                root = removing(path[...], from: root, matching: offending, changed: &changed)
                guard changed else { throw error }
            }
        }
        throw lastError ?? ZelefinError.server("Zelefin could not read Emby's response.")
    }

    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// A missing required key (Jellyfin's `UserPolicy` requires fields Emby never sends) drops the
    /// nested object that lacks it.
    private static func offendingPath(_ error: DecodingError) -> [CodingKey]? {
        switch error {
        case let .typeMismatch(_, context), let .valueNotFound(_, context), let .dataCorrupted(context):
            return context.codingPath
        case let .keyNotFound(_, context):
            return context.codingPath
        @unknown default:
            return nil
        }
    }

    static func normalized(_ value: Any) -> Any {
        if var object = value as? [String: Any] {
            for (key, child) in object {
                if key.hasSuffix("Id"), let number = child as? NSNumber, !isBoolean(number) {
                    object[key] = number.stringValue
                } else {
                    object[key] = normalized(child)
                }
            }
            // Jellyfin's UserPolicy requires both provider ids; Emby sends one at most.
            if object["IsAdministrator"] != nil, object["EnableAllFolders"] != nil {
                for key in ["AuthenticationProviderId", "PasswordResetProviderId"] where object[key] == nil {
                    object[key] = ""
                }
            }
            if object["Type"] as? String == "Video", object["VideoRangeType"] == nil,
               let extended = object["ExtendedVideoType"] as? String,
               let rangeType = videoRangeType(extendedVideoType: extended) {
                object["VideoRangeType"] = rangeType
            }
            return object
        }
        if let array = value as? [Any] {
            return array.map(normalized)
        }
        return value
    }

    static func videoRangeType(extendedVideoType raw: String) -> String? {
        switch raw.lowercased() {
        case "dolbyvision": "DOVI"
        case "hdr10plus": "HDR10Plus"
        case "hdr10": "HDR10"
        case "hyperloggamma", "hlg": "HLG"
        default: nil
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func value(at path: ArraySlice<CodingKey>, in node: Any) -> Any? {
        guard let key = path.first else { return node }
        if let index = key.intValue, let array = node as? [Any], array.indices.contains(index) {
            return value(at: path.dropFirst(), in: array[index])
        }
        if let object = node as? [String: Any], let child = object[key.stringValue] {
            return value(at: path.dropFirst(), in: child)
        }
        return nil
    }

    /// Array indices in `path` act as wildcards, so one bad enum value in a 200-item page
    /// costs one repair rather than 200.
    private static func removing(
        _ path: ArraySlice<CodingKey>,
        from node: Any,
        matching offending: Any?,
        changed: inout Bool
    ) -> Any {
        guard let key = path.first else { return node }
        let rest = path.dropFirst()
        if key.intValue != nil, var array = node as? [Any] {
            if rest.isEmpty {
                let kept = array.filter { !sameValue($0, offending) }
                if kept.count != array.count { changed = true }
                return kept
            }
            for index in array.indices {
                array[index] = removing(rest, from: array[index], matching: offending, changed: &changed)
            }
            return array
        }
        guard var object = node as? [String: Any], let child = object[key.stringValue] else { return node }
        if rest.isEmpty {
            if sameValue(child, offending) {
                object[key.stringValue] = nil
                changed = true
            }
        } else {
            object[key.stringValue] = removing(rest, from: child, matching: offending, changed: &changed)
        }
        return object
    }

    private static func sameValue(_ lhs: Any, _ rhs: Any?) -> Bool {
        guard let rhs else { return true }
        if let left = lhs as? String, let right = rhs as? String { return left == right }
        if lhs is String || rhs is String { return false }
        if let left = lhs as? NSNumber, let right = rhs as? NSNumber {
            return isBoolean(left) == isBoolean(right)
        }
        if lhs is [Any], rhs is [Any] { return true }
        if lhs is [String: Any], rhs is [String: Any] { return true }
        return lhs is NSNull && rhs is NSNull
    }
}
