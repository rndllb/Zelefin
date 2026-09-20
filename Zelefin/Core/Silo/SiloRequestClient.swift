import Foundation

enum SiloRequestSource: String, CaseIterable, Identifiable, Sendable {
    case seerr
    case arr

    var id: String { rawValue }

    var title: String {
        switch self {
        case .seerr: "Seerr"
        case .arr: "Sonarr & Radarr"
        }
    }

    static func matches(_ pluginID: String, source: SiloRequestSource) -> Bool {
        let compact = pluginID.lowercased().filter { $0.isLetter || $0.isNumber }
        switch source {
        case .seerr:
            return compact.contains("seerr") || compact.contains("jellyseerr") || compact.contains("overseerr")
        case .arr:
            return compact.contains("silo.request.arr")
                || compact.contains("silorequestsarr")
                || (compact.contains("request") && compact.contains("arr"))
        }
    }

    static func resolved(preferred: SiloRequestSource, seerr: Bool, arr: Bool) -> SiloRequestSource? {
        switch preferred {
        case .seerr:
            if seerr { return .seerr }
            if arr { return .arr }
            return nil
        case .arr:
            if arr { return .arr }
            if seerr { return .seerr }
            return nil
        }
    }

    static func discoverAvailable(
        requestsEnabled: Bool,
        seerr: Bool,
        arr: Bool,
        preferred: SiloRequestSource
    ) -> Bool {
        guard requestsEnabled else { return false }
        if !seerr, !arr { return true }
        return resolved(preferred: preferred, seerr: seerr, arr: arr) != nil
    }
}

enum SiloSubtitleProviders {
    static let known = ["opensubtitles", "subdl", "subsource"]

    /// Subtitle search is a first-party Silo capability, not a plugin.
    /// The v2 capability wrapper sets `allowed: false` for `not_configured`
    /// and `disabled` even when the search routes still exist.
    static func isAvailable(status: SiloSubtitleProviderStatus?) -> Bool {
        guard let status else { return true }
        let state = (status.state ?? "").lowercased()
        if state == "unsupported" { return false }
        if status.allowed == false, state == "available" { return false }
        return true
    }

    static func listed(from status: SiloSubtitleProviderStatus?) -> [String] {
        let names = normalized(status?.names ?? [])
        if !names.isEmpty { return names }
        return isAvailable(status: status) ? known : []
    }

    static func normalized(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let id = canonical(name)
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            out.append(id)
        }
        return out.sorted { order($0) < order($1) }
    }

    static func canonical(_ raw: String) -> String {
        let compact = raw.lowercased().filter(\.isLetter)
        if compact.contains("opensubtitle") { return "opensubtitles" }
        if compact == "subdl" { return "subdl" }
        if compact.contains("subsource") { return "subsource" }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func displayName(_ raw: String) -> String {
        switch canonical(raw) {
        case "opensubtitles":
            return "OpenSubtitles"
        case "subdl":
            return "SubDL"
        case "subsource":
            return "Subsource"
        default:
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Subtitles" : trimmed
        }
    }

    static func order(_ raw: String?) -> Int {
        let id = canonical(raw ?? "")
        return known.firstIndex(of: id) ?? known.count
    }

    static func searchErrorMessage(_ error: SiloHTTPError) -> String {
        let haystack = "\(error.code ?? "") \(error.message)".lowercased()
        if error.statusCode == 409 || haystack.contains("capability") {
            return "Subtitles are not configured on this Silo server."
        }
        if error.statusCode == 401 || error.statusCode == 403 {
            return "This profile cannot search subtitles on this Silo server."
        }
        if error.shouldUseLegacySubtitles {
            return "Subtitles could not be reached on this Silo server."
        }
        return error.message
    }
}

typealias SiloOpenSubtitles = SiloSubtitleProviders

