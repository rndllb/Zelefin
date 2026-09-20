import Foundation

enum SeerrDiscoverQuery: Hashable, Sendable {
    case requests
    case trending
    case popularMovies
    case upcomingMovies
    case popularTV
    case upcomingTV
    case movieGenre(id: Int, name: String)
    case tvGenre(id: Int, name: String)
    case studio(id: Int, name: String)
    case network(id: Int, name: String)
    case siloGenre(slug: String, name: String, mediaType: String)
    case siloStudio(slug: String, name: String)
    case siloNetwork(slug: String, name: String)

    var title: String {
        switch self {
        case .requests: "Recent Requests"
        case .trending: "Trending"
        case .popularMovies: "Popular Movies"
        case .upcomingMovies: "Upcoming Movies"
        case .popularTV: "Popular TV"
        case .upcomingTV: "Upcoming TV"
        case let .movieGenre(_, name): name
        case let .tvGenre(_, name): name
        case let .studio(_, name): name
        case let .network(_, name): name
        case let .siloGenre(_, name, _): name
        case let .siloStudio(_, name): name
        case let .siloNetwork(_, name): name
        }
    }

    var siloSection: String? {
        switch self {
        case .trending: "trending_movies"
        case .popularMovies: "popular_movies"
        case .upcomingMovies: "upcoming_movies"
        case .popularTV: "popular_series"
        case .upcomingTV: "on_air_series"
        default: nil
        }
    }

    var path: String {
        switch self {
        case .requests: "api/v1/request"
        case .trending: "api/v1/discover/trending"
        case .popularMovies: "api/v1/discover/movies"
        case .upcomingMovies: "api/v1/discover/movies/upcoming"
        case .popularTV: "api/v1/discover/tv"
        case .upcomingTV: "api/v1/discover/tv/upcoming"
        case let .movieGenre(id, _): "api/v1/discover/movies/genre/\(id)"
        case let .tvGenre(id, _): "api/v1/discover/tv/genre/\(id)"
        case let .studio(id, _): "api/v1/discover/movies/studio/\(id)"
        case let .network(id, _): "api/v1/discover/tv/network/\(id)"
        case .siloGenre, .siloStudio, .siloNetwork: ""
        }
    }

    func queryItems(page: Int) -> [URLQueryItem] {
        switch self {
        case .requests:
            [
                URLQueryItem(name: "filter", value: "all"),
                URLQueryItem(name: "take", value: "20"),
                URLQueryItem(name: "skip", value: "\((page - 1) * 20)"),
                URLQueryItem(name: "sort", value: "modified")
            ]
        default:
            [
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "language", value: "en")
            ]
        }
    }
}

struct SeerrDiscoverPage: Sendable {
    var titles: [SeerrTitle]
    var page: Int
    var totalPages: Int
}

struct SeerrGenreSliderItem: Decodable, Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var backdrops: [String]?
    var siloSlug: String? = nil
    var siloMediaType: String? = nil

    var imageURL: URL? {
        SeerrClient.tmdbImageURL(backdrops?.first, size: "w780")
    }

    var discoverQuery: SeerrDiscoverQuery {
        if let siloSlug {
            return .siloGenre(slug: siloSlug, name: name, mediaType: siloMediaType ?? "movie")
        }
        return siloMediaType == "series" || siloMediaType == "tv"
            ? .tvGenre(id: id, name: name)
            : .movieGenre(id: id, name: name)
    }
}

