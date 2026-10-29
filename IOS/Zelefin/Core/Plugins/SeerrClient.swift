import Foundation

struct SeerrTitle: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case movie
        case tv

        var symbolName: String {
            switch self {
            case .movie: "movieclapper.fill"
            case .tv: "tv.fill"
            }
        }

        var accessibilityName: String {
            switch self {
            case .movie: "Movie"
            case .tv: "Show"
            }
        }
    }

    enum Availability: String, Hashable, Sendable {
        case unknown
        case pending
        case processing
        case partial
        case available
        case missing

        init(status: Int?) {
            switch status {
            case 2: self = .pending
            case 3: self = .processing
            case 4: self = .partial
            case 5: self = .available
            case 1: self = .unknown
            default: self = .missing
            }
        }

        var isOnServer: Bool { self == .available || self == .partial }
        var isRequested: Bool { self == .pending || self == .processing || self == .partial }

        var canRequest: Bool {
            switch self {
            case .missing, .unknown, .partial: true
            case .available, .pending, .processing: false
            }
        }

        var buttonTitle: String {
            switch self {
            case .available: "In Library"
            case .pending, .processing: "Requested"
            case .partial: "Request More"
            case .unknown, .missing: "Request"
            }
        }
    }

    var id: String {
        if let requestID {
            return "request-\(requestID)"
        }
        return "\(kind.rawValue)-\(tmdbID)"
    }
    let tmdbID: Int
    let kind: Kind
    let name: String
    var year: Int?
    var overview: String?
    var posterURL: URL?
    var availability: Availability
    var requestedByName: String? = nil
    var requestID: Int? = nil
    /// Seerr's own request status, separate from whether the title is on the server.
    var review: Review? = nil
    /// Ombi's show request that holds `requestID`, which is one batch of its seasons.
    var parentRequestID: Int? = nil

    enum Review: String, Hashable, Sendable {
        case pendingApproval
        case approved
        case declined

        init?(status: Int?) {
            switch status {
            case 1: self = .pendingApproval
            case 2: self = .approved
            case 3: self = .declined
            default: return nil
            }
        }
    }

    var canRequest: Bool { availability.canRequest }

    /// A Boolean value that's true when this title is already on the Jellyfin server.
    func isInJellyfin(catalog: JellyfinTmdbCatalog) -> Bool {
        availability.isOnServer || catalog.contains(self)
    }
}

struct SeerrUser: Decodable, Sendable {
    var id: Int? = nil
    var email: String? = nil
    var username: String? = nil
    var displayName: String? = nil
    var jellyfinUsername: String? = nil
    var plexUsername: String? = nil
    var permissions: Int? = nil

    /// Overseerr/Seerr: admin is bit 2, manage requests is bit 16.
    var canManageRequests: Bool {
        let bits = permissions ?? 0
        return bits & 2 != 0 || bits & 16 != 0
    }

    var displayLabel: String {
        [username, jellyfinUsername, displayName, plexUsername, email]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "Seerr"
    }

    /// A name suitable for a Recent Requests poster, or `nil` when Seerr has no identity.
    var requestLabel: String? {
        let label = displayLabel
        return label == "Seerr" ? nil : label
    }
}

struct SeerrClient: Sendable {
    var baseURL: URL
    var session: SeerrSession?

