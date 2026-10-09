import Foundation

enum MediaKind: String, Hashable, Sendable, Codable {
    case movie
    case series
    case season
    case episode
    case collection
    case genre
    case playlist
    case liveTV
    case book
    case photo
    case unknown

    var usesVideoPlayer: Bool {
        switch self {
        case .movie, .series, .season, .episode, .liveTV, .unknown:
            true
        case .collection, .genre, .playlist, .book, .photo:
            false
        }
    }
}

enum VideoRange: String, Hashable, Sendable, Codable {
    case sdr
    case hdr10
    case hdr10Plus
    case dolbyVision
    case hlg

    var displayName: String {
        switch self {
        case .sdr: "SDR"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .dolbyVision: "Dolby Vision"
        case .hlg: "HLG"
        }
    }
}

enum AudioFormat: String, Hashable, Sendable, Codable {
    case stereo
    case surround
    case atmos
    case unknown

    var displayName: String {
        switch self {
        case .stereo: "Stereo"
        case .surround: "Surround"
        case .atmos: "Dolby Atmos"
        case .unknown: "Audio"
        }
    }
}

enum VideoResolution: String, Hashable, Sendable, Codable {
    case sd
    case hd
    case fourK
    case unknown

    var displayName: String? {
        switch self {
        case .sd: "SD"
        case .hd: "HD"
        case .fourK: "4K"
        case .unknown: nil
        }
    }
}

enum PlaybackQueueKind: String, Hashable, Sendable, Codable {
    case resume
    case nextUp

    var listStatusLabel: String {
        switch self {
        case .resume: "CONTINUE"
        case .nextUp: "NEXT"
        }
    }
}

enum PlaybackMethod: String, Hashable, Sendable, Codable {
    case directPlay
    case remux
    case transcode

    var displayName: String {
        switch self {
        case .directPlay: "Direct Play"
        case .remux: "Remux"
        case .transcode: "Transcode"
        }
    }
}

