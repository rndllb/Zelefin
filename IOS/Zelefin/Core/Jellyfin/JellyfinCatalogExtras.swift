import Foundation
import JellyfinAPI

struct RemoteIdentifyHit: Sendable, Identifiable {
    var id: String { providerIDs.values.sorted().joined(separator: "|") + name }
    var name: String
    var year: Int?
    var overview: String?
    var providerIDs: [String: String]
    var imageURL: URL?
    var raw: RemoteSearchResult
}

struct ItemMetadataDraft: Hashable, Sendable {
    var name: String
    var overview: String
    var year: String
    var officialRating: String
    var genres: String
    var tags: String

    init(item: MediaItem, tags: [String] = []) {
        name = item.name
        overview = item.overview ?? ""
        year = item.year.map(String.init) ?? ""
        officialRating = item.officialRating ?? ""
        genres = item.genres.joined(separator: ", ")
        self.tags = tags.joined(separator: ", ")
    }
}

enum CatalogQueryStore {
    private static let prefix = "zelefin.catalog-query."

    static func load(key: String) -> CatalogBrowseQuery {
        guard let data = UserDefaults.standard.data(forKey: prefix + key),
              let query = try? JSONDecoder().decode(StoredQuery.self, from: data)
        else { return .default }
        return query.asQuery
    }

    static func save(key: String, query: CatalogBrowseQuery) {
        let stored = StoredQuery(query)
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: prefix + key)
        }
    }

    static func key(kind: LibraryKind, libraryID: String?) -> String {
        if let libraryID { return "library:\(libraryID)" }
        return "kind:\(kind.rawValue)"
    }

    private struct StoredQuery: Codable {
        var sort: String
        var sortAscending: Bool
        var statuses: [String]
        var genres: [String]
        var years: [Int]

        init(_ query: CatalogBrowseQuery) {
            sort = query.sort.rawValue
            sortAscending = query.sortAscending
            statuses = query.statuses.map(\.rawValue)
            genres = Array(query.genres)
            years = Array(query.years)
        }

        var asQuery: CatalogBrowseQuery {
            var query = CatalogBrowseQuery.default
            query.sortAscending = sortAscending
            query.genres = Set(genres)
            query.years = Set(years)
            query.statuses = Set(statuses.compactMap(CatalogStatusFilter.init(rawValue:)))
            if let sort = CatalogSortField(rawValue: sort) {
                query.sort = sort
            }
            return query
        }
    }
}

extension JellyfinLibraryClient {
    static let watchlistPlaylistName = "Watchlist"

    func additionalParts(for itemID: String) async -> [MediaItem] {
        let result = try? await client.send(Paths.getAdditionalPart(itemID: itemID, userID: userID)).value
        return (result?.items ?? []).compactMap(ItemMapper.mediaItem(from:))
    }

    func randomTitle() async -> MediaItem? {
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 1,
                    isRecursive: true,
                    fields: ItemMapper.listFields,
                    includeItemTypes: [.movie, .series],
                    sortBy: [.random],
                    enableUserData: true,
                    enableImages: true
                )
            )
        ).value
        return (result?.items ?? []).compactMap(ItemMapper.mediaItem(from:)).first
    }

    func watchlistPlaylistID() async throws -> String {
        let result = try await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID,
                    limit: 20,
                    isRecursive: true,
                    searchTerm: Self.watchlistPlaylistName,
                    includeItemTypes: [.playlist]
                )
            )
        ).value
        if let existing = (result.items ?? []).first(where: { $0.name?.caseInsensitiveCompare(Self.watchlistPlaylistName) == .orderedSame }),
           let id = existing.id {
            return id
        }
        let created = try await client.send(
            Paths.createPlaylist(
                CreatePlaylistDto(
                    ids: [],
                    isPublic: false,
                    mediaType: .video,
                    name: Self.watchlistPlaylistName,
                    userID: userID
                )
            )
        ).value
        guard let id = created.id else {
            throw ZelefinError.server("Jellyfin did not create a Watchlist playlist.")
        }
        return id
    }

    func watchlistItems() async -> [MediaItem] {
        guard let playlist = try? await watchlistPlaylistID() else { return [] }
        return ((try? await playlistEntries(playlistID: playlist)) ?? []).map {
            $0.item.withWatchlisted(true)
        }
    }

    func setWatchlisted(itemID: String, watchlisted: Bool) async throws {
        let playlist = try await watchlistPlaylistID()
        if watchlisted {
            try await addToPlaylist(playlistID: playlist, itemIDs: [itemID])
        } else {
            let entries = try await playlistEntries(playlistID: playlist)
            let ids = entries.filter { $0.item.id == itemID }.map(\.id)
            if !ids.isEmpty {
                try await removeFromPlaylist(playlistID: playlist, entryIDs: ids)
            }
        }
    }

    func identifyHits(for item: MediaItem) async -> [RemoteIdentifyHit] {
        switch item.kind {
        case .movie:
            let info = MovieInfo(name: item.name, providerIDs: item.tmdbID.map { ["Tmdb": String($0)] }, year: item.year)
            let results = (try? await client.send(
                Paths.getMovieRemoteSearchResults(
                    MovieInfoRemoteSearchQuery(itemID: item.id, searchInfo: info)
                )
            ).value) ?? []
            return results.map(Self.hit(from:))
        case .series:
            let info = SeriesInfo(name: item.name, providerIDs: item.tmdbID.map { ["Tmdb": String($0)] }, year: item.year)
            let results = (try? await client.send(
                Paths.getSeriesRemoteSearchResults(
                    SeriesInfoRemoteSearchQuery(itemID: item.id, searchInfo: info)
                )
            ).value) ?? []
            return results.map(Self.hit(from:))
        default:
            return []
        }
    }

    func applyIdentify(itemID: String, hit: RemoteIdentifyHit) async throws {
        _ = try await client.send(Paths.applySearchCriteria(itemID: itemID, isReplaceAllImages: true, hit.raw))
    }

    func updateItemMetadata(itemID: String, draft: ItemMetadataDraft) async throws {
        let current = try await client.send(Paths.getItem(itemID: itemID, userID: userID)).value
        var next = current
        next.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        next.overview = draft.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        next.productionYear = Int(draft.year.trimmingCharacters(in: .whitespacesAndNewlines))
        next.officialRating = draft.officialRating.trimmingCharacters(in: .whitespacesAndNewlines)
        next.genres = draft.genres.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        next.tags = draft.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        _ = try await client.send(Paths.updateItem(itemID: itemID, next))
    }

    private static func hit(from result: RemoteSearchResult) -> RemoteIdentifyHit {
        RemoteIdentifyHit(
            name: result.name?.trimmingCharacters(in: .whitespacesAndNewlines).ifEmpty("Untitled") ?? "Untitled",
            year: result.productionYear,
            overview: result.overview?.trimmingCharacters(in: .whitespacesAndNewlines),
            providerIDs: result.providerIDs ?? [:],
            imageURL: result.imageURL.flatMap(URL.init(string:)),
            raw: result
        )
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String {
        isEmpty ? fallback : self
    }
}