struct SiloPluginInstallation: Decodable, Sendable {
    var id: String
    var pluginID: String
    var version: String?
    var enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case pluginID = "plugin_id"
        case version
        case enabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        pluginID = container.decodeFlexibleString(.pluginID) ?? ""
        version = container.decodeFlexibleString(.version)
        enabled = container.decodeFlexibleBool(.enabled)
    }

    var isEnabled: Bool { enabled ?? true }
}

struct SiloRequestFeatureStatus: Decodable, Sendable {
    var requestsEnabled: Bool?
    var allowed: Bool?

    enum CodingKeys: String, CodingKey {
        case requestsEnabled = "requests_enabled"
        case allowed
        case capability
    }

    private struct Capability: Decodable {
        var allowed: Bool?
        var state: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestsEnabled = container.decodeFlexibleBool(.requestsEnabled)
        allowed = container.decodeFlexibleBool(.allowed)
        if allowed == nil, let capability = try? container.decode(Capability.self, forKey: .capability) {
            allowed = capability.allowed
        }
    }

    var isEnabled: Bool { requestsEnabled == true }
}

struct SiloSubtitleProviderStatus: Decodable, Sendable {
    var enabled: Bool?
    var allowed: Bool?
    var providers: [String]?
    var state: String?

    var isEnabled: Bool { enabled != false }
    var names: [String] { providers ?? [] }
}

struct SiloRequestMediaResult: Decodable, Sendable {
    var mediaType: String?
    var tmdbID: Int?
    var title: String?
    var year: Int?
    var overview: String?
    var posterPath: String?
    var availability: String?
    var request: SiloRequestMediaState?

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case tmdbID = "tmdb_id"
        case title, year, overview, availability, request
        case posterPath = "poster_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = container.decodeFlexibleString(.mediaType)
        tmdbID = container.decodeFlexibleInt(.tmdbID)
        title = container.decodeFlexibleString(.title)
        year = container.decodeFlexibleInt(.year)
        overview = container.decodeFlexibleString(.overview)
        posterPath = container.decodeFlexibleString(.posterPath)
        availability = container.decodeFlexibleString(.availability)
        request = try? container.decode(SiloRequestMediaState.self, forKey: .request)
    }

    func asTitle() -> SeerrTitle? {
        guard let tmdbID, tmdbID > 0 else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return SeerrTitle(
            tmdbID: tmdbID,
            kind: SeerrTitle.Kind(siloMediaType: mediaType),
            name: name,
            year: year,
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(posterPath),
            availability: SeerrTitle.Availability(siloAvailability: availability, request: request)
        )
    }
}

struct SiloRequestMediaState: Decodable, Sendable {
    var status: String?
    var requestable: Bool?
    var requestID: String?

    enum CodingKeys: String, CodingKey {
        case status, requestable
        case requestID = "request_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = container.decodeFlexibleString(.status)
        requestable = container.decodeFlexibleBool(.requestable)
        requestID = container.decodeFlexibleString(.requestID)
    }
}

struct SiloDiscoverSection: Decodable, Sendable {
    var key: String?
    var title: String?
    var page: Int?
    var totalPages: Int?
    var results: [SiloRequestMediaResult]?

    enum CodingKeys: String, CodingKey {
        case key, title, page, results
        case totalPages = "total_pages"
    }

    var titles: [SeerrTitle] {
        (results ?? []).compactMap { $0.asTitle() }
    }
}

struct SiloDiscoverSectionsResponse: Decodable, Sendable {
    var items: [SiloDiscoverSection]?
    var entries: [SiloDiscoverSection]?
    var sections: [SiloDiscoverSection]?

    var rows: [SiloDiscoverSection] { items ?? entries ?? sections ?? [] }
}

struct SiloRequestMediaPage: Decodable, Sendable {
    var page: Int?
    var totalPages: Int?
    var results: [SiloRequestMediaResult]?

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
    }

    var titles: [SeerrTitle] {
        (results ?? []).compactMap { $0.asTitle() }
    }
}