    func search(term: String) async throws -> [SeerrTitle] {
        var components = URLComponents(url: baseURL.appending(path: "api/v1/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "query", value: term),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "language", value: "en")
        ]
        guard let url = components?.url else { return [] }
        let payload: SeerrSearchResponse = try await get(url)
        return payload.results.compactMap { Self.title(from: $0) }
    }

    func request(_ title: SeerrTitle) async throws {
        try await request(
            SeerrRequestDraft(
                kind: title.kind,
                tmdbID: title.tmdbID,
                seasons: title.kind == .tv ? .all : nil
            )
        )
    }

    func request(_ draft: SeerrRequestDraft) async throws {
        try await post(baseURL.appending(path: "api/v1/request"), body: draft.jsonObject)
    }

    func approveRequest(id: Int, draft: SeerrRequestDraft) async throws {
        try await post(baseURL.appending(path: "api/v1/request/\(id)/approve"), body: draft.jsonObject)
    }

    func requestDetails(id: Int) async throws -> SeerrStoredRequest {
        try await get(baseURL.appending(path: "api/v1/request/\(id)"))
    }

    func declineRequest(id: Int) async throws {
        try await post(baseURL.appending(path: "api/v1/request/\(id)/decline"), body: [:])
    }

    func radarrServers() async throws -> [SeerrServiceServer] {
        try await get(baseURL.appending(path: "api/v1/service/radarr"))
    }

    func sonarrServers() async throws -> [SeerrServiceServer] {
        try await get(baseURL.appending(path: "api/v1/service/sonarr"))
    }

    func radarrDetails(id: Int) async throws -> SeerrServiceDetails {
        try await get(baseURL.appending(path: "api/v1/service/radarr/\(id)"))
    }

    func sonarrDetails(id: Int) async throws -> SeerrServiceDetails {
        try await get(baseURL.appending(path: "api/v1/service/sonarr/\(id)"))
    }

    func tvDetails(id: Int) async throws -> SeerrTvDetails {
        try await get(baseURL.appending(path: "api/v1/tv/\(id)"))
    }

    func currentUser() async throws -> SeerrUser {
        try await get(baseURL.appending(path: "api/v1/auth/me"))
    }

    func fetch<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        guard let url = components?.url else {
            throw ZelefinError.invalidServerURL
        }
        return try await get(url)
    }

    static func signIn(baseURL: URL, username: String, password: String) async throws -> SeerrSession {
        let trimmedName = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw ZelefinError.server("Enter your Seerr username.")
        }
        guard !trimmedPassword.isEmpty else {
            throw ZelefinError.server("Enter your Jellyfin or Seerr password.")
        }

        do {
            return try await authenticate(
                baseURL: baseURL,
                path: "api/v1/auth/jellyfin",
                body: jellyfinBody(username: trimmedName, password: trimmedPassword)
            )
        } catch {
            let jellyfinError = error
            do {
                return try await authenticate(
                    baseURL: baseURL,
                    path: "api/v1/auth/local",
                    body: [
                        "email": trimmedName,
                        "password": trimmedPassword
                    ]
                )
            } catch {
                throw jellyfinError
            }
        }
    }

    static func jellyfinBody(username: String, password: String) -> [String: Any] {
        [
            "username": username,
            "password": password
        ]
    }

    private static func authenticate(baseURL: URL, path: String, body: [String: Any]) async throws -> SeerrSession {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        AccessGateway.apply(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await SeerrTransport.session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZelefinError.server("Seerr did not respond.")
        }
        try throwIfNeeded(http, data: data)
        guard let cookie = SeerrCookie.parse(
            from: http,
            url: url,
            storage: SeerrTransport.session.configuration.httpCookieStorage
        ) else {
            throw ZelefinError.server("Seerr signed in but did not return a session cookie.")
        }
        let user = try? JSONDecoder().decode(SeerrUser.self, from: data)
        return SeerrSession(
            cookieName: cookie.name,
            cookieValue: cookie.value,
            displayName: user?.displayLabel ?? "Seerr"
        )
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        applyHeaders(&request)
        let (data, response) = try await SeerrTransport.session.data(for: request)
        try Self.throwIfNeeded(response, data: data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ url: URL, body: [String: Any]) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(&request)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await SeerrTransport.session.data(for: request)
        try Self.throwIfNeeded(response, data: data)
    }

    private func applyHeaders(_ request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        AccessGateway.apply(&request)
        if let session {
            request.setValue(SeerrCookie.header(session: session, url: baseURL), forHTTPHeaderField: "Cookie")
        }
    }

    private static func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        try throwIfNeeded(http, data: data)
    }

    private static func throwIfNeeded(_ http: HTTPURLResponse, data: Data) throws {
        if AccessGateway.isChallenge(response: http, data: data) {
            throw ZelefinError.accessGateway
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ZelefinError.seerrUnauthorized
        }
        guard (200 ..< 300).contains(http.statusCode) else {
            throw ZelefinError.server(Self.errorMessage(from: data, status: http.statusCode))
        }
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["message", "error"] {
                if let value = object[key] as? String,
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    return value
                }
            }
        }
        let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "Seerr returned \(status)."
    }

    static func tmdbImageURL(_ path: String?, size: String = "w342") -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }
        let trimmed = path.hasPrefix("/") ? path : "/\(path)"
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(trimmed)")
    }

    static func title(from result: SeerrSearchResult, defaultKind: SeerrTitle.Kind? = nil) -> SeerrTitle? {
        if result.mediaType == "person" { return nil }
        let kind: SeerrTitle.Kind
        if result.mediaType == "tv" {
            kind = .tv
        } else if result.mediaType == "movie" {
            kind = .movie
        } else if let defaultKind {
            kind = defaultKind
        } else {
            return nil
        }
        let name = result.title ?? result.name ?? ""
        guard !name.isEmpty else { return nil }
        let date = result.releaseDate ?? result.firstAirDate
        let year = date.flatMap { Int($0.prefix(4)) }
        return SeerrTitle(
            tmdbID: result.id,
            kind: kind,
            name: name,
            year: year,
            overview: result.overview,
            posterURL: tmdbImageURL(result.posterPath),
            availability: .init(status: result.mediaInfo?.status)
        )
    }
}

