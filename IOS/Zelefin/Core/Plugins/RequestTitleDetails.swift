import Foundation

/// A Discover title's page: what Seerr or Ombi knows about a movie or show that may not be on Jellyfin yet.
struct RequestTitleDetails: Sendable {
    var backdropURL: URL?
    var posterURL: URL?
    var tagline: String?
    var overview: String?
    var genres: [String] = []
    var releaseDate: Date?
    var runtimeMinutes: Int?
    var seasonCount: Int?
    /// The studio for a movie, the network for a show.
    var studio: String?
    var studioLabel = "Studio"
    var status: String?
    /// TMDB's score out of 10.
    var voteAverage: Double?
    var directors: [String] = []
    var creators: [String] = []
    var cast: [RequestCastMember] = []
    var videos: [RequestVideo] = []
    var related: [SeerrTitle] = []
    var homepage: URL?
    var imdbID: String?

    /// The rows under Information, in the order the Jellyfin detail page shows them.
    var facts: [TitleMoreRow] {
        var rows: [TitleMoreRow] = []
        if let releaseDate {
            rows.append(TitleMoreRow(label: "Released", value: releaseDate.formatted(date: .long, time: .omitted)))
        }
        if let runtimeMinutes, runtimeMinutes > 0 {
            let hours = runtimeMinutes / 60
            let minutes = runtimeMinutes % 60
            rows.append(TitleMoreRow(label: "Run Time", value: hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min"))
        }
        if let seasonCount, seasonCount > 0 {
            rows.append(TitleMoreRow(label: "Seasons", value: "\(seasonCount)"))
        }
        if !genres.isEmpty {
            rows.append(TitleMoreRow(label: "Genre", value: genres.joined(separator: ", ")))
        }
        if !directors.isEmpty {
            rows.append(TitleMoreRow(label: directors.count > 1 ? "Directors" : "Director", value: directors.joined(separator: ", ")))
        }
        if !creators.isEmpty {
            rows.append(TitleMoreRow(label: "Created By", value: creators.joined(separator: ", ")))
        }
        if let studio, !studio.isEmpty {
            rows.append(TitleMoreRow(label: studioLabel, value: studio))
        }
        if let status, !status.isEmpty {
            rows.append(TitleMoreRow(label: "Status", value: status))
        }
        if let voteAverage, voteAverage > 0 {
            rows.append(TitleMoreRow(label: "TMDB Rating", value: String(format: "%.1f / 10", voteAverage)))
        }
        return rows
    }

    /// Trailers first, then teasers, then everything else YouTube has.
    var trailers: [RequestVideo] {
        videos.sorted { $0.rank < $1.rank }
    }

    /// A TMDB release day, read in the local time zone so it shows as the same day.
    static func date(_ raw: String?) -> Date? {
        guard let raw, raw.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(raw.prefix(10))),
              Calendar(identifier: .gregorian).component(.year, from: date) > 1900
        else { return nil }
        return date
    }
}

struct RequestCastMember: Identifiable, Hashable, Sendable {
    var id: Int
    var name: String
    var role: String?
    var imageURL: URL?

    var creditPerson: CreditPerson {
        CreditPerson(id: "tmdb-\(id)", name: name, roleLabel: role ?? "", imageTag: nil, rank: 0, imageURL: imageURL)
    }
}

/// A YouTube video on TMDB: a trailer, teaser, or featurette.
struct RequestVideo: Identifiable, Hashable, Sendable {
    var key: String
    var name: String
    var type: String?

    var id: String { key }

    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(key)") }
    var thumbnailURL: URL? { URL(string: "https://img.youtube.com/vi/\(key)/hqdefault.jpg") }

    var rank: Int {
        switch type {
        case "Trailer": 0
        case "Teaser": 1
        default: 2
        }
    }

    init?(key: String?, name: String?, type: String?, site: String?) {
        guard let key, !key.isEmpty, site == nil || site == "YouTube" else { return nil }
        self.key = key
        self.name = name?.isEmpty == false ? name! : "Trailer"
        self.type = type
    }
}

// MARK: - Seerr

extension SeerrClient {
    func titleDetails(for title: SeerrTitle) async throws -> RequestTitleDetails {
        switch title.kind {
        case .movie:
            async let movie: SeerrMovieFull = fetch("api/v1/movie/\(title.tmdbID)")
            async let related = recommendations(for: title)
            var details = try await movie.details
            details.related = await related
            return details
        case .tv:
            async let show: SeerrShowFull = fetch("api/v1/tv/\(title.tmdbID)")
            async let related = recommendations(for: title)
            var details = try await show.details
            details.related = await related
            return details
        }
    }