struct SiloDiscoverBrand: Decodable, Sendable {
    var tmdbID: Int?
    var slug: String?
    var displayName: String?
    var logoURL: String?
    var seriesSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case slug
        case tmdbID = "tmdb_id"
        case displayName = "display_name"
        case logoURL = "logo_url"
        case seriesSupported = "series_supported"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tmdbID = container.decodeFlexibleInt(.tmdbID)
        slug = container.decodeFlexibleString(.slug)
        displayName = container.decodeFlexibleString(.displayName)
        logoURL = container.decodeFlexibleString(.logoURL)
        seriesSupported = container.decodeFlexibleBool(.seriesSupported)
    }
}

struct SiloDiscoverBrowsePage: Decodable, Sendable {
    var page: Int?
    var totalPages: Int?
    var results: [SiloRequestMediaResult]?
    var displayName: String?

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case displayName = "display_name"
    }
}

struct SiloMediaRequest: Decodable, Sendable {
    var id: String?
    var mediaType: String?
    var tmdbID: Int?
    var title: String?
    var year: Int?
    var overview: String?
    var posterPath: String?
    var status: String?

    enum CodingKeys: String, CodingKey {
        case id, title, year, overview, status
        case mediaType = "media_type"
        case tmdbID = "tmdb_id"
        case posterPath = "poster_path"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        mediaType = container.decodeFlexibleString(.mediaType)
        tmdbID = container.decodeFlexibleInt(.tmdbID)
        title = container.decodeFlexibleString(.title)
        year = container.decodeFlexibleInt(.year)
        overview = container.decodeFlexibleString(.overview)
        posterPath = container.decodeFlexibleString(.posterPath)
        status = container.decodeFlexibleString(.status)
    }

    func asTitle() -> SeerrTitle? {
        guard let tmdbID, tmdbID > 0 else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        var title = SeerrTitle(
            tmdbID: tmdbID,
            kind: SeerrTitle.Kind(siloMediaType: mediaType),
            name: name,
            year: year,
            overview: overview,
            posterURL: SeerrClient.tmdbImageURL(posterPath),
            availability: SeerrTitle.Availability(siloRequestStatus: status)
        )
        if let id, let parsed = Int(id) {
            title.requestID = parsed
        }
        return title
    }

    func asAlert() -> LibraryAlertRequest? {
        let identifier = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !identifier.isEmpty else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return LibraryAlertRequest(
            id: identifier,
            title: name.isEmpty ? "a title" : name,
            requester: "A profile"
        )
    }
}

struct SiloRequestCreate: Encodable, Sendable {
    var mediaType: String
    var tmdbID: Int
    var title: String
    var year: Int?
    var overview: String?
    var posterPath: String?
}

struct SiloSubtitleSearchBody: Encodable, Sendable {
    var mediaFileID: String
    var languages: [String]
}

struct SiloSubtitleSearchResult: Decodable, Sendable {
    var id: String?
    var provider: String?
    var language: String?
    var releaseName: String?
    var format: String?
    var score: Double?
    var downloads: Int?
    var hearingImpaired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, provider, language, format, score, downloads
        case releaseName = "release_name"
        case hearingImpaired = "hearing_impaired"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        provider = container.decodeFlexibleString(.provider)
        language = container.decodeFlexibleString(.language)
        releaseName = container.decodeFlexibleString(.releaseName)
        format = container.decodeFlexibleString(.format)
        score = try? container.decode(Double.self, forKey: .score)
        downloads = container.decodeFlexibleInt(.downloads)
        hearingImpaired = container.decodeFlexibleBool(.hearingImpaired)
    }

    func asMatch(mediaFileID: String) -> RemoteSubtitleMatch? {
        let subtitleID = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !subtitleID.isEmpty else { return nil }
        let release = releaseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var parts: [String] = []
        if let provider, !provider.isEmpty { parts.append(SiloSubtitleProviders.displayName(provider)) }
        if let format, !format.isEmpty { parts.append(format.uppercased()) }
        if hearingImpaired == true { parts.append("SDH") }
        if let downloads, downloads > 0 { parts.append("\(downloads.formatted()) downloads") }
        return RemoteSubtitleMatch(
            id: "\(mediaFileID):\(provider ?? "opensubtitles"):\(subtitleID)",
            title: release.isEmpty ? "Subtitle" : release,
            detail: parts.joined(separator: " · "),
            isHashMatch: false,
            silo: SiloSubtitleDownloadKeys(
                mediaFileID: mediaFileID,
                provider: provider ?? "opensubtitles",
                subtitleID: subtitleID,
                language: language ?? "en",
                releaseName: release,
                format: format ?? "srt",
                score: score ?? 0,
                hearingImpaired: hearingImpaired == true
            )
        )
    }
}