struct MediaItem: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let kind: MediaKind
    let overview: String?
    let year: Int?
    let runtime: TimeInterval?
    let officialRating: String?
    let genres: [String]
    let seriesName: String?
    let seasonIndex: Int?
    let episodeIndex: Int?
    var playbackPosition: TimeInterval
    let unplayedCount: Int?
    let isPlayed: Bool
    let primaryImageTag: String?
    let thumbImageTag: String?
    let backdropImageTag: String?
    let backdropImageTags: [String]
    let logoImageTag: String?
    let parentBackdropItemID: String?
    let parentThumbItemID: String?
    let parentThumbImageTag: String?
    let parentLogoItemID: String?
    let parentLogoImageTag: String?
    let seriesThumbImageTag: String?
    let seriesID: String?
    let imageItemID: String?
    let queueKind: PlaybackQueueKind
    let videoRange: VideoRange
    let audioFormat: AudioFormat
    var criticRating: Double? = nil
    var communityRating: Double? = nil
    var dateCreated: Date? = nil
    var lastPlayedDate: Date? = nil
    var playCount: Int = 0
    var videoResolution: VideoResolution = .unknown
    var hasClosedCaptions: Bool = false
    var hasAudioDescription: Bool = false
    var sourceBitrate: Int? = nil
    var tmdbID: Int? = nil
    var isFavorite: Bool = false
    var isWatchlisted: Bool = false
    var likes: Bool? = nil
    var premiereDate: Date? = nil
    var posterURL: URL? = nil
    var backdropURL: URL? = nil
    var logoURL: URL? = nil

    var progress: Double {
        guard let runtime, runtime > 0 else { return 0 }
        return min(1, max(0, playbackPosition / runtime))
    }

    var episodeLabel: String? {
        guard kind == .episode else { return nil }
        guard let seasonIndex, let episodeIndex else { return seriesName }
        let remaining: String
        if let runtime {
            let leftover = max(0, runtime - playbackPosition)
            remaining = " · \(Self.minutesLabel(leftover, rounding: .down))"
        } else {
            remaining = ""
        }
        return "S\(seasonIndex), E\(episodeIndex)\(remaining)"
    }

    var remainingPlayback: TimeInterval? {
        guard let runtime, runtime > 0 else { return nil }
        return max(0, runtime - playbackPosition)
    }

    var runtimeLabel: String? {
        guard let runtime, runtime > 0 else { return nil }
        return Self.minutesLabel(runtime)
    }

    /// Parental-guidance mark derived from Jellyfin’s `OfficialRating` (PG-13 → 13+, and so on).
    var ageGateLabel: String? {
        guard let officialRating else { return nil }
        let compact = officialRating.uppercased().filter { !$0.isWhitespace }
        if compact.contains("NC-17") || compact == "X" { return "18+" }
        if compact == "R" || compact.contains("TV-MA") { return "17+" }
        if compact.contains("PG-13") || compact.contains("TV-14") { return "13+" }
        if compact.contains("TV-Y7") || compact == "PG" || compact.contains("TV-PG") { return "7+" }
        if compact == "G" || compact.hasPrefix("TV-Y") || compact.contains("TV-G") { return "All" }
        if compact.hasSuffix("+") { return officialRating }
        return nil
    }

    /// Hours and minutes shown on the detail play control: time left while in progress, otherwise runtime.
    var playActionDurationLabel: String? {
        if playbackPosition > 5, let remainingPlayback, remainingPlayback > 0 {
            return Self.minutesLabel(remainingPlayback, rounding: .down)
        }
        guard let runtime, runtime > 0 else { return nil }
        return Self.minutesLabel(runtime)
    }

    /// The title the hero Play control should start: an in-progress episode, else the next unwatched one.
    static func heroPlaybackItem(title: MediaItem, episodes: [MediaItem]) -> MediaItem {
        guard title.kind == .series else { return title }
        if let resumable = episodes.first(where: { !$0.isWatched && $0.playbackPosition > 5 }) {
            return resumable
        }
        if let upcoming = episodes.first(where: { !$0.isWatched }) {
            return upcoming
        }
        return episodes.first ?? title
    }

    var continueWatchingCaption: String? {
        let remaining = remainingPlayback.map { Self.minutesLabel($0, rounding: .down) }
        if kind == .episode, let seasonIndex, let episodeIndex {
            if let remaining {
                return "S\(seasonIndex), E\(episodeIndex) · \(remaining)"
            }
            return "S\(seasonIndex), E\(episodeIndex)"
        }
        return remaining
    }

    var artworkItemID: String { imageItemID ?? id }

    /// OpenSubtitles (and Jellyfin remote search) only cover movies and episodes.
    var supportsRemoteSubtitles: Bool {
        kind == .movie || kind == .episode
    }

    /// Series id to open instead of a standalone episode or season page.
    var seriesDetailItemID: String? {
        guard kind == .episode || kind == .season else { return nil }
        guard let seriesID, !seriesID.isEmpty else { return nil }
        return seriesID
    }

    /// Placeholder series item so the show hero paints before `getItem` returns.
    func seriesShowcasePreview() -> MediaItem {
        let showID = seriesDetailItemID ?? id
        return MediaItem(
            id: showID,
            name: seriesName ?? name,
            kind: .series,
            overview: nil,
            year: year,
            runtime: nil,
            officialRating: officialRating,
            genres: genres,
            seriesName: seriesName,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: unplayedCount,
            isPlayed: false,
            primaryImageTag: nil,
            thumbImageTag: seriesThumbImageTag,
            backdropImageTag: nil,
            backdropImageTags: [],
            logoImageTag: nil,
            parentBackdropItemID: parentBackdropItemID ?? showID,
            parentThumbItemID: parentThumbItemID ?? showID,
            parentThumbImageTag: parentThumbImageTag ?? seriesThumbImageTag,
            parentLogoItemID: parentLogoItemID ?? showID,
            parentLogoImageTag: parentLogoImageTag,
            seriesThumbImageTag: seriesThumbImageTag,
            seriesID: showID,
            imageItemID: parentBackdropItemID ?? showID,
            queueKind: queueKind,
            videoRange: .sdr,
            audioFormat: .unknown,
            criticRating: criticRating,
            videoResolution: .unknown,
            hasClosedCaptions: false,
            hasAudioDescription: false,
            tmdbID: tmdbID,
            isFavorite: isFavorite,
            likes: likes,
            premiereDate: premiereDate,
            posterURL: posterURL,
            backdropURL: backdropURL
        )
    }

    var hasHeroBackdrop: Bool {
        backdropURL != nil || backdropImageTag != nil || !backdropImageTags.isEmpty || parentBackdropItemID != nil
    }

    var hasGenreCoverArt: Bool {
        hasHeroBackdrop
            || posterURL != nil
            || thumbImageTag != nil
            || primaryImageTag != nil
    }

    var continueWatchingTitle: String {
        if kind == .episode {
            return seriesName ?? name
        }
        return name
    }

    var browsingCardTitle: String {
        guard kind == .collection else { return name }
        return Self.strippingCollectionSuffix(name)
    }

    static func strippingCollectionSuffix(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: " Collection", options: [.backwards, .caseInsensitive]),
              range.upperBound == trimmed.endIndex
        else {
            return trimmed
        }
        return trimmed[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var recentlyWatchedCaption: String? {
        if kind == .episode, let seasonIndex, let episodeIndex {
            if let runtime {
                return "S\(seasonIndex), E\(episodeIndex)  ·  \(Self.minutesLabel(runtime))"
            }
            return "S\(seasonIndex), E\(episodeIndex)"
        }
        var parts: [String] = []
        if let year {
            parts.append("\(year)")
        }
        if let runtime {
            parts.append(Self.minutesLabel(runtime))
        }
        return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
    }

    var recentlyWatchedListSubtitle: String {
        var parts: [String] = []
        if kind == .episode, let seasonIndex, let episodeIndex {
            parts.append("S\(seasonIndex), E\(episodeIndex)")
        } else if let year {
            parts.append("\(year)")
        }
        if let runtime {
            parts.append(Self.minutesLabel(runtime).uppercased())
        }
        return parts.joined(separator: "  ·  ")
    }

    var continueWatchingListSubtitle: String {
        var parts = [queueKind.listStatusLabel]
        if kind == .episode, let seasonIndex, let episodeIndex {
            parts.append("S\(seasonIndex), E\(episodeIndex)")
        }
        if let remainingPlayback, remainingPlayback > 0 {
            parts.append("\(Self.minutesLabel(remainingPlayback, rounding: .down).uppercased()) LEFT")
        }
        return parts.joined(separator: "  ·  ")
    }

    var showsResumeProgress: Bool {
        progress > 0.02 && progress < 0.98
    }

    /// Finished in Jellyfin, or played through to the end when `Played` was not set.
    var isWatched: Bool {
        isPlayed || progress >= 0.98
    }

    var kindLabel: String {
        switch kind {
        case .movie: "Movie"
        case .series, .season, .episode: "Show"
        case .collection: "Collection"
        case .genre: "Genre"
        case .playlist: "Playlist"
        case .liveTV: "Live TV"
        case .book: "Book"
        case .photo: "Photo"
        case .unknown: "Title"
        }
    }

    /// Jellyfin seasons store the number in `IndexNumber`; older snapshots may still have it on `episodeIndex`.
    var resolvedSeasonNumber: Int? {
        if kind == .season {
            return seasonIndex ?? episodeIndex
        }
        return seasonIndex
    }

    var seasonMenuTitle: String {
        guard let number = resolvedSeasonNumber else { return name }
        return SeasonDownloadChoice.seasonTitle(number)
    }

    var episodeOrdinalLabel: String? {
        guard kind == .episode, let episodeIndex else { return nil }
        return "EPISODE \(episodeIndex)"
    }

    static func orderedSeasons(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { lhs, rhs in
            lhs.seasonSortKey < rhs.seasonSortKey
        }
    }

    static func orderedEpisodes(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { ($0.episodeIndex ?? Int.max) < ($1.episodeIndex ?? Int.max) }
    }

    static func orderedShowEpisodes(_ episodes: [MediaItem], seasons: [MediaItem]) -> [MediaItem] {
        let rank = Dictionary(
            uniqueKeysWithValues: seasons.enumerated().compactMap { index, season -> (Int, Int)? in
                season.resolvedSeasonNumber.map { ($0, index) }
            }
        )
        return episodes.sorted { lhs, rhs in
            let left = rank[lhs.seasonIndex ?? Int.min] ?? Int.max
            let right = rank[rhs.seasonIndex ?? Int.min] ?? Int.max
            if left != right { return left < right }
            return (lhs.episodeIndex ?? Int.max) < (rhs.episodeIndex ?? Int.max)
        }
    }

    private var seasonSortKey: Int {
        let number = resolvedSeasonNumber ?? Int.max
        if number == 0 { return Int.max - 1 }
        return number
    }

    var heroMetadataLine: String {
        var parts = [kindLabel]
        parts.append(contentsOf: Array(genres.prefix(2)))
        return parts.joined(separator: "  ·  ")
    }

    var searchListSubtitle: String {
        var parts = [kindLabel]
        if let genre = genres.first, !genre.isEmpty {
            parts.append(genre)
        }
        if let year {
            parts.append("\(year)")
        }
        return parts.joined(separator: " · ")
    }

    static func minutesLabel(
        _ interval: TimeInterval,
        rounding: FloatingPointRoundingRule = .toNearestOrAwayFromZero
    ) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded(rounding)))
        if totalMinutes < 60 {
            return "\(max(1, totalMinutes))m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(minutes)m"
    }

    func withCover(from cover: MediaItem) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: overview,
            year: year,
            runtime: runtime,
            officialRating: officialRating,
            genres: genres,
            seriesName: seriesName,
            seasonIndex: seasonIndex,
            episodeIndex: episodeIndex,
            playbackPosition: playbackPosition,
            unplayedCount: unplayedCount,
            isPlayed: isPlayed,
            primaryImageTag: cover.primaryImageTag,
            thumbImageTag: cover.thumbImageTag,
            backdropImageTag: cover.backdropImageTags.randomElement() ?? cover.backdropImageTag,
            backdropImageTags: cover.backdropImageTags,
            logoImageTag: cover.logoImageTag,
            parentBackdropItemID: cover.parentBackdropItemID,
            parentThumbItemID: cover.parentThumbItemID,
            parentThumbImageTag: cover.parentThumbImageTag,
            parentLogoItemID: cover.parentLogoItemID,
            parentLogoImageTag: cover.parentLogoImageTag,
            seriesThumbImageTag: cover.seriesThumbImageTag,
            seriesID: seriesID,
            imageItemID: cover.id,
            queueKind: queueKind,
            videoRange: videoRange,
            audioFormat: audioFormat,
            criticRating: criticRating,
            videoResolution: videoResolution,
            hasClosedCaptions: hasClosedCaptions,
            hasAudioDescription: hasAudioDescription,
            sourceBitrate: sourceBitrate,
            tmdbID: tmdbID,
            isFavorite: isFavorite,
            likes: likes,
            premiereDate: premiereDate,
            posterURL: cover.posterURL,
            backdropURL: cover.backdropURL,
            logoURL: cover.logoURL
        )
    }

    func withFavorite(_ value: Bool) -> MediaItem {
        var copy = self
        copy.isFavorite = value
        return copy
    }

    func withWatchlisted(_ value: Bool) -> MediaItem {
        var copy = self
        copy.isWatchlisted = value
        return copy
    }

    func withLikes(_ value: Bool?) -> MediaItem {
        var copy = self
        copy.likes = value
        return copy
    }

    static func liveChannelStub(
        id: String,
        name: String,
        primaryImageTag: String? = nil,
        overview: String? = nil,
        parentBackdropItemID: String? = nil,
        backdropImageTag: String? = nil,
        imageItemID: String? = nil
    ) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: .liveTV,
            overview: overview,
            year: nil,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: primaryImageTag,
            thumbImageTag: nil,
            backdropImageTag: backdropImageTag,
            backdropImageTags: backdropImageTag.map { [$0] } ?? [],
            logoImageTag: nil,
            parentBackdropItemID: parentBackdropItemID,
            parentThumbItemID: nil,
            parentThumbImageTag: nil,
            parentLogoItemID: nil,
            parentLogoImageTag: nil,
            seriesThumbImageTag: nil,
            seriesID: nil,
            imageItemID: imageItemID,
            queueKind: .resume,
            videoRange: .sdr,
            audioFormat: .unknown
        )
    }
}

