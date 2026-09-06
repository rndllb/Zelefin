import Foundation
import JellyfinAPI

enum ItemMapper {
    static let listImageTypes: [ImageType] = [.primary, .thumb, .backdrop, .logo]

    static let homeFields: [ItemFields] = [
        .primaryImageAspectRatio
    ]

    static let listFields: [ItemFields] = [
        .overview,
        .genres,
        .primaryImageAspectRatio
    ]

    static let detailFields: [ItemFields] = [
        .mediaStreams,
        .mediaSources,
        .overview,
        .genres,
        .chapters,
        .trickplay,
        .primaryImageAspectRatio
    ]

    static func mediaItem(from dto: BaseItemDto) -> MediaItem? {
        mediaItem(from: dto, queueKind: .resume)
    }

    static func mediaItem(from dto: BaseItemDto, queueKind: PlaybackQueueKind) -> MediaItem? {
        guard let id = dto.id, let name = dto.name, let kind = kind(from: dto.type) else { return nil }

        return MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: dto.overview,
            year: dto.productionYear,
            runtime: dto.runTimeTicks.map(TickClock.seconds(from:)),
            officialRating: dto.officialRating,
            genres: dto.genres ?? [],
            seriesName: dto.seriesName,
            seasonIndex: dto.parentIndexNumber,
            episodeIndex: dto.indexNumber,
            playbackPosition: TickClock.seconds(from: dto.userData?.playbackPositionTicks ?? 0),
            unplayedCount: dto.userData?.unplayedItemCount,
            isPlayed: dto.userData?.isPlayed ?? false,
            primaryImageTag: primaryTag(from: dto),
            thumbImageTag: imageTag(from: dto, named: "Thumb"),
            backdropImageTag: dto.backdropImageTags?.first,
            backdropImageTags: dto.backdropImageTags ?? [],
            logoImageTag: imageTag(from: dto, named: "Logo"),
            parentBackdropItemID: dto.parentBackdropItemID,
            parentThumbItemID: dto.parentThumbItemID,
            parentThumbImageTag: dto.parentThumbImageTag,
            parentLogoItemID: dto.parentLogoItemID,
            parentLogoImageTag: dto.parentLogoImageTag,
            seriesThumbImageTag: dto.seriesThumbImageTag,
            seriesID: dto.seriesID,
            imageItemID: nil,
            queueKind: queueKind,
            videoRange: videoRange(from: dto.mediaStreams),
            audioFormat: audioFormat(from: dto.mediaStreams)
        )
    }

    static func library(from dto: BaseItemDto) -> MediaLibrary? {
        guard let id = dto.id, let name = dto.name else { return nil }
        let libraryKind = libraryKind(from: dto.collectionType, name: name)
        return MediaLibrary(
            id: id,
            name: name,
            kind: mediaKind(from: libraryKind),
            libraryKind: libraryKind
        )
    }

    static func tracks(from streams: [MediaStream]?, kind: MediaTrack.Kind) -> [MediaTrack] {
        let wanted: MediaStreamType = kind == .audio ? .audio : .subtitle
        return (streams ?? []).compactMap { stream in
            guard stream.type == wanted, let index = stream.index else { return nil }
            return MediaTrack(
                id: index,
                kind: kind,
                language: stream.language,
                title: stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(index)",
                codec: stream.codec,
                isSelected: stream.isDefault == true,
                isDefault: stream.isDefault ?? false
            )
        }
    }

    static func videoRange(from streams: [MediaStream]?) -> VideoRange {
        guard let video = streams?.first(where: { $0.type == .video }) else { return .sdr }
        let range = video.videoRangeType.map { String(describing: $0).lowercased() } ?? ""

        if range.contains("dovi") || range.contains("dolby") {
            return .dolbyVision
        }
        if range.contains("hdr10+") || range.contains("hdr10plus") {
            return .hdr10Plus
        }
        if range.contains("hdr10") || range.contains("hdr") {
            return .hdr10
        }
        if range.contains("hlg") {
            return .hlg
        }
        return .sdr
    }

    static func audioFormat(from streams: [MediaStream]?) -> AudioFormat {
        let audioStreams = (streams ?? []).filter { $0.type == .audio }
        let joined = audioStreams
            .compactMap { [$0.codec, $0.channelLayout, $0.title, $0.displayTitle].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: " ")
            .lowercased()

        if joined.contains("atmos") || joined.contains("joc") || joined.contains("eac3") && joined.contains("atmos") {
            return .atmos
        }
        if audioStreams.contains(where: { ($0.channels ?? 0) >= 6 }) {
            return .surround
        }
        if audioStreams.isEmpty {
            return .unknown
        }
        return .stereo
    }

    static func playbackMethod(from source: MediaSourceInfo) -> PlaybackMethod {
        if source.transcodingURL != nil {
            if source.isSupportsDirectStream == true {
                return .remux
            }
            return .transcode
        }
        return .directPlay
    }

    private static func kind(from type: BaseItemKind?) -> MediaKind? {
        switch type {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .boxSet: .collection
        case .genre: .genre
        case .collectionFolder, .userView, .userRootFolder, .aggregateFolder, .basePluginFolder:
            nil
        default: .unknown
        }
    }

    private static func libraryKind(from collectionType: CollectionType?, name: String) -> LibraryKind {
        switch collectionType {
        case .movies: .movies
        case .tvshows: .shows
        case .music: .music
        case .books: .books
        case .photos: .photos
        case .livetv: .liveTV
        case .playlists: .playlists
        case .homevideos: .homeVideos
        case .boxsets: .collections
        default: LibraryKind.inferred(fromName: name) ?? .other
        }
    }

    private static func mediaKind(from libraryKind: LibraryKind) -> MediaKind {
        switch libraryKind {
        case .movies: .movie
        case .shows: .series
        default: .collection
        }
    }

    private static func primaryTag(from dto: BaseItemDto) -> String? {
        imageTag(from: dto, named: "Primary") ?? dto.seriesPrimaryImageTag
    }

    private static func imageTag(from dto: BaseItemDto, named name: String) -> String? {
        guard let tags = dto.imageTags else { return nil }
        return tags[name] ?? tags[name.lowercased()]
    }
}