struct SiloSubtitleSearchResults: Decodable, Sendable {
    var results: [SiloSubtitleSearchResult]?
    var warnings: [String]?

    enum CodingKeys: String, CodingKey { case results, warnings }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        results = container.decodeLossyArray(.results)
        warnings = try? container.decode([String].self, forKey: .warnings)
    }

    func matches(mediaFileID: String) -> [RemoteSubtitleMatch] {
        (results ?? []).compactMap { $0.asMatch(mediaFileID: mediaFileID) }
            .sorted { SiloSubtitleProviders.order($0.silo?.provider) < SiloSubtitleProviders.order($1.silo?.provider) }
    }
}

struct SiloSubtitleSearchBodyV1: Encodable, Sendable {
    var mediaFileID: Int
    var languages: [String]
}

struct SiloStoredSubtitles: Decodable, Sendable {
    var subtitles: [SiloStoredSubtitle]?

    enum CodingKeys: String, CodingKey { case subtitles }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subtitles = container.decodeLossyArray(.subtitles)
    }
}

struct SiloStoredSubtitle: Decodable, Sendable {
    var id: String?
    var language: String?
    var format: String?
    var releaseName: String?
    var provider: String?
    var hearingImpaired: Bool?

    enum CodingKeys: String, CodingKey {
        case id, language, format, provider
        case releaseName = "release_name"
        case hearingImpaired = "hearing_impaired"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        language = container.decodeFlexibleString(.language)
        format = container.decodeFlexibleString(.format)
        releaseName = container.decodeFlexibleString(.releaseName)
        provider = container.decodeFlexibleString(.provider)
        hearingImpaired = container.decodeFlexibleBool(.hearingImpaired)
    }

    func asTrack(index: Int) -> MediaTrack {
        let release = releaseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = release.isEmpty
            ? (language.flatMap { Locale.current.localizedString(forLanguageCode: $0) } ?? "Subtitle \(index + 1)")
            : release
        return MediaTrack(
            id: SiloFileID.parse(id ?? "") ?? index,
            kind: .subtitle,
            language: language,
            title: title,
            codec: format,
            isSelected: false,
            isDefault: false
        )
    }
}

struct SiloSubtitleDownloadBodyV1: Encodable, Sendable {
    var mediaFileID: Int
    var provider: String
    var subtitleID: String
    var language: String
    var releaseName: String
    var format: String
    var score: Double
    var hearingImpaired: Bool
}

struct SiloSubtitleDownloadBody: Encodable, Sendable {
    var mediaFileID: String
    var provider: String
    var subtitleID: String
    var language: String
    var releaseName: String
    var score: Double
    var hearingImpaired: Bool
}

struct SiloSubtitleDownloadKeys: Hashable, Sendable {
    var mediaFileID: String
    var provider: String
    var subtitleID: String
    var language: String
    var releaseName: String
    var format: String
    var score: Double
    var hearingImpaired: Bool
}

struct SiloRequestClient: Sendable {
    let api: SiloAPIClient

