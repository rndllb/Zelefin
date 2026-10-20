import Foundation

enum SiloMapper {
    static func mediaItem(from item: SiloCatalogItem, queueKind: PlaybackQueueKind = .resume) -> MediaItem {
        let overlay = item.overlaySummary
        let versions = item.fileIDGroups.flatMap { $0 }
        let fallbackWidth = versions.compactMap(\.width).max()
        let fallbackHeight = versions.compactMap(\.height).max()
        return MediaItem(
            id: item.contentID,
            name: item.displayTitle,
            kind: mediaKind(from: item.type),
            overview: item.overview,
            year: item.year,
            runtime: minutes(item.runtime) ?? item.durationSeconds,
            officialRating: item.contentRating,
            genres: item.genres ?? [],
            seriesName: item.seriesTitle,
            seasonIndex: item.seasonNumber,
            episodeIndex: item.episodeNumber,
            playbackPosition: item.userState?.seconds ?? item.positionSeconds ?? 0,
            unplayedCount: nil,
            isPlayed: item.userState?.watched ?? false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: item.seriesID,
            imageItemID: nil,
            queueKind: queueKind,
            videoRange: SiloQuality.videoRange(from: overlay),
            audioFormat: SiloQuality.audioFormat(from: overlay),
            criticRating: item.ratingRt,
            communityRating: item.ratingImdb ?? item.ratingTmdb ?? item.ratingRtAudience,
            dateCreated: item.addedAt,
            videoResolution: SiloQuality.videoResolution(
                from: overlay,
                fallbackWidth: fallbackWidth,
                fallbackHeight: fallbackHeight
            ),
            tmdbID: item.tmdbID,
            isFavorite: item.userState?.favoriteFlag ?? false,
            posterURL: item.posterURL,
            backdropURL: item.backdropURL,
            logoURL: item.logoURL
        )
    }

    static func mediaItem(from episode: SiloEpisodeRecord, seriesID: String, seriesTitle: String?) -> MediaItem? {
        let id = episode.contentID ?? episode.id
        guard let id, !id.isEmpty else { return nil }
        return MediaItem(
            id: id,
            name: (episode.title ?? episode.name)?.trimmedNonEmpty ?? "Episode",
            kind: .episode,
            overview: episode.overview,
            year: nil,
            runtime: minutes(episode.runtime),
            officialRating: nil,
            genres: [],
            seriesName: episode.seriesTitle ?? seriesTitle,
            seasonIndex: episode.seasonNumber,
            episodeIndex: episode.episodeNumber,
            playbackPosition: episode.userState?.seconds ?? 0,
            unplayedCount: nil,
            isPlayed: episode.userState?.watched ?? false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: episode.seriesID ?? seriesID,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            isFavorite: episode.userState?.favoriteFlag ?? false,
            posterURL: episode.posterURL,
            backdropURL: episode.backdropURL
        )
    }

    static func season(from record: SiloSeasonRecord, seriesID: String, seriesTitle: String?) -> MediaItem? {
        let id = record.contentID ?? record.id
        guard let id, !id.isEmpty else { return nil }
        let number = record.seasonNumber
        let isSpecials = record.isSpecials == true || number == 0
        let name = record.title ?? record.name ?? (isSpecials ? "Specials" : (number.map { "Season \($0)" } ?? "Season"))
        return MediaItem(
            id: id,
            name: name,
            kind: .season,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: seriesTitle,
            seasonIndex: number,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: record.episodeCount,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: seriesID,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            posterURL: record.posterURL
        )
    }

    static func library(from record: SiloLibraryRecord) -> MediaLibrary {
        let libraryKind = libraryKind(from: record.catalogKind)
        return MediaLibrary(
            id: String(record.id),
            name: record.name,
            kind: mediaKind(fromLibrary: libraryKind),
            libraryKind: libraryKind
        )
    }