enum SeerrTransport {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        return URLSession(configuration: configuration)
    }()
}

enum SeerrCookie {
    static func parse(setCookie: String) -> (name: String, value: String)? {
        let firstPair = setCookie.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let separator = firstPair.firstIndex(of: "=") else { return nil }
        let name = String(firstPair[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
        var value = String(firstPair[firstPair.index(after: separator)...])
        if let decoded = value.removingPercentEncoding {
            value = decoded
        }
        guard !name.isEmpty, !value.isEmpty else { return nil }
        return (name, value)
    }

    static func preferred(from cookies: [HTTPCookie]) -> (name: String, value: String)? {
        let match = cookies.first(where: { $0.name == "connect.sid" }) ?? cookies.first
        guard let match, !match.value.isEmpty else { return nil }
        return (match.name, match.value)
    }

    static func parse(
        from response: HTTPURLResponse,
        url: URL,
        storage: HTTPCookieStorage? = nil
    ) -> (name: String, value: String)? {
        var headerFields: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let key = key as? String, let value = value as? String else { continue }
            headerFields[key] = value
        }
        if let cookie = preferred(from: HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url)) {
            return cookie
        }
        if let setCookie = response.value(forHTTPHeaderField: "Set-Cookie"),
           let cookie = parse(setCookie: setCookie)
        {
            return cookie
        }
        let stored = storage?.cookies(for: url) ?? storage?.cookies ?? []
        return preferred(from: stored)
    }

    static func header(session: SeerrSession, url: URL) -> String {
        if let host = url.host,
           let cookie = HTTPCookie(properties: [
               .domain: host,
               .path: "/",
               .name: session.cookieName,
               .value: session.cookieValue
           ])
        {
            let fields = HTTPCookie.requestHeaderFields(with: [cookie])
            if let value = fields["Cookie"], !value.isEmpty {
                return value
            }
        }
        return "\(session.cookieName)=\(session.cookieValue)"
    }
}

struct SeerrSearchResponse: Decodable, Sendable {
    var page: Int?
    var totalPages: Int?
    var results: [SeerrSearchResult]
}

struct SeerrSearchResult: Decodable, Sendable {
    var id: Int
    var mediaType: String?
    var title: String?
    var name: String?
    var releaseDate: String?
    var firstAirDate: String?
    var overview: String?
    var posterPath: String?
    var mediaInfo: SeerrMediaInfo?
}