/// One season the user can tick in the show download action sheet.
struct SeasonDownloadChoice: Identifiable, Hashable, Sendable {
    var id: String { seasonIndex.map(String.init) ?? "all" }
    let title: String
    let seasonIndex: Int?

    static func options(seasons: [MediaItem], episodes: [MediaItem]) -> [SeasonDownloadChoice] {
        let numbers = seasonNumbers(seasons: seasons, episodes: episodes)
        if numbers.isEmpty {
            return episodes.contains(where: { $0.kind == .episode })
                ? [SeasonDownloadChoice(title: "All Episodes", seasonIndex: nil)]
                : []
        }
        return numbers.map { SeasonDownloadChoice(title: seasonTitle($0), seasonIndex: $0) }
    }

    static func episodes(for choice: SeasonDownloadChoice, in episodes: [MediaItem], seasons: [MediaItem] = []) -> [MediaItem] {
        if let number = choice.seasonIndex {
            return Self.episodes(in: episodes, seasons: seasons, indexes: [number])
        }
        return Self.episodes(in: episodes, seasons: seasons, indexes: nil)
    }

    static func episodes(in episodes: [MediaItem], seasons: [MediaItem] = [], indexes: Set<Int>?) -> [MediaItem] {
        let playable = episodes.filter { $0.kind == .episode }
        let scoped = indexes.map { numbers in playable.filter { item in item.seasonIndex.map(numbers.contains) ?? false } } ?? playable
        return MediaItem.orderedShowEpisodes(scoped, seasons: seasons)
    }

