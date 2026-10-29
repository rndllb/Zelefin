import Foundation

struct OmbiSession: Codable, Equatable, Sendable {
    var token: String
    var displayName: String
}

/// Ombi v4's API. Ombi decides the Radarr or Sonarr server, quality, and folder itself, so requests
/// only name the title and, for shows, the seasons.
struct OmbiClient: RequestServiceClient {
    var baseURL: URL
    var session: OmbiSession?

    var service: RequestService { .ombi }
    /// Admins and power users pick the quality and folder from Ombi's Radarr and Sonarr.
    var choosesDownloadServer: Bool { true }
    var browsesGenresAndCompanies: Bool { false }

    /// A page of a Discover row.
    private static let pageSize = 20

    // MARK: Sign-in

    /// Ombi signs in its own users and those imported from Jellyfin or Emby, with that server's password.
    static func signIn(baseURL: URL, username: String, password: String) async throws -> OmbiSession {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ZelefinError.server("Enter your Ombi username.") }
        guard !password.isEmpty else { throw ZelefinError.server("Enter your Ombi password.") }
        let body: [String: Any] = [
            "username": name,
            "password": password,
            "rememberMe": true,
            "usePlexAdminAccount": false,
            "usePlexOAuth": false
        ]
        let anonymous = OmbiClient(baseURL: baseURL, session: nil)
        let token: OmbiToken
        do {
            token = try await anonymous.send("api/v1/Token", method: "POST", body: body)
        } catch ZelefinError.seerrUnauthorized {
            throw ZelefinError.server("Ombi didn't accept that username and password.")
        }
        guard let value = token.accessToken, !value.isEmpty else {
            throw ZelefinError.server("Ombi signed in but didn't return a token.")
        }
        var session = OmbiSession(token: value, displayName: name)
        if let user = try? await OmbiClient(baseURL: baseURL, session: session).identity() {
            session.displayName = user.label ?? name
        }
        return session
    }

    func currentUser() async throws -> SeerrUser {
        let user = try await identity()
        return SeerrUser(
            email: user.emailAddress,
            username: user.label,
            permissions: user.canManageRequests ? 2 : 0
        )
    }

    private func identity() async throws -> OmbiUser {
        try await send("api/v1/Identity")
    }

    // MARK: Search and Discover

    /// Ombi's search has no request state, so each result is looked up for it, as Ombi's own site does.
    func search(term: String) async throws -> [SeerrTitle] {
        let filter: [String: Any] = ["movies": true, "tvShows": true, "music": false, "people": false]
        let results: [OmbiMultiResult] = try await send("api/v2/Search/multi/\(Self.pathComponent(term))", method: "POST", body: filter)
        let basics = results.prefix(Self.pageSize).compactMap(\.seerrTitle)
        return await withTaskGroup(of: (Int, SeerrTitle).self) { group in
            for (index, basic) in basics.enumerated() {
                group.addTask {
                    let detailed = (try? await self.titleDetails(kind: basic.kind, tmdbID: basic.tmdbID)) ?? basic
                    return (index, Self.keepingPoster(of: basic, in: detailed))
                }
            }
            var slots = basics
            for await (index, title) in group {
                slots[index] = title
            }
            return slots
        }
    }

    func discoverHome() async -> SeerrDiscoverHome {
        async let requests = discover(.requests, page: 1)
        async let trending = discover(.trending, page: 1)
        async let popularMovies = discover(.popularMovies, page: 1)
        async let upcomingMovies = discover(.upcomingMovies, page: 1)
        async let popularTV = discover(.popularTV, page: 1)
        async let upcomingTV = discover(.upcomingTV, page: 1)
        return SeerrDiscoverHome(
            recentRequests: (try? await requests)?.titles ?? [],
            trending: (try? await trending)?.titles ?? [],
            popularMovies: (try? await popularMovies)?.titles ?? [],
            upcomingMovies: (try? await upcomingMovies)?.titles ?? [],
            popularTV: (try? await popularTV)?.titles ?? [],
            upcomingTV: (try? await upcomingTV)?.titles ?? []
        )
    }

    func discover(_ query: SeerrDiscoverQuery, page: Int) async throws -> SeerrDiscoverPage {
        let position = (page - 1) * Self.pageSize
        let titles: [SeerrTitle]
        switch query {
        case .requests:
            titles = try await recentRequests(position: position)
        case .trending:
            async let movies = movieList("nowplaying", position: position)
            async let shows = tvList("trending", position: position)
            titles = Self.interleave(try await movies, try await shows)
        case .popularMovies:
            titles = try await movieList("popular", position: position)
        case .upcomingMovies:
            titles = try await movieList("upcoming", position: position)
        case .popularTV:
            titles = try await tvList("popular", position: position)
        case .upcomingTV:
            titles = try await tvList("anticipated", position: position)
        case .movieGenre, .tvGenre, .studio, .network:
            titles = []
        }
        return SeerrDiscoverPage(titles: titles, page: page, totalPages: titles.count >= Self.pageSize ? page + 1 : page)
    }

    private func movieList(_ list: String, position: Int) async throws -> [SeerrTitle] {
        let movies: [OmbiMovie] = try await send("api/v2/Search/movie/\(list)/\(position)/\(Self.pageSize)")
        return movies.compactMap(\.seerrTitle)
    }

    private func tvList(_ list: String, position: Int) async throws -> [SeerrTitle] {
        let shows: [OmbiShow] = try await send("api/v2/Search/tv/\(list)/\(position)/\(Self.pageSize)")
        return shows.compactMap(\.seerrTitle)
    }

    private func titleDetails(kind: SeerrTitle.Kind, tmdbID: Int) async throws -> SeerrTitle? {
        switch kind {
        case .movie:
            let movie: OmbiMovie = try await send("api/v2/Search/movie/\(tmdbID)")
            return movie.seerrTitle
        case .tv:
            let show: OmbiShow = try await send("api/v2/Search/tv/moviedb/\(tmdbID)")
            return show.seerrTitle
        }
    }

    /// Movie and show requests together, newest first.
    private func recentRequests(position: Int) async throws -> [SeerrTitle] {
        let count = Self.pageSize
        async let movies: OmbiRequestPage<OmbiMovieRequest> = send("api/v2/Requests/movie/\(count)/\(position)/requestedDate/desc")
        async let shows: OmbiRequestPage<OmbiChildRequest> = send("api/v2/Requests/tv/\(count)/\(position)/requestedDate/desc")
        let movieRequests = (try? await movies)?.collection ?? []
        let showRequests = (try? await shows)?.collection ?? []
        let dated = movieRequests.compactMap { request in request.seerrTitle.map { (request.requestedDate ?? "", $0) } }
            + showRequests.compactMap { request in request.seerrTitle.map { (request.requestedDate ?? "", $0) } }
        return dated.sorted { $0.0 > $1.0 }.prefix(count).map(\.1)
    }

    // MARK: Requests

    func requestStatus(for title: SeerrTitle) async throws -> SeerrTitle {
        guard var current = try await titleDetails(kind: title.kind, tmdbID: title.tmdbID) else { return title }
        current = Self.keepingPoster(of: title, in: current)
        current.requestedByName = nil
        guard let requestID = current.requestID, current.availability != .available else { return current }
        switch title.kind {
        case .movie:
            if let request: OmbiMovieRequest = try? await send("api/v1/Request/movie/info/\(requestID)") {
                current.requestedByName = request.requestedUser?.label
            }
        case .tv:
            // The show's request holds one request per batch of seasons; the one waiting comes first.
            let show: OmbiShowRequest = try await send("api/v1/Request/tv/\(requestID)")
            let children = show.childRequests ?? []
            let open = children.last { $0.approved != true && $0.denied != true && $0.available != true }
                ?? children.last { $0.denied != true }
            current.parentRequestID = requestID
            current.requestID = nil
            if let open {
                let showAvailability = current.availability
                OmbiReview(approved: open.approved, available: open.available, denied: open.denied)
                    .apply(to: &current, requestID: open.id, requester: open.requestedUser)
                if showAvailability == .partial {
                    current.availability = .partial
                }
            }
        }
        return current
    }

    func tvDetails(id: Int) async throws -> SeerrTvDetails {
        let show: OmbiShow = try await send("api/v2/Search/tv/moviedb/\(id)")
        let seasons = (show.seasonRequests ?? []).sorted { $0.seasonNumber < $1.seasonNumber }
        return SeerrTvDetails(
            id: id,
            name: show.title,
            seasons: seasons.map { SeerrSeason(seasonNumber: $0.seasonNumber, episodeCount: $0.episodes?.count) },
            mediaInfo: SeerrMediaInfo(
                status: nil,
                seasons: seasons.map { SeerrMediaSeason(seasonNumber: $0.seasonNumber, status: $0.isTaken ? 2 : 1) }
            )
        )
    }

    func request(_ draft: SeerrRequestDraft) async throws {
        switch draft.kind {
        case .movie:
            var body: [String: Any] = ["theMovieDbId": draft.tmdbID, "languageCode": "en", "is4kRequest": draft.is4k]
            Self.addOverrides(draft, to: &body)
            try Self.check(try await send("api/v1/Request/movie", method: "POST", body: body))
        case .tv:
            var body = try await showRequestBody(draft)
            Self.addOverrides(draft, to: &body)
            try Self.check(try await send("api/v2/Requests/tv", method: "POST", body: body))
        }
    }

    /// An admin's quality and folder choice. Ombi ignores these from other users.
    private static func addOverrides(_ draft: SeerrRequestDraft, to body: inout [String: Any]) {
        if let profileID = draft.profileID { body["qualityPathOverride"] = profileID }
        if let folderID = draft.rootFolderID { body["rootFolderOverride"] = folderID }
        if draft.kind == .tv, let language = draft.languageProfileID { body["languageProfile"] = language }
    }

    /// Ombi requests episodes, so each picked season lists the episodes not yet requested or on the server.
    private func showRequestBody(_ draft: SeerrRequestDraft) async throws -> [String: Any] {
        var body: [String: Any] = [
            "theMovieDbId": draft.tmdbID,
            "languageCode": "en",
            "requestAll": false,
            "latestSeason": false,
            "firstSeason": false
        ]
        let show: OmbiShow = try await send("api/v2/Search/tv/moviedb/\(draft.tmdbID)")
        let all = show.seasonRequests ?? []
        let picked: [OmbiSeason]
        switch draft.seasons {
        case let .numbers(numbers):
            picked = all.filter { numbers.contains($0.seasonNumber) }
        case .all, nil:
            picked = all.filter { $0.seasonNumber > 0 }
        }
        body["seasons"] = picked.compactMap { season -> [String: Any]? in
            let episodes = (season.episodes ?? []).filter { !$0.isTaken }.map { ["episodeNumber": $0.episodeNumber] }
            return episodes.isEmpty ? nil : ["seasonNumber": season.seasonNumber, "episodes": episodes]
        }
        return body
    }

    func approveRequest(id: Int, draft: SeerrRequestDraft) async throws {
        try await saveAdvancedOptions(requestID: id, draft: draft)
        switch draft.kind {
        case .movie:
            try Self.check(try await send("api/v1/Request/movie/approve", method: "POST", body: ["id": id, "is4K": draft.is4k]))
        case .tv:
            try Self.check(try await send("api/v1/Request/tv/approve", method: "POST", body: ["id": id]))
        }
    }

    func declineRequest(id: Int, kind: SeerrTitle.Kind) async throws {
        switch kind {
        case .movie:
            try Self.check(try await send("api/v1/Request/movie/deny", method: "PUT", body: ["id": id, "is4K": false, "reason": ""]))
        case .tv:
            try Self.check(try await send("api/v1/Request/tv/deny", method: "PUT", body: ["id": id, "reason": ""]))
        }
    }

    /// An admin's edit before approving: the quality and folder the request downloads with.
    private func saveAdvancedOptions(requestID: Int, draft: SeerrRequestDraft) async throws {
        guard draft.profileID != nil || draft.rootFolderID != nil || draft.languageProfileID != nil else { return }
        let target = draft.kind == .movie ? requestID : (draft.parentRequestID ?? requestID)
        let body: [String: Any] = [
            "requestId": target,
            "qualityOverride": draft.profileID ?? 0,
            "rootPathOverride": draft.rootFolderID ?? 0,
            "languageProfile": draft.languageProfileID ?? 0
        ]
        let kind = draft.kind == .movie ? "movie" : "tv"
        try Self.check(try await send("api/v2/Requests/\(kind)/advancedoptions", method: "POST", body: body))
    }

    /// A movie request's quality and folder, for an admin reviewing it. Shows keep theirs on the show's request.
    func requestDetails(id: Int) async throws -> SeerrStoredRequest {
        let request: OmbiMovieRequest = try await send("api/v1/Request/movie/info/\(id)")
        var folder: String?
        if let folderID = request.rootPathOverride, folderID > 0 {
            let folders: [OmbiRootFolder] = (try? await send("api/v1/Radarr/RootFolders")) ?? []
            folder = folders.first { $0.id == folderID }?.path
        }
        return SeerrStoredRequest(
            is4k: request.is4kRequest,
            serverId: 0,
            profileId: request.qualityOverride.flatMap { $0 > 0 ? $0 : nil },
            rootFolder: folder,
            languageProfileId: nil,
            seasons: nil
        )
    }

    /// Ombi has one Radarr (and one Sonarr), shown as a single server when it's set up.
    func radarrServers() async throws -> [SeerrServiceServer] {
        let profiles: [OmbiProfile] = try await send("api/v1/Radarr/Profiles")
        return profiles.isEmpty ? [] : [SeerrServiceServer(id: 0, name: "Radarr", isDefault: true)]
    }

    func sonarrServers() async throws -> [SeerrServiceServer] {
        let profiles: [OmbiProfile] = try await send("api/v1/Sonarr/Profiles")
        return profiles.isEmpty ? [] : [SeerrServiceServer(id: 0, name: "Sonarr", isDefault: true)]
    }

    func radarrDetails(id: Int) async throws -> SeerrServiceDetails {
        async let profiles: [OmbiProfile] = send("api/v1/Radarr/Profiles")
        async let folders: [OmbiRootFolder] = send("api/v1/Radarr/RootFolders")
        return SeerrServiceDetails(
            server: SeerrServiceServer(id: 0, name: "Radarr", isDefault: true),
            profiles: try await profiles.map(\.serviceProfile),
            rootFolders: try await folders.map(\.rootFolder)
        )
    }

    func sonarrDetails(id: Int) async throws -> SeerrServiceDetails {
        async let profiles: [OmbiProfile] = send("api/v1/Sonarr/Profiles")
        async let folders: [OmbiRootFolder] = send("api/v1/Sonarr/RootFolders")
        async let languages: [OmbiProfile]? = try? send("api/v1/Sonarr/v3/LanguageProfiles")
        return SeerrServiceDetails(
            server: SeerrServiceServer(id: 0, name: "Sonarr", isDefault: true),
            profiles: try await profiles.map(\.serviceProfile),
            rootFolders: try await folders.map(\.rootFolder),
            // Sonarr v4 has no language profiles and reports a placeholder called Deprecated.
            languageProfiles: await languages?.filter { $0.name != "Deprecated" }.map(\.serviceProfile)
        )
    }

    // MARK: Transport

    private func send<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL.appendingSlash) else { throw ZelefinError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        AccessGateway.apply(&request)
        if let session {
            request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await SeerrTransport.session.data(for: request)
        if let http = response as? HTTPURLResponse {
            if AccessGateway.isChallenge(response: http, data: data) { throw ZelefinError.accessGateway }
            if http.statusCode == 401 || http.statusCode == 403 { throw ZelefinError.seerrUnauthorized }
            guard (200 ..< 300).contains(http.statusCode) else {
                throw ZelefinError.server(Self.errorMessage(from: data, status: http.statusCode))
            }
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func check(_ result: OmbiRequestResult) throws {
        if let message = result.failure { throw ZelefinError.server(message) }
    }

    static func errorMessage(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["errorMessage", "message", "error", "title"] {
                if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return value
                }
            }
        }
        return "Ombi returned \(status)."
    }

    private static func pathComponent(_ term: String) -> String {
        term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))) ?? term
    }

    private static func interleave(_ first: [SeerrTitle], _ second: [SeerrTitle]) -> [SeerrTitle] {
        var result: [SeerrTitle] = []
        for index in 0 ..< max(first.count, second.count) {
            if index < first.count { result.append(first[index]) }
            if index < second.count { result.append(second[index]) }
        }
        return result
    }

    /// A show's full details carry no poster path, so the poster, year, and overview it came with are kept.
    private static func keepingPoster(of basic: SeerrTitle, in detailed: SeerrTitle) -> SeerrTitle {
        var copy = detailed
        copy.posterURL = detailed.posterURL ?? basic.posterURL
        copy.year = detailed.year ?? basic.year
        copy.overview = detailed.overview ?? basic.overview
        return copy
    }
}