struct SeerrCompany: Identifiable, Hashable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case studio
        case network
    }

    var id: Int
    var name: String
    var kind: Kind
    var imageURL: URL?
    var siloSlug: String? = nil

    var query: SeerrDiscoverQuery {
        if let siloSlug {
            switch kind {
            case .studio: return .siloStudio(slug: siloSlug, name: name)
            case .network: return .siloNetwork(slug: siloSlug, name: name)
            }
        }
        switch kind {
        case .studio: return .studio(id: id, name: name)
        case .network: return .network(id: id, name: name)
        }
    }

    private static func tmdbLogo(_ path: String) -> URL? {
        URL(string: "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,2e2e2e)/\(path)")
    }

    static let studios: [SeerrCompany] = [
        .init(id: 2, name: "Disney", kind: .studio, imageURL: tmdbLogo("wdrCwmRnLFJhEoH8GSfymY85KHT.png")),
        .init(id: 127928, name: "20th Century Studios", kind: .studio, imageURL: tmdbLogo("h0rjX5vjW5r8yEnUBStFarjcLT4.png")),
        .init(id: 34, name: "Sony Pictures", kind: .studio, imageURL: tmdbLogo("GagSvqWlyPdkFHMfQ3pNq6ix9P.png")),
        .init(id: 174, name: "Warner Bros. Pictures", kind: .studio, imageURL: tmdbLogo("ky0xOc5OrhzkZ1N6KyUxacfQsCk.png")),
        .init(id: 33, name: "Universal", kind: .studio, imageURL: tmdbLogo("8lvHyhjr8oUKOOy2dKXoALWKdp0.png")),
        .init(id: 4, name: "Paramount", kind: .studio, imageURL: tmdbLogo("fycMZt242LVjagMByZOLUGbCvv3.png")),
        .init(id: 3, name: "Pixar", kind: .studio, imageURL: tmdbLogo("1TjvGVDMYsj6JBxOAkUHpPEwLf7.png")),
        .init(id: 521, name: "DreamWorks", kind: .studio, imageURL: tmdbLogo("kP7t6RwGz2AvvTkvnI1uteEwHet.png")),
        .init(id: 420, name: "Marvel Studios", kind: .studio, imageURL: tmdbLogo("hUzeosd33nzE5MCNsZxCGEKTXaQ.png")),
        .init(id: 9993, name: "DC", kind: .studio, imageURL: tmdbLogo("2Tc1P3Ac8M479naPp1kYT3izLS5.png")),
        .init(id: 41077, name: "A24", kind: .studio, imageURL: tmdbLogo("1ZXsGaFPgrgS6ZZGS37AqD5uU12.png"))
    ]

    static let networks: [SeerrCompany] = [
        .init(id: 213, name: "Netflix", kind: .network, imageURL: tmdbLogo("wwemzKWzjKYJFfCeiB57q3r4Bcm.png")),
        .init(id: 2739, name: "Disney+", kind: .network, imageURL: tmdbLogo("gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png")),
        .init(id: 1024, name: "Prime Video", kind: .network, imageURL: tmdbLogo("ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png")),
        .init(id: 2552, name: "Apple TV+", kind: .network, imageURL: tmdbLogo("4KAy34EHvRM25Ih8wb82AuGU7zJ.png")),
        .init(id: 453, name: "Hulu", kind: .network, imageURL: tmdbLogo("pqUTCleNUiTLAVlelGxUgWn1ELh.png")),
        .init(id: 49, name: "HBO", kind: .network, imageURL: tmdbLogo("tuomPhY2UtuPTqqFnKMVHvSb724.png")),
        .init(id: 4353, name: "Discovery+", kind: .network, imageURL: tmdbLogo("1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png")),
        .init(id: 2, name: "ABC", kind: .network, imageURL: tmdbLogo("ndAvF4JLsliGreX87jAc9GdjmJY.png")),
        .init(id: 19, name: "FOX", kind: .network, imageURL: tmdbLogo("1DSpHrWyOORkL9N2QHX7Adt31mQ.png")),
        .init(id: 359, name: "Cinemax", kind: .network, imageURL: tmdbLogo("6mSHSquNpfLgDdv6VnOOvC5Uz2h.png")),
        .init(id: 174, name: "AMC", kind: .network, imageURL: tmdbLogo("pmvRmATOCaDykE6JrVoeYxlFHw3.png")),
        .init(id: 67, name: "Showtime", kind: .network, imageURL: tmdbLogo("Allse9kbjiP6ExaQrnSpIhkurEi.png")),
        .init(id: 318, name: "Starz", kind: .network, imageURL: tmdbLogo("8GJjw3HHsAJYwIWKIPBPfqMxlEa.png")),
        .init(id: 71, name: "The CW", kind: .network, imageURL: tmdbLogo("ge9hzeaU7nMtQ4PjkFlHlxkurEi.png")),
        .init(id: 6, name: "NBC", kind: .network, imageURL: tmdbLogo("o3OedEP0f9mfZr33jz2BfXOUK5.png")),
        .init(id: 16, name: "CBS", kind: .network, imageURL: tmdbLogo("nm8d7P7MJNiBLdgIzUK0gkuEA4r.png")),
        .init(id: 4330, name: "Paramount+", kind: .network, imageURL: tmdbLogo("fi83B1oztoS47xxcemFdPMhIzK.png")),
        .init(id: 4, name: "BBC One", kind: .network, imageURL: tmdbLogo("mVn7xESaTNmjBUyUtGNvDQd3CT1.png")),
        .init(id: 56, name: "Cartoon Network", kind: .network, imageURL: tmdbLogo("c5OC6oVCg6QP4eqzW6XIq17CQjI.png")),
        .init(id: 80, name: "Adult Swim", kind: .network, imageURL: tmdbLogo("9AKyspxVzywuaMuZ1Bvilu8sXly.png")),
        .init(id: 13, name: "Nickelodeon", kind: .network, imageURL: tmdbLogo("ikZXxg6GnwpzqiZbRPhJGaZapqB.png")),
        .init(id: 3353, name: "Peacock", kind: .network, imageURL: tmdbLogo("gIAcGTjKKr0KOHL5s4O36roJ8p7.png"))
    ]
}

