import Foundation
import JellyfinAPI

enum CatalogStatusFilter: String, CaseIterable, Hashable, Sendable {
    case played
    case unplayed
    case favorite
    case continueWatching

    var title: String {
        switch self {
        case .played: "Played"
        case .unplayed: "Unplayed"
        case .favorite: "Favorite"
        case .continueWatching: "Continue Watching"
        }
    }
}

enum CatalogFeatureFilter: String, CaseIterable, Hashable, Sendable {
    case subtitles
    case trailers
    case extras
    case themeSongs
    case themeVideos

    var title: String {
        switch self {
        case .subtitles: "Subtitles"
        case .trailers: "Trailers"
        case .extras: "Extras"
        case .themeSongs: "Theme Songs"
        case .themeVideos: "Theme Videos"
        }
    }
}

enum CatalogVideoKind: String, CaseIterable, Hashable, Sendable {
    case sd
    case hd
    case fourK
    case threeD
    case dvd
    case bluRay
    case iso

    var title: String {
        switch self {
        case .sd: "SD"
        case .hd: "HD"
        case .fourK: "4K"
        case .threeD: "3D"
        case .dvd: "DVD"
        case .bluRay: "Blu-ray"
        case .iso: "ISO"
        }
    }

    var isResolution: Bool {
        switch self {
        case .sd, .hd, .fourK: true
        default: false
        }
    }

    var isDisc: Bool {
        switch self {
        case .dvd, .bluRay, .iso: true
        default: false
        }
    }
}

enum CatalogSortField: String, CaseIterable, Hashable, Sendable, Identifiable {
    case name
    case random
    case communityRating
    case criticRating
    case dateAdded
    case datePlayed
    case parentalRating
    case playCount
    case releaseDate
    case runtime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Name"
        case .random: "Random"
        case .communityRating: "Community Rating"
        case .criticRating: "Critics Rating"
        case .dateAdded: "Date Added"
        case .datePlayed: "Date Played"
        case .parentalRating: "Parental Rating"
        case .playCount: "Play Count"
        case .releaseDate: "Release Date"
        case .runtime: "Runtime"
        }
    }

    var itemSortBy: ItemSortBy {
        switch self {
        case .name: .sortName
        case .random: .random
        case .communityRating: .communityRating
        case .criticRating: .criticRating
        case .dateAdded: .dateCreated
        case .datePlayed: .datePlayed
        case .parentalRating: .officialRating
        case .playCount: .playCount
        case .releaseDate: .premiereDate
        case .runtime: .runtime
        }
    }

    var allowsDirection: Bool { self != .random }

    /// Sorts Silo's Jellyfin-compatible API applies; it falls back to its own order for the rest.
    var isServedBySilo: Bool {
        switch self {
        case .name, .random, .communityRating, .dateAdded, .releaseDate: true
        case .criticRating, .datePlayed, .parentalRating, .playCount, .runtime: false
        }
    }
}

struct CatalogFilterChoice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

struct CatalogFilterOptions: Hashable, Sendable {
    var genres: [CatalogFilterChoice] = []
    var officialRatings: [CatalogFilterChoice] = []
    var tags: [CatalogFilterChoice] = []
    var years: [CatalogFilterChoice] = []
    var studios: [CatalogFilterChoice] = []
    var languages: [CatalogFilterChoice] = []
}

struct CatalogBrowseQuery: Hashable, Sendable {
    var statuses: Set<CatalogStatusFilter> = []
    var features: Set<CatalogFeatureFilter> = []
    var videoKinds: Set<CatalogVideoKind> = []
    var genres: Set<String> = []
    var officialRatings: Set<String> = []
    var tags: Set<String> = []
    var years: Set<Int> = []
    var studios: Set<String> = []
    var audioLanguages: Set<String> = []
    var subtitleLanguages: Set<String> = []
    var sort: CatalogSortField = .name
    var sortAscending = true

    static let `default` = CatalogBrowseQuery()

    func applyingFavoriteFilter() -> CatalogBrowseQuery {
        var next = self
        next.statuses.insert(.favorite)
        return next
    }

    var isDefault: Bool {
        statuses.isEmpty
            && features.isEmpty
            && videoKinds.isEmpty
            && genres.isEmpty
            && officialRatings.isEmpty
            && tags.isEmpty
            && years.isEmpty
            && studios.isEmpty
            && audioLanguages.isEmpty
            && subtitleLanguages.isEmpty
            && sort == .name
            && sortAscending
    }

    var activeFilterCount: Int {
        statuses.count
            + features.count
            + videoKinds.count
            + genres.count
            + officialRatings.count
            + tags.count
            + years.count
            + studios.count
            + audioLanguages.count
            + subtitleLanguages.count
    }

    var itemFilters: [ItemFilter] {
        var filters: [ItemFilter] = []
        let played = statuses.contains(.played)
        let unplayed = statuses.contains(.unplayed)
        if played != unplayed {
            filters.append(played ? .isPlayed : .isUnplayed)
        }
        if statuses.contains(.favorite) {
            filters.append(.isFavorite)
        }
        if statuses.contains(.continueWatching) {
            filters.append(.isResumable)
        }
        return filters
    }

