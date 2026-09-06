import Foundation

enum MediaKind: String, Hashable, Sendable, Codable {
    case movie
    case series
    case season
    case episode
    case collection
    case genre
    case unknown
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
    let playbackPosition: TimeInterval
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
            remaining = " · \(Self.minutesLabel(leftover))"
        } else {
            remaining = ""
        }
        return "S\(seasonIndex), E\(episodeIndex)\(remaining)"
    }

    var remainingPlayback: TimeInterval? {
        guard let runtime, runtime > 0 else { return nil }
        return max(0, runtime - playbackPosition)
    }

    var continueWatchingCaption: String? {
        let remaining = remainingPlayback.map(Self.minutesLabel)
        if kind == .episode, let seasonIndex, let episodeIndex {
            if let remaining {
                return "S\(seasonIndex), E\(episodeIndex) · \(remaining)"
            }
            return "S\(seasonIndex), E\(episodeIndex)"
        }
        return remaining
    }

    var artworkItemID: String { imageItemID ?? id }

    var hasGenreCoverArt: Bool {
        !backdropImageTags.isEmpty
            || backdropImageTag != nil
            || parentBackdropItemID != nil
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
            parts.append("\(Self.minutesLabel(remainingPlayback).uppercased()) LEFT")
        }
        return parts.joined(separator: "  ·  ")
    }

    var showsResumeProgress: Bool {
        progress > 0.02 && progress < 0.98
    }

    var kindLabel: String {
        switch kind {
        case .movie: "Movie"
        case .series, .season, .episode: "Show"
        case .collection: "Collection"
        case .genre: "Genre"
        case .unknown: "Title"
        }
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

    private static func minutesLabel(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int((interval / 60).rounded()))
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
            audioFormat: audioFormat
        )
    }
}

enum LibraryKind: String, Hashable, Sendable, Codable {
    case movies
    case shows
    case music
    case books
    case photos
    case liveTV
    case playlists
    case homeVideos
    case collections
    case other

    var appearsOnHome: Bool {
        switch self {
        case .music, .books, .photos, .liveTV, .playlists, .collections:
            false
        case .movies, .shows, .homeVideos, .other:
            true
        }
    }

    var appearsInLibrary: Bool {
        switch self {
        case .movies, .shows, .other, .liveTV:
            true
        case .music, .books, .photos, .playlists, .homeVideos, .collections:
            false
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
        return nil
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
    let videoRange: VideoRange
    let audioFormat: AudioFormat
    let startTime: TimeInterval
    let byteSize: Int64?
    let extraHTTPHeaders: [String: String]
    let audioTracks: [MediaTrack]
    let subtitleTracks: [MediaTrack]
}