    static func seasonTitle(_ number: Int) -> String {
        number == 0 ? "Specials" : "Season \(number)"
    }

    private static func seasonNumbers(seasons: [MediaItem], episodes: [MediaItem]) -> [Int] {
        let fromEpisodes = Set(episodes.compactMap(\.seasonIndex))
        let fromSeasons = Set(seasons.compactMap(\.resolvedSeasonNumber))
        let numbers = fromEpisodes.isEmpty ? fromSeasons : fromEpisodes
        return numbers.sorted { lhs, rhs in
            let left = lhs == 0 ? Int.max : lhs
            let right = rhs == 0 ? Int.max : rhs
            return left < right
        }
    }
}

enum LibraryKind: String, Hashable, Sendable, Codable, CaseIterable {
    case movies
    case shows
    case music
    case books
    case photos
    case liveTV
    case playlists
    case homeVideos
    case collections
    case favorites
    case watchlist
    case other

    var appearsOnHome: Bool {
        switch self {
        case .movies, .shows:
            true
        default:
            false
        }
    }

    var appearsInLibrary: Bool {
        switch self {
        case .music, .books, .playlists, .favorites, .watchlist:
            false
        default:
            true
        }
    }

    var browseLabel: String {
        switch self {
        case .movies: "Movies"
        case .shows: "Shows"
        case .music: "Music"
        case .books: "Books"
        case .photos: "Photos"
        case .liveTV: "Live TV"
        case .playlists: "Playlists"
        case .homeVideos: "Home videos"
        case .collections: "Collections"
        case .favorites: "Favorites"
        case .watchlist: "Watchlist"
        case .other: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .movies: "film"
        case .shows: "tv"
        case .music: "music.note"
        case .books: "book"
        case .photos: "photo"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .playlists: "list.bullet.rectangle"
        case .homeVideos: "video"
        case .collections: "square.grid.2x2.fill"
        case .favorites: "heart.fill"
        case .watchlist: "text.badge.plus"
        case .other: "rectangle.stack"
        }
    }

