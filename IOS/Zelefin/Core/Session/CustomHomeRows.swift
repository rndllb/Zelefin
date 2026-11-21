import Foundation

enum CustomHomeRowScope: String, CaseIterable, Identifiable, Sendable {
    case movies
    case shows
    case both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .movies: AppLanguage.string("tab.movies", default: "Movies")
        case .shows: AppLanguage.string("tab.shows", default: "Shows")
        case .both: AppLanguage.string("home.movies_and_shows", default: "Movies & Shows")
        }
    }

    static func from(raw: String?) -> CustomHomeRowScope {
        guard let raw, let scope = CustomHomeRowScope(rawValue: raw) else { return .movies }
        return scope
    }

    var catalogKinds: [LibraryKind] {
        switch self {
        case .movies: [.movies]
        case .shows: [.shows]
        case .both: [.movies, .shows]
        }
    }

  /// Catalog tabs and filter options use a single kind; movies first when both.
    var primaryLibraryKind: LibraryKind {
        catalogKinds[0]
    }
}

struct CatalogBrowseQueryDto: Codable, Hashable, Sendable {
    var statuses: [String] = []
    var features: [String] = []
    var videoKinds: [String] = []
    var genres: [String] = []
    var officialRatings: [String] = []
    var tags: [String] = []
    var years: [Int] = []
    var studios: [String] = []
    var audioLanguages: [String] = []
    var subtitleLanguages: [String] = []
    var sort: String = CatalogSortField.name.rawValue
    var sortAscending = true

    init() {}

    init(_ query: CatalogBrowseQuery) {
        statuses = query.statuses.map(\.rawValue)
        features = query.features.map(\.rawValue)
        videoKinds = query.videoKinds.map(\.rawValue)
        genres = query.genres.sorted()
        officialRatings = query.officialRatings.sorted()
        tags = query.tags.sorted()
        years = query.years.sorted()
        studios = query.studios.sorted()
        audioLanguages = query.audioLanguages.sorted()
        subtitleLanguages = query.subtitleLanguages.sorted()
        sort = query.sort.rawValue
        sortAscending = query.sortAscending
    }

    func toQuery() -> CatalogBrowseQuery {
        var query = CatalogBrowseQuery.default
        query.statuses = Set(statuses.compactMap(CatalogStatusFilter.init(rawValue:)))
        query.features = Set(features.compactMap(CatalogFeatureFilter.init(rawValue:)))
        query.videoKinds = Set(videoKinds.compactMap(CatalogVideoKind.init(rawValue:)))
        query.genres = Set(genres)
        query.officialRatings = Set(officialRatings)
        query.tags = Set(tags)
        query.years = Set(years)
        query.studios = Set(studios)
        query.audioLanguages = Set(audioLanguages)
        query.subtitleLanguages = Set(subtitleLanguages)
        if let resolved = CatalogSortField(rawValue: sort) {
            query.sort = resolved
        }
        query.sortAscending = sortAscending
        return query
    }
}

struct CustomHomeRow: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var scope: String
    var query: CatalogBrowseQueryDto
    var enabled: Bool

    init(
        id: String = UUID().uuidString,
        title: String = AppLanguage.string("settings.custom_row", default: "Custom Row"),
        scope: String = CustomHomeRowScope.movies.rawValue,
        query: CatalogBrowseQueryDto = CatalogBrowseQueryDto(),
        enabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.scope = scope
        self.query = query
        self.enabled = enabled
    }

    var resolvedScope: CustomHomeRowScope { CustomHomeRowScope.from(raw: scope) }

    var browseQuery: CatalogBrowseQuery { query.toQuery() }

    func withQuery(_ next: CatalogBrowseQuery) -> CustomHomeRow {
        var row = self
        row.query = CatalogBrowseQueryDto(next)
        return row
    }
}

enum HomeRowSlot: Hashable, Identifiable, Sendable {
    case builtIn(HomeRowKind)
    case custom(String)

    static let customPrefix = "custom:"

    var id: String { raw }

    var raw: String {
        switch self {
        case let .builtIn(kind): kind.rawValue
        case let .custom(id): Self.customPrefix + id
        }
    }

    static func parse(_ token: String) -> HomeRowSlot? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(customPrefix) {
            let id = String(trimmed.dropFirst(customPrefix.count))
            return id.isEmpty ? nil : .custom(id)
        }
        guard let kind = HomeRowKind(rawValue: trimmed) else { return nil }
        return .builtIn(kind)
    }

    static func ordered(from raw: String, customIDs: Set<String>) -> [HomeRowSlot] {
        var seen = Set<HomeRowSlot>()
        var order: [HomeRowSlot] = []
        for token in raw.split(separator: ",") {
            guard let slot = parse(String(token)) else { continue }
            switch slot {
            case let .builtIn(kind) where seen.insert(slot).inserted:
                order.append(.builtIn(kind))
            case let .custom(id) where customIDs.contains(id) && seen.insert(slot).inserted:
                order.append(.custom(id))
            default:
                continue
            }
        }
        for kind in HomeRowKind.allCases {
            let slot = HomeRowSlot.builtIn(kind)
            if seen.insert(slot).inserted {
                order.append(slot)
            }
        }
        for id in customIDs {
            let slot = HomeRowSlot.custom(id)
            if seen.insert(slot).inserted {
                order.append(slot)
            }
        }
        return order
    }

    static func rawOrder(_ slots: [HomeRowSlot]) -> String {
        var seen = Set<HomeRowSlot>()
        return slots.compactMap { slot in
            seen.insert(slot).inserted ? slot.raw : nil
        }.joined(separator: ",")
    }
}