// MARK: - Ombi payloads

private struct OmbiToken: Decodable {
    var accessToken: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

private struct OmbiUser: Decodable {
    struct Claim: Decodable {
        var value: String?
        var enabled: Bool?
    }

    var userName: String?
    var alias: String?
    var emailAddress: String?
    var claims: [Claim]?

    var label: String? {
        [alias, userName, emailAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// Admins and power users approve and decline requests.
    var canManageRequests: Bool {
        (claims ?? []).contains { claim in
            claim.enabled == true && (claim.value == "Admin" || claim.value == "PowerUser")
        }
    }
}

private struct OmbiMultiResult: Decodable {
    var id: String?
    var mediaType: String?
    var title: String?
    var poster: String?
    var overview: String?

    /// Ombi names search results "Dune (2021)".
    static func splitYear(_ raw: String) -> (String, Int?) {
        guard raw.hasSuffix(")"), let open = raw.lastIndex(of: "(") else { return (raw, nil) }
        let inside = raw[raw.index(after: open) ..< raw.index(before: raw.endIndex)]
        guard inside.count == 4, let year = Int(inside) else { return (raw, nil) }
        return (raw[..<open].trimmingCharacters(in: .whitespaces), year)
    }

    var seerrTitle: SeerrTitle? {
        guard let id, let tmdbID = Int(id), let raw = title, !raw.isEmpty else { return nil }
        let (name, year) = Self.splitYear(raw)
        let kind: SeerrTitle.Kind
        switch mediaType {
        case "movie": kind = .movie
        case "tv": kind = .tv
        default: return nil
        }
        return SeerrTitle(
            tmdbID: tmdbID,
            kind: kind,
            name: name,
            year: year,
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(poster),
            availability: .missing
        )
    }
}

/// The request and library state Ombi puts on every movie and show it returns.
private protocol OmbiRequestState {
    var available: Bool? { get }
    var partlyAvailable: Bool? { get }
    var requested: Bool? { get }
    var approved: Bool? { get }
    var denied: Bool? { get }
    var requestId: Int? { get }
}

private extension OmbiRequestState {
    /// A partly downloaded show is `available` and `partlyAvailable` at once, so the partial check comes first.
    var availability: SeerrTitle.Availability {
        if partlyAvailable == true { return .partial }
        if available == true { return .available }
        if denied == true { return .missing }
        if requested == true { return approved == true ? .processing : .pending }
        return .missing
    }

    var review: SeerrTitle.Review? {
        guard requested == true, available != true else { return nil }
        if denied == true { return .declined }
        return approved == true ? .approved : .pendingApproval
    }

    func applyState(to title: inout SeerrTitle) {
        title.availability = availability
        title.review = review
        if let requestId, requestId > 0 {
            title.requestID = requestId
        }
    }
}

private struct OmbiMovie: Decodable, OmbiRequestState {
    var id: Int?
    var theMovieDbId: String?
    var title: String?
    var overview: String?
    var posterPath: String?
    var releaseDate: String?
    var available: Bool?
    var requested: Bool?
    var approved: Bool?
    var denied: Bool?
    var requestId: Int?
    var partlyAvailable: Bool? { nil }

    private enum CodingKeys: String, CodingKey {
        case id, theMovieDbId, title, overview, posterPath, releaseDate, available, requested, approved, denied, requestId
    }

    var seerrTitle: SeerrTitle? {
        guard let tmdbID = theMovieDbId.flatMap(Int.init) ?? id, let name = title, !name.isEmpty else { return nil }
        var result = SeerrTitle(
            tmdbID: tmdbID,
            kind: .movie,
            name: name,
            year: releaseDate.flatMap { Int($0.prefix(4)) },
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(posterPath),
            availability: .missing
        )
        applyState(to: &result)
        return result
    }
}

private struct OmbiEpisode: Decodable {
    var episodeNumber: Int
    var available: Bool?
    var requested: Bool?
    var approved: Bool?

    var isTaken: Bool { available == true || requested == true || approved == true }
}

private struct OmbiSeason: Decodable {
    var seasonNumber: Int
    var episodes: [OmbiEpisode]?

    /// Every episode is on the server or already requested.
    var isTaken: Bool {
        guard let episodes, !episodes.isEmpty else { return false }
        return episodes.allSatisfy(\.isTaken)
    }
}

private struct OmbiShow: Decodable, OmbiRequestState {
    var id: Int?
    var theMovieDbId: String?
    var title: String?
    var overview: String?
    var posterPath: String?
    var firstAired: String?
    var available: Bool?
    var partlyAvailable: Bool?
    var requested: Bool?
    var approved: Bool?
    var denied: Bool?
    var requestId: Int?
    var seasonRequests: [OmbiSeason]?

    var seerrTitle: SeerrTitle? {
        guard let tmdbID = theMovieDbId.flatMap(Int.init) ?? id, let name = title, !name.isEmpty else { return nil }
        var result = SeerrTitle(
            tmdbID: tmdbID,
            kind: .tv,
            name: name,
            year: firstAired.flatMap { Int($0.prefix(4)) },
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(posterPath),
            availability: .missing
        )
        applyState(to: &result)
        return result
    }
}

private struct OmbiRequestPage<Request: Decodable>: Decodable {
    var collection: [Request]?
}

private struct OmbiRequester: Decodable {
    var userName: String?
    var alias: String?

    var label: String? {
        [alias, userName].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }
}

/// A request's review state: approved, declined, or waiting.
private struct OmbiReview {
    var approved: Bool?
    var available: Bool?
    var denied: Bool?

    func apply(to title: inout SeerrTitle, requestID: Int, requester: OmbiRequester?) {
        title.requestID = requestID
        title.requestedByName = requester?.label
        if available == true {
            title.availability = .available
            title.review = nil
        } else if denied == true {
            title.availability = .missing
            title.review = .declined
        } else if approved == true {
            title.availability = .processing
            title.review = .approved
        } else {
            title.availability = .pending
            title.review = .pendingApproval
        }
    }
}

private struct OmbiProfile: Decodable {
    var id: Int
    var name: String?

    var serviceProfile: SeerrServiceProfile {
        SeerrServiceProfile(id: id, name: name ?? "Profile \(id)")
    }
}

private struct OmbiRootFolder: Decodable {
    var id: Int
    var path: String
    var freeSpace: Double?

    var rootFolder: SeerrRootFolder {
        SeerrRootFolder(folderID: id, path: path, freeSpace: freeSpace)
    }
}

private struct OmbiShowRequest: Decodable {
    var id: Int
    var childRequests: [OmbiChildRequest]?
}

private struct OmbiMovieRequest: Decodable {
    var id: Int
    var theMovieDbId: Int?
    var qualityOverride: Int?
    var rootPathOverride: Int?
    var is4kRequest: Bool?
    var title: String?
    var overview: String?
    var posterPath: String?
    var releaseDate: String?
    var requestedDate: String?
    var approved: Bool?
    var available: Bool?
    var denied: Bool?
    var requestedUser: OmbiRequester?

    var seerrTitle: SeerrTitle? {
        guard let tmdbID = theMovieDbId, let name = title, !name.isEmpty else { return nil }
        var result = SeerrTitle(
            tmdbID: tmdbID,
            kind: .movie,
            name: name,
            year: releaseDate.flatMap { Int($0.prefix(4)) },
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(posterPath),
            availability: .pending
        )
        OmbiReview(approved: approved, available: available, denied: denied).apply(to: &result, requestID: id, requester: requestedUser)
        return result
    }
}

private struct OmbiChildRequest: Decodable {
    struct Parent: Decodable {
        var externalProviderId: Int?
        var title: String?
        var overview: String?
        var posterPath: String?
        var releaseDate: String?
    }

    var id: Int
    var parentRequestId: Int?
    var requestedDate: String?
    var approved: Bool?
    var available: Bool?
    var denied: Bool?
    var requestedUser: OmbiRequester?
    var parentRequest: Parent?

    var seerrTitle: SeerrTitle? {
        guard let parent = parentRequest, let tmdbID = parent.externalProviderId, let name = parent.title, !name.isEmpty else { return nil }
        var result = SeerrTitle(
            tmdbID: tmdbID,
            kind: .tv,
            name: name,
            year: parent.releaseDate.flatMap { Int($0.prefix(4)) },
            overview: parent.overview,
            posterURL: SeerrClient.tmdbImageURL(parent.posterPath),
            availability: .pending
        )
        OmbiReview(approved: approved, available: available, denied: denied).apply(to: &result, requestID: id, requester: requestedUser)
        result.parentRequestID = parentRequestId
        return result
    }
}

private struct OmbiRequestResult: Decodable {
    var result: Bool?
    var message: String?
    var isError: Bool?
    var errorMessage: String?

    var failure: String? {
        guard isError == true || result == false else { return nil }
        let text = [errorMessage, message].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return text ?? "Ombi didn't take the request."
    }
}

private extension URL {
    /// `URL(string:relativeTo:)` drops the base's last path component unless it ends in a slash.
    var appendingSlash: URL {
        absoluteString.hasSuffix("/") ? self : URL(string: absoluteString + "/") ?? self
    }
}