    func recentlyAddedTitle(libraryName: String) -> String {
        switch self {
        case .movies: "Recently Added Movies"
        case .shows: "Recently Added Shows"
        default: "Recently Added \(libraryName)"
        }
    }

    static func inferred(fromName name: String) -> LibraryKind? {
        let lower = name.lowercased()
        if lower.contains("movie") || lower.contains("film") {
            return .movies
        }
        if lower.contains("show") || lower.contains("series") || lower == "tv" || lower.contains("tv show") {
            return .shows
        }
        if lower.contains("collection") {
            return .collections
        }
        if lower.contains("music") {
            return .music
        }
        return nil
    }
}

enum GenreSymbol {
    static func systemImage(for name: String) -> String {
        let key = normalized(name)
        if let exact = exactSymbols[key] {
            return exact
        }
        if let matched = keywordSymbols.first(where: { key.contains($0.key) })?.value {
            return matched
        }
        return fallbackSymbol(for: name)
    }

    private static func normalized(_ name: String) -> String {
        let lowered = name.lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
        let letters = lowered.map { character -> Character in
            character.isLetter || character.isNumber || character == " " ? character : " "
        }
        let collapsed = String(letters)
            .split(separator: " ")
            .joined(separator: " ")
        return collapsed
            .replacingOccurrences(of: "science fiction", with: "scifi")
            .replacingOccurrences(of: "sci fi", with: "scifi")
    }

    private static let exactSymbols: [String: String] = [
        "action": "flame.fill",
        "action and adventure": "burst.fill",
        "adventure": "figure.hiking",
        "animation": "sparkle",
        "anime": "moon.stars.fill",
        "awards": "trophy.fill",
        "biography": "person.text.rectangle",
        "children": "teddybear.fill",
        "classic": "clock.fill",
        "comedy": "face.smiling",
        "concert": "music.mic",
        "crime": "lock.shield.fill",
        "true crime": "lock.shield.fill",
        "crime drama": "lock.shield.fill",
        "cult": "star.circle.fill",
        "cyberpunk": "cpu.fill",
        "dark comedy": "cloud.moon.fill",
        "disaster": "hurricane",
        "documentary": "photo.on.rectangle.angled",
        "drama": "text.book.closed.fill",
        "education": "graduationcap.fill",
        "faith": "heart.circle.fill",
        "family": "figure.2.and.child.holdinghands",
        "fantasy": "wand.and.stars",
        "film noir": "moon.fill",
        "food": "fork.knife",
        "foreign": "globe",
        "game show": "gamecontroller.fill",
        "historical": "building.columns.fill",
        "history": "building.columns.fill",
        "holiday": "gift.fill",
        "home and garden": "leaf.fill",
        "horror": "theatermasks.fill",
        "independent": "film",
        "indie": "film",
        "kids": "balloon.2.fill",
        "kids and family": "balloon.2.fill",
        "legal": "hammer.fill",
        "lgbt": "rainbow",
        "lgbtq": "rainbow",
        "martial arts": "figure.martial.arts",
        "medical": "cross.case.fill",
        "miniseries": "rectangle.stack.fill",
        "music": "music.note",
        "musical": "music.quarternote.3",
        "mystery": "magnifyingglass",
        "nature": "tree.fill",
        "news": "newspaper.fill",
        "noir": "moon.fill",
        "paranormal": "eye.trianglebadge.exclamationmark",
        "politics": "building.columns",
        "reality": "video.fill",
        "religion": "book.closed.fill",
        "romance": "heart.fill",
        "romantic comedy": "heart.circle.fill",
        "satire": "quote.bubble.fill",
        "science": "atom",
        "scifi": "sparkles",
        "scifi and fantasy": "sparkles",
        "short": "timer",
        "sitcom": "tv.fill",
        "soap": "drop.fill",
        "special": "star.fill",
        "sport": "sportscourt.fill",
        "sports": "sportscourt.fill",
        "spy": "binoculars.fill",
        "stand up": "mic.fill",
        "superhero": "bolt.shield.fill",
        "suspense": "eye.fill",
        "talk": "bubble.left.and.bubble.right.fill",
        "teen": "person.2.fill",
        "thriller": "bolt.fill",
        "travel": "airplane",
        "tv movie": "play.tv.fill",
        "vampire": "moon.haze.fill",
        "war": "shield.fill",
        "war and politics": "shield.lefthalf.filled",
        "western": "sun.horizon.fill",
        "zombie": "figure.walk"
    ]