enum CustomHomeRows {
    static let storageKey = "zelefin.custom-home-rows"
    static let syncKey = "customHomeRows"
    static let sectionIDPrefix = "custom-"
    static let previewLimit = 24

    private static let encoder: JSONEncoder = {
        let json = JSONEncoder()
        return json
    }()

    private static let decoder: JSONDecoder = {
        let json = JSONDecoder()
        return json
    }()

    static var rows: [CustomHomeRow] {
        get { decode(UserDefaults.standard.string(forKey: storageKey)) }
        set { save(newValue) }
    }

    static func load() {
        _ = rows
    }

    static func save(_ next: [CustomHomeRow]) {
        UserDefaults.standard.set(encode(next), forKey: storageKey)
    }

    @discardableResult
    static func add(_ row: CustomHomeRow = CustomHomeRow()) -> CustomHomeRow {
        save(rows + [row])
        return row
    }

    static func update(_ row: CustomHomeRow) {
        save(rows.map { $0.id == row.id ? row : $0 })
    }

    static func remove(id: String) {
        save(rows.filter { $0.id != id })
    }

    static func row(id: String) -> CustomHomeRow? {
        rows.first { $0.id == id }
    }

    static func encode(_ list: [CustomHomeRow] = rows) -> String {
        guard let data = try? encoder.encode(list) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ raw: String?) -> [CustomHomeRow] {
        guard let raw, !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        return (try? decoder.decode([CustomHomeRow].self, from: data)) ?? []
    }

    static func applySynced(_ raw: String?) {
        guard let raw else { return }
        save(decode(raw))
    }

    static func sectionID(for rowID: String) -> String {
        sectionIDPrefix + rowID
    }

    static func queryStoreKey(id: String) -> String {
        "custom-home:\(id)"
    }

    static func filterSummary(_ row: CustomHomeRow) -> String {
        let query = row.browseQuery
        var parts = [row.resolvedScope.title]
        if query.activeFilterCount > 0 {
            parts.append("\(query.activeFilterCount) filters")
        }
        if query.sort != .name || !query.sortAscending {
            parts.append(query.sort.title + (query.sortAscending ? "" : " ↓"))
        }
        return parts.joined(separator: " · ")
    }

    static func insertCustomSlot(id: String, into orderRaw: inout String) {
        let customIDs = Set(rows.map(\.id))
        var slots = HomeRowSlot.ordered(from: orderRaw, customIDs: customIDs)
        guard !slots.contains(where: { if case let .custom(existing) = $0 { return existing == id } else { return false } }) else {
            return
        }
        let insertAt = slots.firstIndex(where: { if case let .builtIn(kind) = $0 { return kind == .recentlyAddedMovies } else { return false } })
            .map { $0 + 1 } ?? slots.count
        slots.insert(.custom(id), at: insertAt)
        orderRaw = HomeRowSlot.rawOrder(slots)
    }

    static func removeCustomSlot(id: String, from orderRaw: inout String) {
        let customIDs = Set(rows.map(\.id))
        let slots = HomeRowSlot.ordered(from: orderRaw, customIDs: customIDs).filter { slot in
            if case let .custom(existing) = slot { return existing != id }
            return true
        }
        orderRaw = HomeRowSlot.rawOrder(slots)
    }

    static func fetchSections(
        libraries: [MediaLibrary],
        using library: any LibraryServing
    ) async -> [HomeSection] {
        let enabled = rows.filter(\.enabled)
        guard !enabled.isEmpty else { return [] }
        return await withTaskGroup(of: HomeSection?.self) { group in
            for row in enabled {
                group.addTask {
                    await section(for: row, libraries: libraries, using: library)
                }
            }
            var sections: [HomeSection] = []
            for await section in group {
                if let section {
                    sections.append(section)
                }
            }
            return sections
        }
    }

  private static func section(
        for row: CustomHomeRow,
        libraries: [MediaLibrary],
        using library: any LibraryServing
    ) async -> HomeSection? {
        let kinds = row.resolvedScope.catalogKinds
        let matches = libraries.filter { kinds.contains($0.libraryKind) }
        guard !matches.isEmpty else { return nil }
        let items = await library.browseCatalogKinds(
            kinds: kinds,
            libraries: matches,
            query: row.browseQuery
        )
        let preview = Array(items.prefix(previewLimit))
        guard !preview.isEmpty else { return nil }
        return HomeSection(
            id: sectionID(for: row.id),
            title: row.title,
            style: .portrait,
            items: preview
        )
    }
}

extension LibraryServing {
    func browseCatalogKinds(
        kinds: [LibraryKind],
        libraries: [MediaLibrary],
        query: CatalogBrowseQuery,
        onPage: CatalogPageHandler? = nil
    ) async -> [MediaItem] {
        if kinds.count == 1 {
            return await browseCatalog(kind: kinds[0], libraries: libraries, query: query, onPage: onPage)
        }
        let matches = libraries.filter { kinds.contains($0.libraryKind) }
        return await items(inLibraries: matches, query: query, onPage: onPage)
    }
}