    func search(term: String) async throws -> [SeerrTitle] {
        let page: SiloRequestMediaPage = try await api.get(
            "/api/v2/requests/search",
            query: ["q": term, "page": "1"]
        )
        return page.titles
    }

    func discoverHome() async -> SeerrDiscoverHome {
        async let sections = (try? await api.siloDiscoverSections()) ?? []
        async let mine = (try? await api.siloMyRequests()) ?? []
        async let genres = (try? await api.siloDiscoverBrands(path: "genres")) ?? []
        async let studios = (try? await api.siloDiscoverBrands(path: "studios")) ?? []
        async let networks = (try? await api.siloDiscoverBrands(path: "networks")) ?? []
        let rows = await sections
        func titles(for key: String) -> [SeerrTitle] {
            rows.first(where: { $0.key == key })?.titles ?? []
        }
        return SeerrDiscoverHome(
            recentRequests: await mine.compactMap { $0.asTitle() },
            trending: titles(for: "trending_movies") + titles(for: "trending_series"),
            popularMovies: titles(for: "popular_movies"),
            upcomingMovies: titles(for: "upcoming_movies"),
            popularTV: titles(for: "popular_series"),
            upcomingTV: titles(for: "on_air_series"),
            movieGenres: await genres.map { $0.genreItem(mediaType: "movie") },
            tvGenres: await genres.filter { $0.seriesSupported != false }.map { $0.genreItem(mediaType: "series") },
            studios: await studios.compactMap { $0.company(kind: .studio) },
            networks: await networks.compactMap { $0.company(kind: .network) }
        )
    }

    func discover(_ query: SeerrDiscoverQuery, page: Int) async throws -> SeerrDiscoverPage {
        switch query {
        case .requests:
            let requests = try await api.siloMyRequests()
            return SeerrDiscoverPage(titles: requests.compactMap { $0.asTitle() }, page: 1, totalPages: 1)
        case let .siloGenre(slug, _, mediaType):
            let payload: SiloDiscoverBrowsePage = try await api.get(
                "/api/v2/requests/discover/browse/genre/\(SiloAPIClient.path(slug))",
                query: ["media_type": mediaType, "page": "\(page)"]
            )
            return SeerrDiscoverPage(
                titles: (payload.results ?? []).compactMap { $0.asTitle() },
                page: payload.page ?? page,
                totalPages: max(payload.totalPages ?? page, 1)
            )
        case let .siloStudio(slug, _):
            return try await browse("studio", slug: slug, page: page)
        case let .siloNetwork(slug, _):
            return try await browse("network", slug: slug, page: page)
        default:
            guard let section = query.siloSection else {
                throw ZelefinError.server("That discovery row is not on this Silo server.")
            }
            let payload: SiloDiscoverSection = try await api.get(
                "/api/v2/requests/discover/\(section)",
                query: ["page": "\(page)"]
            )
            return SeerrDiscoverPage(
                titles: payload.titles,
                page: payload.page ?? page,
                totalPages: max(payload.totalPages ?? page, 1)
            )
        }
    }

    func request(_ title: SeerrTitle) async throws {
        let body = SiloRequestCreate(
            mediaType: title.kind == .tv ? "series" : "movie",
            tmdbID: title.tmdbID,
            title: title.name,
            year: title.year,
            overview: title.overview,
            posterPath: title.posterURL.flatMap(Self.tmdbPath(from:))
        )
        let _: SiloMediaRequest = try await api.post("/api/v2/requests", body: body)
    }

    func listedAlerts() async throws -> [LibraryAlertRequest] {
        do {
            return try await api.siloAdminRequests().compactMap { $0.asAlert() }
        } catch {
            return try await api.siloMyRequests().compactMap { $0.asAlert() }
        }
    }