    private static let keywordSymbols: [(key: String, value: String)] = [
        ("martial arts", "figure.martial.arts"),
        ("action and adventure", "burst.fill"),
        ("kids and family", "balloon.2.fill"),
        ("romantic comedy", "heart.circle.fill"),
        ("dark comedy", "cloud.moon.fill"),
        ("stand up", "mic.fill"),
        ("game show", "gamecontroller.fill"),
        ("home and garden", "leaf.fill"),
        ("film noir", "moon.fill"),
        ("scifi and fantasy", "sparkles"),
        ("war and politics", "shield.lefthalf.filled"),
        ("documentary", "photo.on.rectangle.angled"),
        ("biography", "person.text.rectangle"),
        ("animation", "sparkle"),
        ("adventure", "figure.hiking"),
        ("thriller", "bolt.fill"),
        ("suspense", "eye.fill"),
        ("superhero", "bolt.shield.fill"),
        ("fantasy", "wand.and.stars"),
        ("mystery", "magnifyingglass"),
        ("western", "sun.horizon.fill"),
        ("romance", "heart.fill"),
        ("romantic", "heart.fill"),
        ("horror", "theatermasks.fill"),
        ("comedy", "face.smiling"),
        ("family", "figure.2.and.child.holdinghands"),
        ("children", "teddybear.fill"),
        ("kids", "balloon.2.fill"),
        ("anime", "moon.stars.fill"),
        ("true crime", "lock.shield.fill"),
        ("crime drama", "lock.shield.fill"),
        ("crime", "lock.shield.fill"),
        ("drama", "text.book.closed.fill"),
        ("action", "flame.fill"),
        ("history", "building.columns.fill"),
        ("historical", "building.columns.fill"),
        ("musical", "music.quarternote.3"),
        ("music", "music.note"),
        ("sports", "sportscourt.fill"),
        ("sport", "sportscourt.fill"),
        ("news", "newspaper.fill"),
        ("reality", "video.fill"),
        ("scifi", "sparkles"),
        ("science", "atom"),
        ("nature", "tree.fill"),
        ("travel", "airplane"),
        ("holiday", "gift.fill"),
        ("christmas", "gift.fill"),
        ("food", "fork.knife"),
        ("legal", "hammer.fill"),
        ("medical", "cross.case.fill"),
        ("politics", "building.columns"),
        ("war", "shield.fill"),
        ("spy", "binoculars.fill"),
        ("teen", "person.2.fill"),
        ("talk", "bubble.left.and.bubble.right.fill"),
        ("soap", "drop.fill"),
        ("sitcom", "tv.fill"),
        ("concert", "music.mic"),
        ("awards", "trophy.fill"),
        ("education", "graduationcap.fill"),
        ("faith", "heart.circle.fill"),
        ("religion", "book.closed.fill"),
        ("foreign", "globe"),
        ("independent", "film"),
        ("classic", "clock.fill"),
        ("short", "timer"),
        ("zombie", "figure.walk"),
        ("vampire", "moon.haze.fill"),
        ("paranormal", "eye.trianglebadge.exclamationmark"),
        ("disaster", "hurricane"),
        ("cyberpunk", "cpu.fill")
    ]

    private static let fallbackSymbols = [
        "tag.fill",
        "star.square.fill",
        "hexagon.fill",
        "rhombus.fill",
        "seal.fill",
        "pentagon.fill",
        "diamond.fill",
        "octagon.fill",
        "triangle.fill",
        "capsule.fill",
        "oval.fill",
        "button.programmable",
        "app.fill",
        "circle.hexagongrid.fill",
        "square.on.circle.fill"
    ]

    private static func fallbackSymbol(for name: String) -> String {
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) &* 37 }
        return fallbackSymbols[abs(hash) % fallbackSymbols.count]
    }
}

struct MediaLibrary: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let kind: MediaKind
    let libraryKind: LibraryKind
}

struct HomeSection: Identifiable, Hashable, Sendable, Codable {
    enum Style: String, Hashable, Sendable, Codable {
        case landscape
        case portrait
        case ranked
        case labeledPortrait
        case replayLandscape
    }

    let id: String
    let title: String
    let style: Style
    let items: [MediaItem]

    var showsChevron: Bool {
        style != .labeledPortrait
    }

    var isCatalogBrowse: Bool {
        id == "genres" || id == "collections"
    }

    var isRecentlyWatched: Bool {
        id == "recently-watched"
    }

    var isRecentlyAddedCollections: Bool {
        let title = title.lowercased()
        return title.contains("recently added") && title.contains("collection")
    }
}

struct HomeLayout: Hashable, Sendable, Codable {
    var featured: [MediaItem]
    var sections: [HomeSection]

    func replacing(_ item: MediaItem) -> HomeLayout {
        HomeLayout(
            featured: featured.map { $0.id == item.id ? item : $0 },
            sections: sections.map { section in
                HomeSection(
                    id: section.id,
                    title: section.title,
                    style: section.style,
                    items: section.items.map { $0.id == item.id ? item : $0 }
                )
            }
        )
    }
}

struct CreditPerson: Identifiable, Hashable, Sendable, Codable {
    let id: String
    let name: String
    let roleLabel: String
    let imageTag: String?
    let rank: Int
    var overview: String? = nil
    var birthYear: Int? = nil
    var imageURL: URL? = nil
}

struct TitleExtra: Identifiable, Hashable, Sendable, Codable {
    let item: MediaItem
    let caption: String

    var id: String { item.id }
    var title: String { item.name }
}

