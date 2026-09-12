import Foundation
import JellyfinAPI

enum JellyfinEnhancedPlugin {
    static func isInstalled(names: [String]) -> Bool {
        names.contains { name in
            let compact = name.lowercased().filter(\.isLetter)
            return compact.contains("jellyfinenhanced")
        }
    }
}

enum JellyfinEnhancedHomeSurface: String, Equatable, Sendable {
    case continueWatching
    case nextUp
}

enum JellyfinEnhancedHomeHide {
    static func surface(queueKind: PlaybackQueueKind) -> JellyfinEnhancedHomeSurface {
        queueKind == .nextUp ? .nextUp : .continueWatching
    }

    static func menuTitle(for surface: JellyfinEnhancedHomeSurface) -> String {
        switch surface {
        case .continueWatching: "Remove from Continue Watching"
        case .nextUp: "Remove from Next Up"
        }
    }

    static func path(itemID: String, surface: JellyfinEnhancedHomeSurface) -> String {
        let encoded = itemID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? itemID
        switch surface {
        case .continueWatching:
            return "/JellyfinEnhanced/continue-watching/hide/\(encoded)"
        case .nextUp:
            return "/JellyfinEnhanced/next-up/hide/\(encoded)"
        }
    }
}

enum JellyfinEnhancedReviewKey {
    static func target(for item: MediaItem) -> (mediaType: String, tmdbID: String)? {
        guard let tmdbID = item.tmdbID, tmdbID > 0 else { return nil }
        switch item.kind {
        case .movie:
            return ("movie", "\(tmdbID)")
        case .series, .season, .episode:
            return ("tv", "\(tmdbID)")
        default:
            return nil
        }
    }
}

struct JellyfinEnhancedReview: Equatable, Identifiable, Sendable {
    var userID: String
    var userName: String
    var content: String
    var rating: Double?
    var createdAt: String?
    var updatedAt: String?

    var id: String { userID }

    var hasText: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func isAuthored(by userID: String) -> Bool {
        Self.normalizedUserID(self.userID) == Self.normalizedUserID(userID)
    }

    static func normalizedUserID(_ value: String) -> String {
        value.filter { $0 != "-" }.lowercased()
    }

    static func averageRating(in reviews: [JellyfinEnhancedReview]) -> Double? {
        let scores = reviews.compactMap(\.rating)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}

enum JellyfinEnhancedReviewPayload {
    static func isValid(content: String, rating: Double?) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 2000 { return false }
        if let rating {
            guard rating >= 1, rating <= 5 else { return false }
            let steps = (rating * 2).rounded()
            guard abs(rating * 2 - steps) < 0.001 else { return false }
        }
        return rating != nil || !trimmed.isEmpty
    }

    static func body(content: String, rating: Double?) -> [String: Any] {
        var payload: [String: Any] = [:]
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            payload["content"] = trimmed
        }
        if let rating {
            payload["rating"] = rating
        }
        return payload
    }
}

struct JellyfinEnhancedAward: Equatable, Identifiable, Sendable {
    var name: String
    var result: String
    var year: Int?
    var recipients: [String]
    var works: [String]

    var id: String {
        "\(name)-\(result)-\(year ?? 0)-\(recipients.joined(separator: ","))"
    }

    var isWin: Bool {
        result.compare("Won", options: .caseInsensitive) == .orderedSame
    }

    var detailLine: String? {
        let people = recipients.filter { !$0.isEmpty }
        if !people.isEmpty {
            return people.joined(separator: ", ")
        }
        let titles = works.filter { !$0.isEmpty }
        if !titles.isEmpty {
            return titles.joined(separator: ", ")
        }
        return nil
    }
}

struct JellyfinEnhancedAwards: Equatable, Sendable {
    var found: Bool
    var wins: Int
    var nominations: Int
    var awards: [JellyfinEnhancedAward]

    var isEmpty: Bool {
        !found || (wins == 0 && nominations == 0 && awards.isEmpty)
    }

    var summary: String {
        var parts: [String] = []
        if wins > 0 {
            parts.append(wins == 1 ? "1 win" : "\(wins) wins")
        }
        if nominations > 0 {
            parts.append(nominations == 1 ? "1 nomination" : "\(nominations) nominations")
        }
        if parts.isEmpty, !awards.isEmpty {
            parts.append(awards.count == 1 ? "1 award" : "\(awards.count) awards")
        }
        return parts.joined(separator: " · ")
    }
}

struct TMDBUserReview: Equatable, Identifiable, Sendable {
    var id: String
    var author: String
    var content: String
    var rating: Double?