    var videoTypes: [VideoType] {
        CatalogVideoKind.allCases.compactMap { kind in
            guard videoKinds.contains(kind) else { return nil }
            switch kind {
            case .dvd: return .dvd
            case .bluRay: return .bluRay
            case .iso: return .iso
            default: return nil
            }
        }
    }

    var is3D: Bool? {
        videoKinds.contains(.threeD) ? true : nil
    }

    /// One pass when resolutions do not need OR; several when SD and 4K are mixed.
    var resolutionPasses: [(isHd: Bool?, is4K: Bool?)] {
        let picked = Set(videoKinds.filter(\.isResolution))
        if picked.isEmpty { return [(nil, nil)] }
        if picked.contains(.sd) && picked.contains(.hd) { return [(nil, nil)] }
        if picked == [.sd, .fourK] { return [(false, nil), (nil, true)] }
        if picked.contains(.fourK) && !picked.contains(.hd) && !picked.contains(.sd) {
            return [(nil, true)]
        }
        if picked.contains(.hd) { return [(true, nil)] }
        if picked.contains(.sd) { return [(false, nil)] }
        return [(nil, nil)]
    }

    var extraLanguageQuery: [(String, String?)] {
        var items: [(String, String?)] = []
        if !audioLanguages.isEmpty {
            items.append(("audioLanguages", audioLanguages.sorted().joined(separator: ",")))
        }
        if !subtitleLanguages.isEmpty {
            items.append(("subtitleLanguages", subtitleLanguages.sorted().joined(separator: ",")))
        }
        return items
    }

    mutating func clearFilters() {
        statuses = []
        features = []
        videoKinds = []
        genres = []
        officialRatings = []
        tags = []
        years = []
        studios = []
        audioLanguages = []
        subtitleLanguages = []
    }

    func apply(to parameters: inout Paths.GetItemsParameters, isHd: Bool?, is4K: Bool?) {
        let filters = itemFilters
        parameters.filters = filters.isEmpty ? nil : filters
        parameters.hasSubtitles = features.contains(.subtitles) ? true : nil
        parameters.hasTrailer = features.contains(.trailers) ? true : nil
        parameters.hasSpecialFeature = features.contains(.extras) ? true : nil
        parameters.hasThemeSong = features.contains(.themeSongs) ? true : nil
        parameters.hasThemeVideo = features.contains(.themeVideos) ? true : nil
        parameters.isHd = isHd
        parameters.isIs4K = is4K
        parameters.isIs3D = is3D
        let discs = videoTypes
        parameters.videoTypes = discs.isEmpty ? nil : discs
        parameters.genres = genres.isEmpty ? nil : genres.sorted()
        parameters.officialRatings = officialRatings.isEmpty ? nil : officialRatings.sorted()
        parameters.tags = tags.isEmpty ? nil : tags.sorted()
        parameters.years = years.isEmpty ? nil : years.sorted()
        parameters.studios = studios.isEmpty ? nil : studios.sorted()
        parameters.sortBy = [sort.itemSortBy]
        if sort.allowsDirection {
            parameters.sortOrder = [sortAscending ? .ascending : .descending]
        } else {
            parameters.sortOrder = nil
        }
    }

    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        if sort == .random { return items.shuffled() }
        let ordered: [MediaItem]
        switch sort {
        case .name:
            ordered = items.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .random:
            ordered = items
        case .communityRating:
            ordered = items.sorted { ($0.communityRating ?? -1) < ($1.communityRating ?? -1) }
        case .criticRating:
            ordered = items.sorted { ($0.criticRating ?? -1) < ($1.criticRating ?? -1) }
        case .dateAdded:
            ordered = items.sorted { ($0.dateCreated ?? .distantPast) < ($1.dateCreated ?? .distantPast) }
        case .datePlayed:
            ordered = items.sorted { ($0.lastPlayedDate ?? .distantPast) < ($1.lastPlayedDate ?? .distantPast) }
        case .parentalRating:
            ordered = items.sorted {
                ($0.officialRating ?? "").localizedStandardCompare($1.officialRating ?? "") == .orderedAscending
            }
        case .playCount:
            ordered = items.sorted { $0.playCount < $1.playCount }
        case .releaseDate:
            ordered = items.sorted { ($0.year ?? 0) < ($1.year ?? 0) }
        case .runtime:
            ordered = items.sorted { ($0.runtime ?? 0) < ($1.runtime ?? 0) }
        }
        return sortAscending ? ordered : ordered.reversed()
    }
}

enum CatalogFilterLists {
    static func choices(from names: [String]?) -> [CatalogFilterChoice] {
        (names ?? []).compactMap { name in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return CatalogFilterChoice(id: trimmed, name: trimmed)
        }
    }

    static func yearChoices(from years: [Int]?) -> [CatalogFilterChoice] {
        (years ?? []).sorted(by: >).map { year in
            CatalogFilterChoice(id: String(year), name: String(year))
        }
    }

    static func languageChoices(from cultures: [CultureDto]) -> [CatalogFilterChoice] {
        var seen = Set<String>()
        var choices: [CatalogFilterChoice] = []
        for culture in cultures {
            let code = culture.threeLetterISOLanguageName
                ?? culture.twoLetterISOLanguageName
                ?? ""
            let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            let name = culture.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            choices.append(
                CatalogFilterChoice(
                    id: trimmed,
                    name: (name?.isEmpty == false ? name : nil) ?? trimmed.uppercased()
                )
            )
        }
        return choices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
