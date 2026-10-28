import Foundation

/// TheIntroDB's community skip times, for the kinds the server has no markers for: every Emby title,
/// Jellyfin without a skip plugin, and the recaps or credits Intro Skipper didn't find. Jellyfin's
/// TheIntroDB plugin and Silo write the same data into media segments.
enum TheIntroDB {
    struct Lookup: Hashable, Sendable {
        var tvdbID: Int?
        var tmdbID: Int?
        var imdbID: String?
        var season: Int?
        var episode: Int?
        /// Picks the matching release (theatrical, extended, a DVD cut) when the API knows several.
        var durationMS: Int?

        var hasIdentity: Bool { tvdbID != nil || tmdbID != nil || imdbID != nil }
    }

    private static let endpoint = URL(string: "https://api.theintrodb.org/v4/media")!
    private static let cache = Cache()
    static let blockedUntilKey = "zelefin.theintrodb.blocked-until"
    /// Without an API key TheIntroDB allows a daily number of lookups per public address, shared with
    /// every device and server at home; once it says they're spent, asking again only wastes requests.
    private static let fallbackBlock: TimeInterval = 60 * 60

    /// Server markers win; TheIntroDB only adds the kinds the server has none of.
    static func filling(_ server: [SkipSegment], from community: [SkipSegment]) -> [SkipSegment] {
        let known = Set(server.map(\.kind))
        return (server + community.filter { !known.contains($0.kind) }).sorted { $0.start < $1.start }
    }

    static func coversEveryKind(_ segments: [SkipSegment]) -> Bool {
        Set(segments.map(\.kind)).count == SkipSegment.Kind.allCases.count
    }

    static func isBlocked(now: Date = .now, defaults: UserDefaults = .standard) -> Bool {
        defaults.double(forKey: blockedUntilKey) > now.timeIntervalSince1970
    }

    static func block(retryAfter: String?, now: Date = .now, defaults: UserDefaults = .standard) {
        let seconds = retryAfter.flatMap { TimeInterval($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        let wait = seconds > 0 ? seconds : fallbackBlock
        defaults.set(now.timeIntervalSince1970 + wait, forKey: blockedUntilKey)
    }

    /// Skip segments for `item`. Episodes are looked up by their show plus season and episode, which
    /// costs one library request for the show's provider ids.
    static func segments(for item: MediaItem, library: any LibraryServing) async -> [SkipSegment] {
        guard let lookup = await lookup(for: item, library: library) else { return [] }
        return await segments(for: lookup, runtime: item.runtime)
    }

    static func lookup(for item: MediaItem, library: any LibraryServing) async -> Lookup? {
        let duration = item.runtime.map { Int($0 * 1000) }
        switch item.kind {
        case .movie:
            let lookup = Lookup(tvdbID: item.tvdbID, tmdbID: item.tmdbID, imdbID: item.imdbID, durationMS: duration)
            return lookup.hasIdentity ? lookup : nil
        case .episode:
            guard let seriesID = item.seriesID, let season = item.seasonIndex, let episode = item.episodeIndex,
                  let series = try? await library.item(id: seriesID) else { return nil }
            let lookup = Lookup(
                tvdbID: series.tvdbID,
                tmdbID: series.tmdbID,
                imdbID: series.imdbID,
                season: season,
                episode: episode,
                durationMS: duration
            )
            return lookup.hasIdentity ? lookup : nil
        default:
            return nil
        }
    }

    static func segments(for lookup: Lookup, runtime: TimeInterval?) async -> [SkipSegment] {
        if let cached = await cache.value(for: lookup) { return cached }
        guard !isBlocked(), let url = url(for: lookup) else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return [] }
        if http.statusCode == 429 {
            block(retryAfter: http.value(forHTTPHeaderField: "Retry-After"))
            return []
        }
        // 404 is "no submissions for this media": a real answer, worth remembering. An outage is
        // not, so the next play asks again.
        guard http.statusCode == 200 || http.statusCode == 404 else { return [] }
        let segments = http.statusCode == 200 ? parse(data, runtime: runtime) : []
        await cache.store(segments, for: lookup)
        return segments
    }

    static func url(for lookup: Lookup) -> URL? {
        var items: [URLQueryItem] = []
        if let tvdb = lookup.tvdbID { items.append(.init(name: "tvdb_id", value: String(tvdb))) }
        if let tmdb = lookup.tmdbID { items.append(.init(name: "tmdb_id", value: String(tmdb))) }
        if let imdb = lookup.imdbID { items.append(.init(name: "imdb_id", value: imdb)) }
        guard !items.isEmpty else { return nil }
        if let season = lookup.season, let episode = lookup.episode {
            items.append(.init(name: "season", value: String(season)))
            items.append(.init(name: "episode", value: String(episode)))
        }
        if let duration = lookup.durationMS, duration > 0 {
            items.append(.init(name: "duration_ms", value: String(duration)))
        }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = items
        return components?.url
    }

    /// A null start runs from the beginning and a null end to the end of the title, so open-ended
    /// credits need the runtime; without one they are dropped rather than guessed.
    static func parse(_ data: Data, runtime: TimeInterval?) -> [SkipSegment] {
        guard let body = try? JSONDecoder().decode(MediaBody.self, from: data) else { return [] }
        let groups: [(SkipSegment.Kind, [Timestamp]?)] = [
            (.recap, body.recap), (.intro, body.intro), (.outro, body.credits), (.preview, body.preview)
        ]
        return groups.flatMap { kind, stamps in
            (stamps ?? []).compactMap { stamp -> SkipSegment? in
                let start = stamp.startMS.map { Double($0) / 1000 } ?? 0
                guard let end = stamp.endMS.map({ Double($0) / 1000 }) ?? runtime, end - start >= 3 else { return nil }
                return SkipSegment(kind: kind, start: start, end: end)
            }
        }
        .sorted { $0.start < $1.start }
    }

    private struct MediaBody: Decodable {
        var intro: [Timestamp]?
        var recap: [Timestamp]?
        var credits: [Timestamp]?
        var preview: [Timestamp]?
    }

    private struct Timestamp: Decodable {
        var startMS: Int?
        var endMS: Int?

        enum CodingKeys: String, CodingKey {
            case startMS = "start_ms"
            case endMS = "end_ms"
        }
    }

    /// One lookup per title per launch: replays and quality restarts would otherwise spend
    /// TheIntroDB's per-address rate limit.
    private actor Cache {
        private var entries: [Lookup: [SkipSegment]] = [:]

        func value(for lookup: Lookup) -> [SkipSegment]? { entries[lookup] }

        func store(_ segments: [SkipSegment], for lookup: Lookup) {
            if entries.count > 200 { entries.removeAll() }
            entries[lookup] = segments
        }
    }
}