    static func credits(from item: SiloCatalogItem) -> [CreditPerson] {
        let cast = (item.cast ?? []).sorted { ($0.order ?? Int.max) < ($1.order ?? Int.max) }
        let crew = item.crew ?? []
        return (cast + crew).enumerated().compactMap { index, record in
            let name = record.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }
            let role = (record.character ?? record.role ?? record.job)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return CreditPerson(
                id: record.personID ?? record.id ?? "\(item.contentID)-credit-\(index)",
                name: name,
                roleLabel: role.isEmpty ? (index < cast.count ? "Cast" : "Crew") : role,
                imageTag: nil,
                rank: record.order ?? index,
                imageURL: record.photoURL
            )
        }
    }

    static func moreInfo(from item: SiloCatalogItem) -> TitleMoreInfo {
        var info = TitleMoreInfoMapper.info(from: mediaItem(from: item))
        var rows: [TitleMoreRow] = []
        let studios = item.studios ?? []
        if !studios.isEmpty {
            rows.append(.init(label: "Studio", value: studios.joined(separator: ", ")))
        }
        let networks = item.networks ?? []
        if !networks.isEmpty {
            rows.append(.init(label: "Network", value: networks.joined(separator: ", ")))
        }
        if let original = item.originalTitle, original != item.displayTitle {
            rows.append(.init(label: "Original Title", value: original))
        }
        if let released = displayDate(item.releaseDate ?? item.firstAirDate) {
            rows.append(.init(label: "Released", value: released))
        }
        let skip = Set(rows.map(\.label))
        rows.append(contentsOf: info.information.filter { !skip.contains($0.label) })
        if let countries = item.countries, !countries.isEmpty,
           !rows.contains(where: { $0.label == "Regions of Origin" }) {
            rows.append(.init(label: "Regions of Origin", value: countries.joined(separator: ", ")))
        }
        if let status = item.showStatus, !rows.contains(where: { $0.label == "Status" }) {
            rows.append(.init(label: "Status", value: status))
        }
        if let air = item.airTime, !rows.contains(where: { $0.label == "Airs" }) {
            rows.append(.init(label: "Airs", value: air))
        }
        info.information = rows
        info.links = links(from: item)
        return info
    }

    static func trailers(from item: SiloCatalogItem) -> [TitleTrailer] {
        (item.videos ?? []).compactMap { video in
            let key = video.siteKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !key.isEmpty else { return nil }
            let site = (video.site ?? "").lowercased()
            let title = video.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Trailer"
            let kind: TitleTrailer.Kind?
            if site.contains("youtube") {
                kind = .youtube(key)
            } else if site.contains("vimeo") {
                kind = .vimeo(key)
            } else {
                kind = nil
            }
            guard let kind else { return nil }
            return TitleTrailer(id: "\(site)-\(key)", title: title, kind: kind)
        }
        .sorted { $0.trailerRank < $1.trailerRank }
    }

    static func extras(from item: SiloCatalogItem) -> [TitleExtra] {
        (item.extras ?? []).compactMap { extra in
            let id = extra.contentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !id.isEmpty else { return nil }
            let name = extra.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? extra.kind?.replacingOccurrences(of: "_", with: " ").capitalized
                ?? "Extra"
            let media = MediaItem(
                id: id,
                name: name,
                kind: .movie,
                overview: nil,
                year: nil,
                runtime: extra.durationSeconds,
                officialRating: nil,
                genres: [],
                seriesName: item.displayTitle,
                seasonIndex: nil,
                episodeIndex: nil,
                playbackPosition: 0,
                unplayedCount: nil,
                isPlayed: false,
                primaryImageTag: nil,
                thumbImageTag: nil,
                backdropImageTag: nil,
                backdropImageTags: [],
                logoImageTag: nil,
                parentBackdropItemID: nil,
                parentThumbItemID: nil,
                parentThumbImageTag: nil,
                parentLogoItemID: nil,
                parentLogoImageTag: nil,
                seriesThumbImageTag: nil,
                seriesID: item.contentID,
                imageItemID: nil,
                queueKind: .resume,
                videoRange: .sdr,
                audioFormat: .unknown,
                posterURL: item.backdropURL ?? item.posterURL
            )
            return TitleExtra(item: media, caption: extra.kind?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Extra")
        }
    }

    private static func links(from item: SiloCatalogItem) -> [TitleMoreLink] {
        var links: [TitleMoreLink] = []
        if let imdb = item.imdbID {
            let id = imdb.hasPrefix("tt") ? imdb : "tt\(imdb)"
            if let url = URL(string: "https://www.imdb.com/title/\(id)/") {
                links.append(.init(name: "IMDb", url: url))
            }
        }
        if let tmdb = item.tmdbID {
            let kind = mediaKind(from: item.type) == .series ? "tv" : "movie"
            if let url = URL(string: "https://www.themoviedb.org/\(kind)/\(tmdb)") {
                links.append(.init(name: "TMDB", url: url))
            }
        }
        return links
    }

    static func genreItem(name: String) -> MediaItem {
        MediaItem(
            id: name,
            name: name,
            kind: .genre,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [name],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }

    static func mediaItem(from collection: SiloPersonalCollection) -> MediaItem {
        MediaItem(
            id: collection.id,
            name: collection.name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Collection",
            kind: .collection,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: collection.itemCount,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: nil,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown,
            posterURL: collection.posterURL
        )
    }

    static func mediaItem(from event: SiloCalendarEvent) -> MediaItem? {
        guard event.watched != true else { return nil }
        let type = (event.type ?? "").lowercased()
        guard type.contains("episode") || type.contains("season") else { return nil }
        let id = event.contentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        let seriesTitle = event.title
        let episodeTitle = event.episodeTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return MediaItem(
            id: id,
            name: episodeTitle?.nilIfEmpty ?? seriesTitle ?? "Episode",
            kind: .episode,
            overview: nil,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: seriesTitle,
            seasonIndex: event.seasonNumber,
            episodeIndex: event.episodeNumber,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: nil,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: nil,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: event.seriesID,
            imageItemID: nil,
            queueKind: .nextUp,
            videoRange: .sdr,
            audioFormat: .unknown,
            premiereDate: parseDay(event.localAirDate ?? event.airDate),
            posterURL: event.posterURL
        )
    }

    static func recommendationSections(from rows: [SiloRecommendationRow]) -> [HomeSection] {
        rows.compactMap { row in
            let items = uniqueItems(row.entries.map { mediaItem(from: $0) })
            guard !items.isEmpty else { return nil }
            return HomeSection(
                id: row.sectionID,
                title: row.displayTitle,
                style: .portrait,
                items: items
            )
        }
    }

    static func homeFeed(from response: SiloHomeSectionsResponse) -> SiloMappedHome {
        var resume: [MediaItem] = []
        var nextUp: [MediaItem] = []
        var recentlyWatched: [MediaItem] = []
        var featured: [MediaItem] = []
        var librarySections: [HomeSection] = []
        var extraSections: [HomeSection] = []
        var collections: [MediaItem] = []
        var recommendations: [HomeSection] = []

        for section in response.rows {
            let kind = homeKind(for: section)
            let items = section.entries.map { entry in
                mediaItem(from: entry, queueKind: queueKind(for: kind, itemSource: entry.itemSource))
            }
            let visible = uniqueItems(items)
            guard !visible.isEmpty || kind == .skip else { continue }
            switch kind {
            case .continueWatching:
                for (entry, item) in zip(section.entries, items) {
                    if isNextUpSource(entry.itemSource) {
                        nextUp.append(item)
                    } else {
                        resume.append(item)
                    }
                }
            case .nextUp:
                nextUp.append(contentsOf: visible)
            case .recentlyWatched:
                recentlyWatched.append(contentsOf: visible)
            case .featured:
                featured.append(contentsOf: visible)
            case .collections:
                collections.append(contentsOf: visible)
            case .recommendations:
                recommendations.append(
                    HomeSection(
                        id: "recommend-\(section.resolvedID)",
                        title: section.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Recommended for You",
                        style: .portrait,
                        items: visible
                    )
                )
            case .library:
                let trimmed = section.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                librarySections.append(
                    HomeSection(
                        id: section.resolvedID,
                        title: trimmed.isEmpty ? "Recently Added" : trimmed,
                        style: .portrait,
                        items: visible
                    )
                )
            case .extra:
                let trimmed = section.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                extraSections.append(
                    HomeSection(
                        id: "silo-\(section.resolvedID)",
                        title: trimmed.isEmpty ? "More from Silo" : trimmed,
                        style: .portrait,
                        items: visible
                    )
                )
            case .skip:
                continue
            }
        }

        return SiloMappedHome(
            resume: uniqueItems(resume),
            nextUp: uniqueItems(nextUp),
            recentlyWatched: uniqueItems(recentlyWatched),
            featured: uniqueItems(featured),
            librarySections: librarySections,
            extraSections: extraSections,
            collections: uniqueItems(collections),
            recommendations: recommendations
        )
    }

    static func canonicalLibraryHome(
        _ sections: [HomeSection],
        libraries: [MediaLibrary]
    ) -> (movies: HomeSection?, shows: HomeSection?, extras: [HomeSection]) {
        var movieItems: [MediaItem] = []
        var showItems: [MediaItem] = []
        var extras: [HomeSection] = []
        for section in sections {
            switch libraryHomeClass(for: section) {
            case .extra:
                extras.append(section)
            case .movies, .shows:
                for item in section.items {
                    switch item.kind {
                    case .movie:
                        movieItems.append(item)
                    case .series, .season, .episode:
                        showItems.append(item)
                    default:
                        if libraryHomeClass(for: section) == .movies {
                            movieItems.append(item)
                        } else {
                            showItems.append(item)
                        }
                    }
                }
            }
        }
        let movieLibraryID = libraries.first(where: { $0.libraryKind == .movies })?.id ?? "movies"
        return (
            movies: uniqueSection(
                id: "library-\(movieLibraryID)",
                title: "Recently Added Movies",
                items: movieItems
            ),
            shows: uniqueSection(
                id: "library-shows",
                title: "Recently Added Shows",
                items: showItems
            ),
            extras: extras
        )
    }

    static func searchHit(from item: MediaItem) -> LibrarySearchHit {
        LibrarySearchHit(
            id: item.id,
            name: item.name,
            kind: .title(item.kind),
            subtitle: item.searchListSubtitle,
            year: item.year,
            imageTag: nil,
            imageURL: item.posterURL ?? item.backdropURL
        )
    }

    static func mediaKind(from raw: String?) -> MediaKind {
        switch (raw ?? "").lowercased() {
        case "movie", "movies": .movie
        case "show", "shows", "series": .series
        case "season", "seasons": .season
        case "episode", "episodes": .episode
        case "collection", "collections", "boxset": .collection
        default: .unknown
        }
    }

    static func catalogType(for kind: LibraryKind) -> String? {
        switch kind {
        case .movies: "movie"
        case .shows: "series"
        case .youTube: nil
        case .collections: "collection"
        default: nil
        }
    }

    static func libraryKind(from raw: String) -> LibraryKind {
        switch raw {
        case "movie", "movies": .movies
        case "show", "shows", "series", "tv": .shows
        case "collection", "collections": .collections
        case "live", "livetv", "live_tv": .liveTV
        case "music", "musicvideo", "musicvideos", "audio": .music
        default: .other
        }
    }

    static func mediaKind(fromLibrary kind: LibraryKind) -> MediaKind {
        switch kind {
        case .movies: .movie
        case .shows, .youTube: .series
        case .liveTV: .liveTV
        case .collections: .collection
        case .playlists: .playlist
        case .photos: .photo
        case .books: .book
        default: .unknown
        }
    }

    static func sortQuery(_ field: CatalogSortField) -> (sort: String, order: String) {
        switch field {
        case .name: ("title", "asc")
        case .dateAdded: ("added_at", "desc")
        case .releaseDate: ("year", "desc")
        case .communityRating, .criticRating: ("rating", "desc")
        case .runtime: ("runtime", "desc")
        case .datePlayed: ("date_viewed", "desc")
        default: ("title", "asc")
        }
    }

    private static func uniqueSection(id: String, title: String, items: [MediaItem]) -> HomeSection? {
        let unique = uniqueItems(items)
        guard !unique.isEmpty else { return nil }
        return HomeSection(id: id, title: title, style: .portrait, items: unique)
    }

    private static func libraryHomeClass(for section: HomeSection) -> SiloLibraryHomeClass {
        let title = section.title.lowercased()
        let id = section.id.lowercased()
        if title.contains("released"), !title.contains("added") { return .extra }
        if title.contains("show") || title.contains("series") || title.contains("tv")
            || id.contains("show") || id.contains("series") {
            return .shows
        }
        if title.contains("movie") || title.contains("film") || id.contains("movie") {
            return .movies
        }
        if section.items.contains(where: { $0.kind == .series }) { return .shows }
        if section.items.contains(where: { $0.kind == .movie }) { return .movies }
        return .extra
    }

    private static func minutes(_ value: Int?) -> TimeInterval? {
        guard let value, value > 0 else { return nil }
        return TimeInterval(value * 60)
    }

    private static func displayDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let prefix = String(raw.prefix(10))
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: prefix) else { return raw }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .none
        return display.string(from: date)
    }

    private static func uniqueItems(_ items: [MediaItem]) -> [MediaItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }

    private static func queueKind(for kind: SiloHomeKind, itemSource: String?) -> PlaybackQueueKind {
        if kind == .nextUp || isNextUpSource(itemSource) { return .nextUp }
        return .resume
    }

    private static func isNextUpSource(_ raw: String?) -> Bool {
        let value = (raw ?? "").replacingOccurrences(of: "-", with: "_").lowercased()
        return value.contains("next_up") || value == "on_deck"
    }

    private static func homeKind(for section: SiloHomeSection) -> SiloHomeKind {
        if section.featured == true { return .featured }
        let type = section.normalizedType.replacingOccurrences(of: "-", with: "_")
        if type.contains("continue") { return .continueWatching }
        if type.contains("next_up") || type.contains("nextup") || type.contains("next_in_series") || type.contains("on_deck") {
            return .nextUp
        }
        if type.contains("recently_watched") || type == "history" { return .recentlyWatched }
        if type.contains("featured") || type.contains("hero") { return .featured }
        if type.contains("recommend") || type.contains("because") || type.contains("taste")
            || type.contains("similar_users") || type.contains("for_you") {
            return .recommendations
        }
        if type.contains("collection") { return .collections }
        if type == "genre" || type.contains("browse_genre") { return .skip }
        if type.contains("recently_added") || type.contains("recently_released") { return .library }
        if type.contains("hidden") || type.contains("trending") || type.contains("seasonal")
            || type.contains("random") || type.contains("watchlist") || type.contains("favorite")
            || type.contains("custom") {
            return .extra
        }
        return .library
    }

    private static func parseDay(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

private enum SiloHomeKind: Sendable {
    case continueWatching
    case nextUp
    case recentlyWatched
    case featured
    case collections
    case recommendations
    case library
    case extra
    case skip
}

private enum SiloLibraryHomeClass: Sendable {
    case movies
    case shows
    case extra
}

struct SiloMappedHome: Sendable {
    var resume: [MediaItem]
    var nextUp: [MediaItem]
    var recentlyWatched: [MediaItem]
    var featured: [MediaItem]
    var librarySections: [HomeSection]
    var extraSections: [HomeSection]
    var collections: [MediaItem]
    var recommendations: [HomeSection]
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var nilIfEmpty: String? { trimmedNonEmpty }
}