struct MediaChapter: Identifiable, Hashable, Sendable, Codable {
    var id: Int { index }
    let index: Int
    let name: String
    let startTime: TimeInterval
    let imageTag: String?
}

struct MediaVersion: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

struct TrickplayInfo: Hashable, Sendable {
    let width: Int
    let interval: TimeInterval
    let thumbnailCount: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailWidth: Int
    let thumbnailHeight: Int
    let mediaSourceID: String?

    var thumbnailsPerTile: Int { max(1, tileWidth * tileHeight) }

    func thumbnailIndex(at time: TimeInterval) -> Int {
        guard interval > 0 else { return 0 }
        return min(max(0, Int(time / interval)), max(0, thumbnailCount - 1))
    }

    func tileIndex(at time: TimeInterval) -> Int {
        thumbnailIndex(at: time) / thumbnailsPerTile
    }

    func cell(at time: TimeInterval) -> (column: Int, row: Int) {
        let local = thumbnailIndex(at: time) % thumbnailsPerTile
        return (local % max(tileWidth, 1), local / max(tileWidth, 1))
    }
}

struct LibrarySearchHit: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case title(MediaKind)
        case person
        case genre
        case studio
    }

    let id: String
    let name: String
    let kind: Kind
    let subtitle: String?
    let year: Int?
    let imageTag: String?
    let imageURL: URL?

    init(
        id: String,
        name: String,
        kind: Kind,
        subtitle: String?,
        year: Int?,
        imageTag: String?,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.subtitle = subtitle
        self.year = year
        self.imageTag = imageTag
        self.imageURL = imageURL
    }

    func recentItem(kind: MediaKind) -> MediaItem {
        MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: nil,
            year: year,
            runtime: nil,
            officialRating: nil,
            genres: [],
            seriesName: nil,
            seasonIndex: nil,
            episodeIndex: nil,
            playbackPosition: 0,
            unplayedCount: nil,
            isPlayed: false,
            primaryImageTag: imageTag,
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
}

struct ItemCollectionMembership: Identifiable, Hashable, Sendable, Codable {
    var id: String { collection.id }
    let collection: MediaItem
    let items: [MediaItem]
}

struct MediaTrack: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case audio
        case subtitle
    }

    let id: Int
    let kind: Kind
    let language: String?
    let title: String
    let codec: String?
    let isSelected: Bool
    let isDefault: Bool
}

struct PlaybackPlan: Hashable, Sendable {
    let item: MediaItem
    let streamURL: URL
    let playSessionID: String?
    let mediaSourceID: String?
    let method: PlaybackMethod
    let container: String
    let videoCodec: String?
    let videoRange: VideoRange
    let audioFormat: AudioFormat
    let startTime: TimeInterval
    let byteSize: Int64?
    let extraHTTPHeaders: [String: String]
    let audioTracks: [MediaTrack]
    let subtitleTracks: [MediaTrack]
    var externalSubtitles: [ExternalSubtitleSidecar] = []
    var chapters: [MediaChapter] = []
    var trickplay: TrickplayInfo? = nil
    var versions: [MediaVersion] = []
    var isLive: Bool = false
    var liveStreamID: String? = nil
    /// Full-file remux (Silo `original_http`) keeps the playhead on the client.
    var clientOwnsPlayhead: Bool = false
}

struct ExternalSubtitleSidecar: Hashable, Sendable {
    let url: URL
    let name: String
    let language: String?
    let formatHint: String
    let isForced: Bool
    let isHearingImpaired: Bool
}

struct TitleTrailer: Identifiable, Hashable, Sendable, Codable {
    enum Kind: Hashable, Sendable, Codable {
        case youtube(String)
        case vimeo(String)
        case jellyfin(MediaItem)
        case catalog(URL)
    }

    let id: String
    let title: String
    let kind: Kind

    var caption: String {
        switch kind {
        case .youtube, .vimeo:
            return "Trailer"
        case .jellyfin:
            return "From your server"
        case .catalog(let url):
            let host = (url.host ?? "").lowercased()
            if host.contains("imdb") { return "IMDb" }
            if host.contains("themoviedb") { return "TMDB" }
            return "Trailer"
        }
    }

    var trailerRank: Int {
        let name = title.lowercased()
        if name.contains("official") && name.contains("trailer") { return 0 }
        if name.contains("trailer") { return 1 }
        if name.contains("teaser") { return 2 }
        return 3
    }

    var isOfficialTrailer: Bool {
        Self.isOfficialTrailer(title: title)
    }

    /// Trailers only — not teasers, clips, featurettes, or other extras.
    static func isOfficialTrailer(title: String, type: String? = nil, official: Bool? = nil) -> Bool {
        if official == false { return false }
        if let type {
            let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalized.isEmpty, normalized != "trailer" { return false }
        }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.isEmpty { return true }
        let extras = [
            "teaser", "clip", "featurette", "behind the scenes", "blooper",
            "interview", "deleted", "sneak peek", "promo", "spot", "excerpt",
            "scene", "endboard", "announcement"
        ]
        if extras.contains(where: { name.contains($0) }) { return false }
        return name.contains("trailer")
    }