struct SeerrDiscoverHome: Sendable {
    var recentRequests: [SeerrTitle] = []
    var trending: [SeerrTitle] = []
    var popularMovies: [SeerrTitle] = []
    var upcomingMovies: [SeerrTitle] = []
    var popularTV: [SeerrTitle] = []
    var upcomingTV: [SeerrTitle] = []
    var movieGenres: [SeerrGenreSliderItem] = []
    var tvGenres: [SeerrGenreSliderItem] = []
    var studios: [SeerrCompany] = []
    var networks: [SeerrCompany] = []

    var isEmpty: Bool {
        recentRequests.isEmpty
            && trending.isEmpty
            && popularMovies.isEmpty
            && upcomingMovies.isEmpty
            && popularTV.isEmpty
            && upcomingTV.isEmpty
            && movieGenres.isEmpty
            && tvGenres.isEmpty
    }

    mutating func markRequested(_ title: SeerrTitle) {
        func patch(_ items: inout [SeerrTitle]) {
            if let index = items.firstIndex(where: { $0.id == title.id }) {
                items[index].availability = .pending
            }
        }
        patch(&recentRequests)
        patch(&trending)
        patch(&popularMovies)
        patch(&upcomingMovies)
        patch(&popularTV)
        patch(&upcomingTV)
    }
}

struct SeerrRequestListResponse: Decodable, Sendable {
    var pageInfo: SeerrPageInfo?
    var results: [SeerrListedRequest]
}

struct SeerrPageInfo: Decodable, Sendable {
    var page: Int?
    var pages: Int?
    var results: Int?
}

struct SeerrListedRequest: Decodable, Sendable {
    var id: Int
    var media: SeerrMediaInfo
    var requestedBy: SeerrUser?

    init(id: Int, media: SeerrMediaInfo, requestedBy: SeerrUser? = nil) {
        self.id = id
        self.media = media
        self.requestedBy = requestedBy
    }
}

extension SeerrClient {
    func discoverHome() async -> SeerrDiscoverHome {
        async let recentRequests = recentRequestTitles(page: 1)
        async let trending = discover(.trending)
        async let popularMovies = discover(.popularMovies)
        async let upcomingMovies = discover(.upcomingMovies)
        async let popularTV = discover(.popularTV)
        async let upcomingTV = discover(.upcomingTV)
        async let movieGenres = genreSlider(kind: .movie)
        async let tvGenres = genreSlider(kind: .tv)
        return SeerrDiscoverHome(
            recentRequests: (try? await recentRequests)?.titles ?? [],
            trending: (try? await trending)?.titles ?? [],
            popularMovies: (try? await popularMovies)?.titles ?? [],
            upcomingMovies: (try? await upcomingMovies)?.titles ?? [],
            popularTV: (try? await popularTV)?.titles ?? [],
            upcomingTV: (try? await upcomingTV)?.titles ?? [],
            movieGenres: (try? await movieGenres) ?? [],
            tvGenres: (try? await tvGenres) ?? [],
            studios: SeerrCompany.studios,
            networks: SeerrCompany.networks
        )
    }