struct SeerrMediaInfo: Decodable, Sendable {
    var status: Int?
    var tmdbId: Int?
    var mediaType: String?
    var seasons: [SeerrMediaSeason]?
    /// The title's requests, on a movie or show's own page.
    var requests: [SeerrMediaRequest]?

    init(status: Int?, seasons: [SeerrMediaSeason]? = nil, tmdbId: Int? = nil, mediaType: String? = nil) {
        self.status = status
        self.seasons = seasons
        self.tmdbId = tmdbId
        self.mediaType = mediaType
    }
}

struct SeerrMediaRequest: Decodable, Sendable {
    var id: Int
    var status: Int?
    var is4k: Bool?
    var requestedBy: SeerrUser?
}

struct SeerrMediaSeason: Decodable, Hashable, Sendable {
    var seasonNumber: Int
    var status: Int?
    var status4k: Int?

    func isOccupied(is4k: Bool) -> Bool {
        let value = is4k ? (status4k ?? status) : status
        switch value {
        case 2, 3, 4, 5: return true
        default: return false
        }
    }
}

enum SeerrSeasonSelection: Equatable, Sendable {
    case all
    case numbers([Int])
}

struct SeerrStoredRequest: Decodable, Sendable {
    var is4k: Bool?
    var serverId: Int?
    var profileId: Int?
    var rootFolder: String?
    var languageProfileId: Int?
    var seasons: [SeerrStoredSeason]?
}

struct SeerrStoredSeason: Decodable, Sendable {
    var seasonNumber: Int
}

struct SeerrRequestDraft: Equatable, Sendable {
    var kind: SeerrTitle.Kind
    var tmdbID: Int
    var seasons: SeerrSeasonSelection?
    var is4k: Bool = false
    var serverID: Int?
    var profileID: Int?
    var rootFolder: String?
    var languageProfileID: Int?
    /// Ombi names a folder by its Radarr or Sonarr ID rather than its path.
    var rootFolderID: Int? = nil
    /// Ombi's show request, whose quality and folder an admin changes before approving.
    var parentRequestID: Int? = nil

    var jsonObject: [String: Any] {
        var body: [String: Any] = [
            "mediaType": kind.rawValue,
            "mediaId": tmdbID,
            "is4k": is4k
        ]
        switch seasons {
        case .all:
            body["seasons"] = "all"
        case let .numbers(values):
            body["seasons"] = values
        case nil:
            break
        }
        if let serverID { body["serverId"] = serverID }
        if let profileID { body["profileId"] = profileID }
        if let rootFolder, !rootFolder.isEmpty { body["rootFolder"] = rootFolder }
        if let languageProfileID { body["languageProfileId"] = languageProfileID }
        return body
    }
}

struct SeerrServiceServer: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var is4k: Bool?
    var isDefault: Bool?
    var activeDirectory: String?
    var activeProfileId: Int?
    var activeLanguageProfileId: Int?

    var uses4K: Bool { is4k ?? false }
    var isDefaultServer: Bool { isDefault ?? false }

    init(
        id: Int,
        name: String,
        is4k: Bool? = nil,
        isDefault: Bool? = nil,
        activeDirectory: String? = nil,
        activeProfileId: Int? = nil,
        activeLanguageProfileId: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.is4k = is4k
        self.isDefault = isDefault
        self.activeDirectory = activeDirectory
        self.activeProfileId = activeProfileId
        self.activeLanguageProfileId = activeLanguageProfileId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Server \(id)"
        is4k = try container.decodeIfPresent(Bool.self, forKey: .is4k)
        isDefault = try container.decodeIfPresent(Bool.self, forKey: .isDefault)
        activeDirectory = try container.decodeIfPresent(String.self, forKey: .activeDirectory)
        activeProfileId = try container.decodeIfPresent(Int.self, forKey: .activeProfileId)
        activeLanguageProfileId = try container.decodeIfPresent(Int.self, forKey: .activeLanguageProfileId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, is4k, isDefault, activeDirectory, activeProfileId, activeLanguageProfileId
    }
}

struct SeerrServiceProfile: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
}