    func webURL(for title: SeerrTitle) -> URL? {
        baseURL.appending(path: "\(title.kind.rawValue)/\(title.tmdbID)")
    }

    private func recommendations(for title: SeerrTitle) async -> [SeerrTitle] {
        let page: SeerrSearchResponse? = try? await fetch(
            "api/v1/\(title.kind.rawValue)/\(title.tmdbID)/recommendations",
            query: [URLQueryItem(name: "page", value: "1"), URLQueryItem(name: "language", value: "en")]
        )
        return (page?.results ?? []).compactMap { Self.title(from: $0, defaultKind: title.kind) }
    }
}

private struct SeerrNamed: Decodable {
    var name: String?
}

private struct SeerrCredits: Decodable {
    struct Cast: Decodable {
        var id: Int
        var name: String?
        var character: String?
        var profilePath: String?
    }

    struct Crew: Decodable {
        var name: String?
        var job: String?
    }

    var cast: [Cast]?
    var crew: [Crew]?

    var members: [RequestCastMember] {
        (cast ?? []).prefix(30).compactMap { person in
            guard let name = person.name, !name.isEmpty else { return nil }
            return RequestCastMember(id: person.id, name: name, role: person.character, imageURL: SeerrClient.tmdbImageURL(person.profilePath, size: "w185"))
        }
    }

    var directors: [String] {
        (crew ?? []).filter { $0.job == "Director" }.compactMap(\.name)
    }
}

private struct SeerrExternalIDs: Decodable {
    var imdbId: String?
}

private struct SeerrMovieFull: Decodable {
    var backdropPath: String?
    var posterPath: String?
    var tagline: String?
    var overview: String?
    var genres: [SeerrNamed]?
    var releaseDate: String?
    var runtime: Int?
    var status: String?
    var voteAverage: Double?
    var productionCompanies: [SeerrNamed]?
    var credits: SeerrCredits?
    var relatedVideos: [SeerrRelatedVideo]?
    var homepage: String?
    var externalIds: SeerrExternalIDs?
    var imdbId: String?

    var details: RequestTitleDetails {
        RequestTitleDetails(
            backdropURL: SeerrClient.tmdbImageURL(backdropPath, size: "w1280"),
            posterURL: SeerrClient.tmdbImageURL(posterPath, size: "w500"),
            tagline: tagline,
            overview: overview,
            genres: (genres ?? []).compactMap(\.name),
            releaseDate: RequestTitleDetails.date(releaseDate),
            runtimeMinutes: runtime,
            studio: productionCompanies?.first?.name,
            status: status,
            voteAverage: voteAverage,
            directors: credits?.directors ?? [],
            cast: credits?.members ?? [],
            videos: (relatedVideos ?? []).compactMap { RequestVideo(key: $0.key, name: $0.name, type: $0.type, site: $0.site) },
            homepage: homepage.flatMap(URL.init(string:)),
            imdbID: externalIds?.imdbId ?? imdbId
        )
    }
}

private struct SeerrShowFull: Decodable {
    var backdropPath: String?
    var posterPath: String?
    var tagline: String?
    var overview: String?
    var genres: [SeerrNamed]?
    var firstAirDate: String?
    var episodeRunTime: [Int]?
    var numberOfSeasons: Int?
    var status: String?
    var voteAverage: Double?
    var networks: [SeerrNamed]?
    var createdBy: [SeerrNamed]?
    var credits: SeerrCredits?
    var relatedVideos: [SeerrRelatedVideo]?
    var homepage: String?
    var externalIds: SeerrExternalIDs?

    var details: RequestTitleDetails {
        RequestTitleDetails(
            backdropURL: SeerrClient.tmdbImageURL(backdropPath, size: "w1280"),
            posterURL: SeerrClient.tmdbImageURL(posterPath, size: "w500"),
            tagline: tagline,
            overview: overview,
            genres: (genres ?? []).compactMap(\.name),
            releaseDate: RequestTitleDetails.date(firstAirDate),
            runtimeMinutes: episodeRunTime?.first,
            seasonCount: numberOfSeasons,
            studio: networks?.first?.name,
            studioLabel: "Network",
            status: status,
            voteAverage: voteAverage,
            creators: (createdBy ?? []).compactMap(\.name),
            cast: credits?.members ?? [],
            videos: (relatedVideos ?? []).compactMap { RequestVideo(key: $0.key, name: $0.name, type: $0.type, site: $0.site) },
            homepage: homepage.flatMap(URL.init(string:)),
            imdbID: externalIds?.imdbId
        )
    }
}