    private func browse(_ kind: String, slug: String, page: Int) async throws -> SeerrDiscoverPage {
        let payload: SiloDiscoverBrowsePage = try await api.get(
            "/api/v2/requests/discover/browse/\(kind)/\(SiloAPIClient.path(slug))",
            query: ["page": "\(page)"]
        )
        return SeerrDiscoverPage(
            titles: (payload.results ?? []).compactMap { $0.asTitle() },
            page: payload.page ?? page,
            totalPages: max(payload.totalPages ?? page, 1)
        )
    }

    private static func tmdbPath(from url: URL) -> String? {
        let path = url.path
        guard let range = path.range(of: "/t/p/") else { return nil }
        let rest = path[range.upperBound...]
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        return String(rest[slash...])
    }
}

extension SiloAPIClient {
    fileprivate static let subtitleProviderTimeout: TimeInterval = 90

    func siloPluginSettings() async throws -> [SiloPluginInstallation] {
        let envelope: SiloPageCollection<SiloPluginInstallation> = try await get("/api/v2/settings/plugins")
        return envelope.entries.filter { !$0.pluginID.isEmpty }
    }

    func siloAdminPluginInstallations() async throws -> [SiloPluginInstallation] {
        let envelope: SiloPageCollection<SiloPluginInstallation> = try await get(
            "/api/v2/admin/plugins/installations",
            query: ["limit": "100"]
        )
        return envelope.entries.filter { !$0.pluginID.isEmpty }
    }

    func siloRequestStatus() async throws -> SiloRequestFeatureStatus {
        try await get("/api/v2/requests/status")
    }

    func siloSubtitleProviderStatus() async throws -> SiloSubtitleProviderStatus {
        do {
            return try await get("/api/v2/subtitles/providers/status")
        } catch let error as SiloHTTPError where error.shouldUseLegacySubtitles {
            return try await get("/api/v1/subtitles/providers/status")
        }
    }

    func siloDiscoverSections() async throws -> [SiloDiscoverSection] {
        let envelope: SiloDiscoverSectionsResponse = try await get("/api/v2/requests/discover")
        return envelope.rows
    }

    func siloDiscoverBrands(path: String) async throws -> [SiloDiscoverBrand] {
        let envelope: SiloPageCollection<SiloDiscoverBrand> = try await get("/api/v2/requests/discover/\(path)")
        return envelope.entries
    }

    func siloMyRequests() async throws -> [SiloMediaRequest] {
        let envelope: SiloPageCollection<SiloMediaRequest> = try await get(
            "/api/v2/requests/mine",
            query: ["limit": "50"]
        )
        return envelope.entries
    }

    func siloAdminRequests() async throws -> [SiloMediaRequest] {
        let envelope: SiloPageCollection<SiloMediaRequest> = try await get(
            "/api/v2/admin/requests",
            query: ["limit": "50"]
        )
        return envelope.entries
    }

    func searchSubtitles(mediaFileID: Int, language: String) async throws -> [RemoteSubtitleMatch] {
        let file = String(mediaFileID)
        let languages = [language]
        do {
            let payload: SiloSubtitleSearchResults = try await post(
                "/api/v1/subtitles/search",
                body: SiloSubtitleSearchBodyV1(mediaFileID: mediaFileID, languages: languages),
                timeout: Self.subtitleProviderTimeout
            )
            return payload.matches(mediaFileID: file)
        } catch let error as SiloHTTPError where error.isMissing {
            do {
                let payload: SiloSubtitleSearchResults = try await post(
                    "/api/v2/subtitles/search",
                    body: SiloSubtitleSearchBody(mediaFileID: file, languages: languages),
                    timeout: Self.subtitleProviderTimeout
                )
                return payload.matches(mediaFileID: file)
            } catch let error as SiloHTTPError {
                throw ZelefinError.server(SiloSubtitleProviders.searchErrorMessage(error))
            }
        } catch let error as SiloHTTPError {
            throw ZelefinError.server(SiloSubtitleProviders.searchErrorMessage(error))
        } catch let error as URLError where error.code == .timedOut {
            throw ZelefinError.server("Subtitle search took too long. Try again.")
        }
    }

