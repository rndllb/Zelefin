import Foundation
import JellyfinAPI

enum ItemMapper {
    static let listImageTypes: [ImageType] = [.primary, .thumb, .backdrop, .logo]

    static let homeFields: [ItemFields] = [
        .primaryImageAspectRatio,
        .mediaStreams,
        .providerIDs,
        .width,
        .height
    ]

    static let listFields: [ItemFields] = [
        .overview,
        .genres,
        .primaryImageAspectRatio,
        .mediaStreams,
        .providerIDs,
        .width,
        .height
    ]

    static let alertFields: [ItemFields] = listFields + [.dateCreated]

    static let episodeFields: [ItemFields] = [
        .overview,
        .primaryImageAspectRatio,
        .mediaStreams,
        .providerIDs,
        .width,
        .height
    ]

    static let detailFields: [ItemFields] = [
        .mediaStreams,
        .mediaSources,
        .overview,
        .genres,
        .chapters,
        .trickplay,
        .primaryImageAspectRatio,
        .remoteTrailers,
        .localTrailerCount,
        .providerIDs,
        .people
    ]

    static func credits(from people: [BaseItemPerson]?) -> [CreditPerson] {
        guard let people else { return [] }
        let mapped = people.compactMap { person -> CreditPerson? in
            guard let id = person.id, let name = person.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
                return nil
            }
            return CreditPerson(
                id: id,
                name: name,
                roleLabel: creditRoleLabel(type: person.type, role: person.role),
                imageTag: person.primaryImageTag,
                rank: creditRank(person.type)
            )
        }
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            return false
        }
        var seen = Set<String>()
        return sorted.filter { seen.insert($0.id).inserted }
    }

    private static func creditRank(_ type: PersonKind?) -> Int {
        switch type {
        case .actor, .guestStar: 0
        case .director: 1
        case .creator: 2
        case .writer: 3
        case .producer: 4
        default: 5
        }
    }

    private static func creditRoleLabel(type: PersonKind?, role: String?) -> String {
        let trimmed = role?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        switch type {
        case .director: return "Director"
        case .writer: return "Writer"
        case .producer: return "Producer"
        case .creator: return "Creator"
        case .composer: return "Composer"
        case .guestStar: return "Guest Star"
        default: return "Cast"
        }
    }

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
            seasonIndex: kind == .season ? dto.indexNumber : dto.parentIndexNumber,
            episodeIndex: kind == .episode ? dto.indexNumber : nil,
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
            audioFormat: audioFormat(from: dto.mediaStreams),
            criticRating: dto.criticRating.map(Double.init),
            communityRating: dto.communityRating.map(Double.init),
            dateCreated: dto.dateCreated,
            lastPlayedDate: dto.userData?.lastPlayedDate,
            playCount: dto.userData?.playCount ?? 0,
            videoResolution: videoResolution(from: dto),
            hasClosedCaptions: hasClosedCaptions(from: dto.mediaStreams),
            hasAudioDescription: hasAudioDescription(from: dto.mediaStreams),
            sourceBitrate: sourceBitrate(from: dto),
            tmdbID: JellyfinTmdbCatalog.tmdbID(from: dto.providerIDs)
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

    static func sourceBitrate(from dto: BaseItemDto) -> Int? {
        if let rate = dto.mediaSources?.first?.bitrate, rate > 0 {
            return rate
        }
        if let rate = dto.mediaStreams?.first(where: { $0.type == .video })?.bitRate, rate > 0 {
            return rate
        }
        return nil
    }

    static func videoRange(from streams: [MediaStream]?) -> VideoRange {
        guard let video = streams?.first(where: { $0.type == .video }) else { return .sdr }
        let range = [
            video.videoRangeType?.rawValue,
            video.videoRange?.rawValue,
            video.colorPrimaries,
            video.colorSpace,
            video.videoRangeType.map { String(describing: $0) }
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        if range.contains("dovi") || range.contains("dolby") {
            return .dolbyVision
        }
        if range.contains("hdr10+") || range.contains("hdr10plus") {
            return .hdr10Plus
        }
        if range.contains("hdr10") || range.contains("smpte2084") || range.contains("pq") {
            return .hdr10
        }
        if range.contains("hlg") {
            return .hlg
        }
        if range.contains("hdr") || range.contains("bt2020") {
            return .hdr10
        }
        return .sdr
    }

    static func audioFormat(from streams: [MediaStream]?) -> AudioFormat {
        let audioStreams = (streams ?? []).filter { $0.type == .audio }
        let joined = audioStreams
            .compactMap { [$0.codec, $0.channelLayout, $0.title, $0.displayTitle].compactMap { $0 }.joined(separator: " ") }
            .joined(separator: " ")
            .lowercased()

        if audioStreams.contains(where: { $0.audioSpatialFormat == .dolbyAtmos }) {
            return .atmos
        }
        if joined.contains("atmos") || joined.contains("joc") || (joined.contains("eac3") && joined.contains("atmos")) {
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

    static func videoResolution(from dto: BaseItemDto) -> VideoResolution {
        let fromStreams = videoResolution(from: dto.mediaStreams)
        if fromStreams != .unknown { return fromStreams }
        return videoResolution(width: dto.width, height: dto.height)
    }

    static func videoResolution(from streams: [MediaStream]?) -> VideoResolution {
        guard let video = streams?.first(where: { $0.type == .video }) else { return .unknown }
        return videoResolution(width: video.width, height: video.height)
    }

    static func videoResolution(width: Int?, height: Int?) -> VideoResolution {
        let longEdge = max(width ?? 0, height ?? 0)
        if longEdge >= 3800 { return .fourK }
        if longEdge >= 1200 { return .hd }
        if longEdge > 0 { return .sd }
        return .unknown
    }

    static func hasClosedCaptions(from streams: [MediaStream]?) -> Bool {
        (streams ?? []).contains { $0.type == .subtitle }
    }

    static func hasAudioDescription(from streams: [MediaStream]?) -> Bool {
        (streams ?? []).contains { stream in
            guard stream.type == .audio else { return false }
            let blob = [stream.title, stream.displayTitle, stream.comment]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            return blob.contains("audio description")
                || blob.contains("described")
                || blob.contains("ad -")
                || blob.hasPrefix("ad ")
                || blob.contains(" visually")
        }
    }

    static func playbackMethod(from source: MediaSourceInfo) -> PlaybackMethod {
        playbackMethod(
            supportsDirectPlay: source.isSupportsDirectPlay,
            supportsDirectStream: source.isSupportsDirectStream,
            transcodingURL: source.transcodingURL
        )
    }

    static func playbackMethod(
        supportsDirectPlay: Bool?,
        supportsDirectStream: Bool?,
        transcodingURL: String?
    ) -> PlaybackMethod {
        if supportsDirectPlay == true {
            return .directPlay
        }
        if transcodingURL != nil {
            if supportsDirectStream == true {
                return .remux
            }
            return .transcode
        }
        return .directPlay
    }

    static func videoCodec(from streams: [MediaStream]?) -> String? {
        streams?.first(where: { $0.type == .video })?.codec
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
        imageTag(from: dto, named: "Primary")
    }

    private static func imageTag(from dto: BaseItemDto, named name: String) -> String? {
        guard let tags = dto.imageTags else { return nil }
        return tags[name] ?? tags[name.lowercased()]
    }
}