    /// TMDB scores are out of 10; title-page stars are out of 5.
    var starsOutOfFive: Double? {
        guard let rating else { return nil }
        return min(5, max(0, rating / 2))
    }

    static func averageStars(in reviews: [TMDBUserReview]) -> Double? {
        let scores = reviews.compactMap(\.starsOutOfFive)
        guard !scores.isEmpty else { return nil }
        return scores.reduce(0, +) / Double(scores.count)
    }
}

struct JellyfinEnhancedClient: Sendable {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func isReachable() async -> Bool {
        do {
            _ = try await send(method: "GET", path: "/JellyfinEnhanced/version", ok: [200])
            return true
        } catch {
            return false
        }
    }

    func hideFromHome(itemID: String, surface: JellyfinEnhancedHomeSurface) async throws {
        let path = JellyfinEnhancedHomeHide.path(itemID: itemID, surface: surface)
        _ = try await send(method: "POST", path: path, ok: [200, 201, 204])
    }

    func reviews(mediaType: String, tmdbID: String) async throws -> [JellyfinEnhancedReview] {
        let path = "/JellyfinEnhanced/reviews/\(mediaType)/\(encoded(tmdbID))"
        let data = try await send(method: "GET", path: path, ok: [200])
        return JellyfinEnhancedJSON.reviews(from: data)
    }

    func saveReview(mediaType: String, tmdbID: String, content: String, rating: Double?) async throws {
        guard JellyfinEnhancedReviewPayload.isValid(content: content, rating: rating) else {
            throw ZelefinError.server("Add a star rating or a few words.")
        }
        let path = "/JellyfinEnhanced/reviews/\(mediaType)/\(encoded(tmdbID))"
        let body = try JSONSerialization.data(
            withJSONObject: JellyfinEnhancedReviewPayload.body(content: content, rating: rating)
        )
        _ = try await send(method: "POST", path: path, body: body, ok: [200, 201, 204])
    }

    func deleteOwnReview(mediaType: String, tmdbID: String) async throws {
        let path = "/JellyfinEnhanced/reviews/\(mediaType)/\(encoded(tmdbID))"
        _ = try await send(method: "DELETE", path: path, ok: [200, 204])
    }

    func deleteReview(userID: String, mediaType: String, tmdbID: String) async throws {
        let compact = JellyfinEnhancedReview.normalizedUserID(userID)
        let path = "/JellyfinEnhanced/reviews/admin/\(compact)/\(mediaType)/\(encoded(tmdbID))"
        _ = try await send(method: "DELETE", path: path, ok: [200, 204])
    }

    func awards(mediaType: String, tmdbID: String) async -> JellyfinEnhancedAwards? {
        let path = "/JellyfinEnhanced/awards/\(mediaType)/\(encoded(tmdbID))"
        do {
            let data = try await send(method: "GET", path: path, ok: [200])
            let parsed = JellyfinEnhancedJSON.awards(from: data)
            return parsed.isEmpty ? nil : parsed
        } catch {
            return nil
        }
    }

    func tmdbReviews(mediaType: String, tmdbID: String) async -> [TMDBUserReview] {
        let path = "/JellyfinEnhanced/tmdb/\(mediaType)/\(encoded(tmdbID))/reviews?language=en-US&page=1"
        do {
            let data = try await send(method: "GET", path: path, ok: [200])
            return JellyfinEnhancedJSON.tmdbReviews(from: data)
        } catch {
            return []
        }
    }

