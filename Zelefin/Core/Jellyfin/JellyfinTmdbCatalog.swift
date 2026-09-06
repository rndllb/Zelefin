import Foundation

/// TMDB identifiers for movies and series already in the signed-in Jellyfin library.
struct JellyfinTmdbCatalog: Equatable, Sendable {
    var movieIDs: Set<Int> = []
    var seriesIDs: Set<Int> = []

    /// A Boolean value that's true when `title` is already in this library.
    func contains(_ title: SeerrTitle) -> Bool {
        switch title.kind {
        case .movie: movieIDs.contains(title.tmdbID)
        case .tv: seriesIDs.contains(title.tmdbID)
        }
    }

    /// Returns the TMDB identifier stored in Jellyfin provider IDs.
    static func tmdbID(from providerIDs: [String: String]?) -> Int? {
        guard let providerIDs else { return nil }
        for (key, raw) in providerIDs where key.compare("Tmdb", options: [.caseInsensitive]) == .orderedSame {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmed) {
                return value
            }
        }
        return nil
    }

    /// Returns the IMDb identifier stored in Jellyfin provider IDs (`tt1375666`).
    static func imdbID(from providerIDs: [String: String]?) -> String? {
        guard let providerIDs else { return nil }
        for (key, raw) in providerIDs where key.compare("Imdb", options: [.caseInsensitive]) == .orderedSame {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("tt"), trimmed.dropFirst(2).allSatisfy(\.isNumber) {
                return trimmed
            }
            if !trimmed.isEmpty, trimmed.allSatisfy(\.isNumber) {
                return "tt\(trimmed)"
            }
        }
        return nil
    }
}