    func listedRequests(page: Int = 1) async throws -> [SeerrListedRequest] {
        let payload: SeerrRequestListResponse = try await fetch(
            SeerrDiscoverQuery.requests.path,
            query: SeerrDiscoverQuery.requests.queryItems(page: page)
        )
        return payload.results
    }

    func discover(_ query: SeerrDiscoverQuery, page: Int = 1) async throws -> SeerrDiscoverPage {
        if query == .requests {
            return try await recentRequestTitles(page: page)
        }
        let payload: SeerrSearchResponse = try await fetch(query.path, query: query.queryItems(page: page))
        let defaultKind: SeerrTitle.Kind? = switch query {
        case .popularMovies, .upcomingMovies, .movieGenre, .studio: .movie
        case .popularTV, .upcomingTV, .tvGenre, .network: .tv
        default: nil
        }
        return SeerrDiscoverPage(
            titles: payload.results.compactMap { Self.title(from: $0, defaultKind: defaultKind) },
            page: payload.page ?? page,
            totalPages: payload.totalPages ?? page
        )
    }

    func genreSlider(kind: SeerrTitle.Kind) async throws -> [SeerrGenreSliderItem] {
        let path = kind == .movie ? "api/v1/discover/genreslider/movie" : "api/v1/discover/genreslider/tv"
        return try await fetch(path, query: [URLQueryItem(name: "language", value: "en")])
    }

    func titleDetails(kind: SeerrTitle.Kind, tmdbID: Int) async throws -> SeerrTitle {
        let path = kind == .movie ? "api/v1/movie/\(tmdbID)" : "api/v1/tv/\(tmdbID)"
        let payload: SeerrSearchResult = try await fetch(path, query: [URLQueryItem(name: "language", value: "en")])
        guard let title = Self.title(from: payload, defaultKind: kind) else {
            throw ZelefinError.server("Seerr did not return that title.")
        }
        return title
    }

    private func recentRequestTitles(page: Int) async throws -> SeerrDiscoverPage {
        let payload: SeerrRequestListResponse = try await fetch(
            SeerrDiscoverQuery.requests.path,
            query: SeerrDiscoverQuery.requests.queryItems(page: page)
        )
        let titles = await hydrate(payload.results)
        return SeerrDiscoverPage(
            titles: titles,
            page: payload.pageInfo?.page ?? page,
            totalPages: max(payload.pageInfo?.pages ?? page, 1)
        )
    }

    private func hydrate(_ requests: [SeerrListedRequest]) async -> [SeerrTitle] {
        await withTaskGroup(of: (Int, SeerrTitle?).self) { group in
            for (index, request) in requests.enumerated() {
                group.addTask {
                    (index, try? await self.title(for: request))
                }
            }
            var slots: [SeerrTitle?] = Array(repeating: nil, count: requests.count)
            for await (index, title) in group {
                slots[index] = title
            }
            return slots.compactMap { $0 }
        }
    }

    private func title(for request: SeerrListedRequest) async throws -> SeerrTitle {
        guard let tmdbID = request.media.tmdbId else {
            throw ZelefinError.server("Missing TMDB id.")
        }
        let kind: SeerrTitle.Kind = request.media.mediaType == "tv" ? .tv : .movie
        var title = try await titleDetails(kind: kind, tmdbID: tmdbID)
        title.requestID = request.id
        title.requestedByName = request.requestedBy?.requestLabel
        if title.availability == .missing || title.availability == .unknown {
            title.availability = .init(status: request.media.status)
            if title.availability == .missing {
                title.availability = .pending
            }
        }
        return title
    }
}