    var jellyfinItem: MediaItem? {
        if case .jellyfin(let item) = kind { return item }
        return nil
    }

    var thumbnailURL: URL? {
        switch kind {
        case .youtube(let videoID):
            return URL(string: "https://i.ytimg.com/vi/\(videoID)/mqdefault.jpg")
        case .vimeo, .jellyfin, .catalog:
            return nil
        }
    }

    var externalWatchURL: URL? {
        switch kind {
        case .youtube(let videoID):
            return URL(string: "https://www.youtube.com/watch?v=\(videoID)")
        case .vimeo(let videoID):
            return URL(string: "https://vimeo.com/\(videoID)")
        case .catalog(let url):
            return url
        case .jellyfin:
            return nil
        }
    }

    static func youtube(id: String, title: String) -> TitleTrailer {
        TitleTrailer(id: "yt-\(id)", title: title, kind: .youtube(id))
    }

    static func vimeo(id: String, title: String) -> TitleTrailer {
        TitleTrailer(id: "vimeo-\(id)", title: title, kind: .vimeo(id))
    }

    static func jellyfin(_ item: MediaItem) -> TitleTrailer {
        TitleTrailer(id: "jf-\(item.id)", title: item.name, kind: .jellyfin(item))
    }

    /// Remote trailer URL from Jellyfin metadata (TMDb / NFO), usually YouTube.
    static func jellyfinRemote(url: String, title: String) -> TitleTrailer? {
        if let youtubeID = TrailerLinkParser.youtubeVideoID(from: url) {
            return .youtube(id: youtubeID, title: title)
        }
        if let vimeoID = TrailerLinkParser.vimeoVideoID(from: url) {
            return .vimeo(id: vimeoID, title: title)
        }
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return TitleTrailer(id: "web-\(url)", title: title, kind: .catalog(parsed))
    }

    static func tmdbPage(id: Int, isSeries: Bool) -> TitleTrailer {
        let path = isSeries ? "tv" : "movie"
        let url = URL(string: "https://www.themoviedb.org/\(path)/\(id)")!
        return TitleTrailer(id: "tmdb-\(id)", title: "Trailer", kind: .catalog(url))
    }

    static func imdbPage(id: String) -> TitleTrailer {
        let url = URL(string: "https://www.imdb.com/title/\(id)/")!
        return TitleTrailer(id: "imdb-\(id)", title: "Trailer", kind: .catalog(url))
    }
}

enum TrailerLinkParser {
    static func youtubeVideoID(from raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&amp;", with: "&")
        if isYouTubeID(trimmed) { return trimmed }
        if trimmed.lowercased().hasPrefix("plugin://plugin.video.youtube"),
           let videoID = kodiYouTubeID(from: trimmed)
        {
            return videoID
        }
        guard let url = URL(string: trimmed) else { return nil }
        let host = (url.host ?? "").lowercased()

        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            let id = url.path.split(separator: "/").first.map(String.init)
            return validatedYouTubeID(id)
        }

        let isYouTubeHost = host == "youtube.com"
            || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com"
            || host.hasSuffix(".youtube-nocookie.com")
        guard isYouTubeHost else { return nil }

        if let videoID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "v" })?
            .value
        {
            return validatedYouTubeID(videoID)
        }

        let parts = url.path.split(separator: "/").map(String.init)
        if let marker = parts.firstIndex(where: { ["embed", "v", "shorts", "live", "e"].contains($0.lowercased()) }),
           marker + 1 < parts.count
        {
            return validatedYouTubeID(parts[marker + 1])
        }
        return nil
    }

    static func vimeoVideoID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else { return nil }
        let host = (url.host ?? "").lowercased()
        guard host == "vimeo.com" || host.hasSuffix(".vimeo.com") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if let marker = parts.firstIndex(where: { $0.lowercased() == "video" }),
           marker + 1 < parts.count,
           isVimeoID(parts[marker + 1])
        {
            return parts[marker + 1]
        }
        if let last = parts.last, isVimeoID(last) {
            return last
        }
        return nil
    }

    /// Jellyfin NFO / Kodi YouTube plugin URLs stored as remote trailers.
    private static func kodiYouTubeID(from raw: String) -> String? {
        guard let components = URLComponents(string: raw) else { return nil }
        let items = components.queryItems ?? []
        for name in ["videoid", "video_id", "v"] {
            if let value = items.first(where: { $0.name.lowercased() == name })?.value {
                return validatedYouTubeID(value)
            }
        }
        return nil
    }

    private static func validatedYouTubeID(_ value: String?) -> String? {
        guard let value else { return nil }
        let id = value.split(whereSeparator: { $0 == "?" || $0 == "&" }).first.map(String.init) ?? value
        return isYouTubeID(id) ? id : nil
    }

    private static func isYouTubeID(_ value: String) -> Bool {
        value.count == 11 && value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    private static func isVimeoID(_ value: String) -> Bool {
        value.count >= 5 && value.count <= 12 && value.allSatisfy(\.isNumber)
    }
}