    func downloadSubtitle(_ keys: SiloSubtitleDownloadKeys) async throws {
        guard let fileID = SiloFileID.parse(keys.mediaFileID) else {
            throw ZelefinError.server("This title has no playable file on the Silo server.")
        }
        let legacy = SiloSubtitleDownloadBodyV1(
            mediaFileID: fileID,
            provider: keys.provider,
            subtitleID: keys.subtitleID,
            language: keys.language,
            releaseName: keys.releaseName,
            format: keys.format,
            score: keys.score,
            hearingImpaired: keys.hearingImpaired
        )
        do {
            _ = try await postData(
                "/api/v1/subtitles/download",
                body: legacy,
                timeout: Self.subtitleProviderTimeout
            )
        } catch let error as SiloHTTPError where error.isMissing {
            do {
                _ = try await postData(
                    "/api/v2/subtitles/download",
                    body: SiloSubtitleDownloadBody(
                        mediaFileID: keys.mediaFileID,
                        provider: keys.provider,
                        subtitleID: keys.subtitleID,
                        language: keys.language,
                        releaseName: keys.releaseName,
                        score: keys.score,
                        hearingImpaired: keys.hearingImpaired
                    ),
                    timeout: Self.subtitleProviderTimeout
                )
            } catch let error as SiloHTTPError {
                throw ZelefinError.server(SiloSubtitleProviders.searchErrorMessage(error))
            }
        } catch let error as SiloHTTPError {
            throw ZelefinError.server(SiloSubtitleProviders.searchErrorMessage(error))
        } catch let error as URLError where error.code == .timedOut {
            throw ZelefinError.server("Subtitle download took too long. Try again.")
        }
    }

    func listStoredSubtitles(mediaFileID: Int) async throws -> [MediaTrack] {
        let payload: SiloStoredSubtitles
        do {
            payload = try await get("/api/v2/subtitles/\(mediaFileID)")
        } catch let error as SiloHTTPError where error.shouldUseLegacySubtitles {
            payload = try await get("/api/v1/subtitles/\(mediaFileID)")
        }
        return (payload.subtitles ?? []).enumerated().map { $0.element.asTrack(index: $0.offset) }
    }
}

extension SeerrTitle.Kind {
    init(siloMediaType: String?) {
        switch siloMediaType?.lowercased() {
        case "tv", "series", "show": self = .tv
        default: self = .movie
        }
    }
}

extension SeerrTitle.Availability {
    init(siloAvailability: String?, request: SiloRequestMediaState?) {
        if siloAvailability?.lowercased() == "available" {
            self = .available
            return
        }
        self = .init(siloRequestStatus: request?.status, requestable: request?.requestable)
    }

    init(siloRequestStatus: String?, requestable: Bool? = nil) {
        switch siloRequestStatus?.lowercased() {
        case "pending", "approved":
            self = .pending
        case "queued", "downloading":
            self = .processing
        case "completed":
            self = .available
        default:
            self = requestable == false ? .pending : .missing
        }
    }
}

private extension SiloDiscoverBrand {
    func genreItem(mediaType: String) -> SeerrGenreSliderItem {
        SeerrGenreSliderItem(
            id: tmdbID ?? abs(slug?.hashValue ?? 0),
            name: displayName ?? slug ?? "Genre",
            backdrops: nil,
            siloSlug: slug,
            siloMediaType: mediaType
        )
    }

    func company(kind: SeerrCompany.Kind) -> SeerrCompany? {
        let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let slug, !name.isEmpty else { return nil }
        return SeerrCompany(
            id: tmdbID ?? abs(slug.hashValue),
            name: name,
            kind: kind,
            imageURL: logoURL.flatMap(URL.init(string:)),
            siloSlug: slug
        )
    }
}