struct SeerrRootFolder: Decodable, Hashable, Sendable, Identifiable {
    var id: String { path }
    var folderID: Int?
    var path: String
    var freeSpace: Double?

    var pickerTitle: String {
        guard let freeSpace else { return path }
        let bytes = ByteCountFormatter.string(fromByteCount: Int64(freeSpace), countStyle: .file)
        return "\(path) · \(bytes) free"
    }

    init(folderID: Int? = nil, path: String, freeSpace: Double? = nil) {
        self.folderID = folderID
        self.path = path
        self.freeSpace = freeSpace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        folderID = try? container.decode(Int.self, forKey: .folderID)
        if let value = try? container.decode(Double.self, forKey: .freeSpace) {
            freeSpace = value
        } else if let value = try? container.decode(Int64.self, forKey: .freeSpace) {
            freeSpace = Double(value)
        } else {
            freeSpace = nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case folderID = "id"
        case path
        case freeSpace
    }
}

struct SeerrServiceDetails: Decodable, Sendable {
    var server: SeerrServiceServer
    var profiles: [SeerrServiceProfile]
    var rootFolders: [SeerrRootFolder]
    var languageProfiles: [SeerrServiceProfile]?

    init(
        server: SeerrServiceServer,
        profiles: [SeerrServiceProfile],
        rootFolders: [SeerrRootFolder],
        languageProfiles: [SeerrServiceProfile]? = nil
    ) {
        self.server = server
        self.profiles = profiles
        self.rootFolders = rootFolders
        self.languageProfiles = languageProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        server = try container.decode(SeerrServiceServer.self, forKey: .server)
        profiles = try container.decodeIfPresent([SeerrServiceProfile].self, forKey: .profiles) ?? []
        rootFolders = try container.decodeIfPresent([SeerrRootFolder].self, forKey: .rootFolders) ?? []
        languageProfiles = try container.decodeIfPresent([SeerrServiceProfile].self, forKey: .languageProfiles)
    }

    private enum CodingKeys: String, CodingKey {
        case server, profiles, rootFolders, languageProfiles
    }
}

struct SeerrTvDetails: Decodable, Sendable {
    var id: Int
    var name: String?
    var seasons: [SeerrSeason]
    var mediaInfo: SeerrMediaInfo?
    var relatedVideos: [SeerrRelatedVideo]?

    init(id: Int, name: String?, seasons: [SeerrSeason], mediaInfo: SeerrMediaInfo?, relatedVideos: [SeerrRelatedVideo]? = nil) {
        self.id = id
        self.name = name
        self.seasons = seasons
        self.mediaInfo = mediaInfo
        self.relatedVideos = relatedVideos
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        seasons = try container.decodeIfPresent([SeerrSeason].self, forKey: .seasons) ?? []
        mediaInfo = try container.decodeIfPresent(SeerrMediaInfo.self, forKey: .mediaInfo)
        relatedVideos = try container.decodeIfPresent([SeerrRelatedVideo].self, forKey: .relatedVideos)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, seasons, mediaInfo, relatedVideos
    }
}

struct SeerrRelatedVideo: Decodable, Sendable {
    var key: String?
    var name: String?
    var site: String?
    var type: String?
    var url: String?
    var official: Bool?
}

struct SeerrSeason: Decodable, Hashable, Sendable, Identifiable {
    var id: Int { seasonNumber }
    var name: String?
    var seasonNumber: Int
    var episodeCount: Int?
    var airDate: String?

    var isSpecials: Bool { seasonNumber == 0 }
    var title: String {
        if isSpecials { return name ?? "Specials" }
        if let name, !name.isEmpty, name != "Season \(seasonNumber)" {
            return "Season \(seasonNumber) · \(name)"
        }
        return "Season \(seasonNumber)"
    }
}

enum SeerrRequestDefaults {
    static func preferredServer(from servers: [SeerrServiceServer], is4k: Bool) -> SeerrServiceServer? {
        let matching = servers.filter { $0.uses4K == is4k }
        return matching.first(where: \.isDefaultServer) ?? matching.first ?? servers.first
    }
}