    private func encoded(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    @discardableResult
    private func send(
        method: String,
        path: String,
        body: Data? = nil,
        ok: Set<Int>
    ) async throws -> Data {
        // Auth is on the request headers. Do not put the Jellyfin token in the query:
        // the TMDB proxy forwards the whole query string to themoviedb.org, and a
        // Jellyfin api_key there makes TMDB reject the request.
        guard let url = ServerURL.resolve(
            base: client.configuration.url,
            path: path
        ) else {
            throw ZelefinError.invalidServerURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let token = client.accessToken {
            request.setValue("MediaBrowser Token=\"\(token)\"", forHTTPHeaderField: "Authorization")
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await JellyfinNetworking.apiData(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ZelefinError.server("The server did not respond.")
        }
        if AccessGateway.isChallenge(response: http, data: data) {
            throw ZelefinError.accessGateway
        }
        guard ok.contains(http.statusCode) else {
            throw ZelefinError.server(Self.failureMessage(statusCode: http.statusCode, data: data))
        }
        return data
    }

    private static func failureMessage(statusCode: Int, data: Data) -> String {
        if let object = JellyfinEnhancedJSON.object(from: data) {
            if let message = JellyfinEnhancedJSON.string(object, "message", "Message"), !message.isEmpty {
                return message
            }
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty,
           !text.hasPrefix("<")
        {
            return text
        }
        return "The server returned \(statusCode)."
    }
}

enum JellyfinEnhancedJSON {
    static func object(from data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func value(_ object: [String: Any], _ keys: String...) -> Any? {
        for key in keys {
            if let value = object[key] {
                return value
            }
            if let match = object.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
                return match.value
            }
        }
        return nil
    }

    static func string(_ object: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = value(object, key) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    static func int(_ object: [String: Any], _ keys: String...) -> Int? {
        for key in keys {
            switch value(object, key) {
            case let number as Int:
                return number
            case let number as Double:
                return Int(number)
            case let number as NSNumber:
                return number.intValue
            case let text as String:
                if let parsed = Int(text) { return parsed }
            default:
                continue
            }
        }
        return nil
    }

    static func double(_ object: [String: Any], _ keys: String...) -> Double? {
        for key in keys {
            switch value(object, key) {
            case let number as Double:
                return number
            case let number as Int:
                return Double(number)
            case let number as NSNumber:
                return number.doubleValue
            default:
                continue
            }
        }
        return nil
    }

    static func bool(_ object: [String: Any], _ keys: String...) -> Bool? {
        for key in keys {
            switch value(object, key) {
            case let flag as Bool:
                return flag
            default:
                continue
            }
        }
        return nil
    }

    static func reviews(from data: Data) -> [JellyfinEnhancedReview] {
        guard let object = object(from: data) else { return [] }
        let raw = value(object, "reviews", "Reviews") as? [Any] ?? []
        return raw.compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            let userID = string(row, "userId", "UserId") ?? ""
            guard !userID.isEmpty else { return nil }
            return JellyfinEnhancedReview(
                userID: userID,
                userName: string(row, "userName", "UserName") ?? "Someone",
                content: string(row, "content", "Content") ?? "",
                rating: double(row, "rating", "Rating"),
                createdAt: string(row, "createdAt", "CreatedAt"),
                updatedAt: string(row, "updatedAt", "UpdatedAt")
            )
        }
    }

    static func awards(from data: Data) -> JellyfinEnhancedAwards {
        guard let object = object(from: data) else {
            return JellyfinEnhancedAwards(found: false, wins: 0, nominations: 0, awards: [])
        }
        let raw = value(object, "awards", "Awards") as? [Any] ?? []
        let awards = raw.compactMap { item -> JellyfinEnhancedAward? in
            guard let row = item as? [String: Any] else { return nil }
            guard let name = string(row, "name", "Name") else { return nil }
            return JellyfinEnhancedAward(
                name: name,
                result: string(row, "result", "Result") ?? "",
                year: int(row, "year", "Year"),
                recipients: stringList(row, "recipients", "Recipients"),
                works: stringList(row, "works", "Works")
            )
        }
        return JellyfinEnhancedAwards(
            found: bool(object, "found", "Found") ?? !awards.isEmpty,
            wins: int(object, "wins", "Wins") ?? awards.filter(\.isWin).count,
            nominations: int(object, "nominations", "Nominations") ?? awards.filter { !$0.isWin }.count,
            awards: awards
        )
    }

    static func tmdbReviews(from data: Data) -> [TMDBUserReview] {
        let rows: [Any]
        if let object = object(from: data), let results = value(object, "results", "Results") as? [Any] {
            rows = results
        } else if let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] {
            rows = array
        } else {
            return []
        }
        return rows.prefix(12).compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            let content = string(row, "content", "Content") ?? ""
            guard !content.isEmpty else { return nil }
            let details = value(row, "author_details", "authorDetails", "AuthorDetails") as? [String: Any]
            let rating = details.flatMap { double($0, "rating", "Rating") }
            return TMDBUserReview(
                id: string(row, "id", "Id") ?? content,
                author: string(row, "author", "Author")
                    ?? details.flatMap { string($0, "username", "name", "Username", "Name") }
                    ?? "TMDB",
                content: content,
                rating: rating
            )
        }
    }

    private static func stringList(_ object: [String: Any], _ keys: String...) -> [String] {
        for key in keys {
            if let values = value(object, key) as? [String] {
                return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            }
            if let values = value(object, key) as? [Any] {
                return values.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }
}
