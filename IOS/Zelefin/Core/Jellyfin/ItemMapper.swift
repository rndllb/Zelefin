import Foundation
import JellyfinAPI

enum ItemMapper {
    static let tubeArchivistProvider = "TubeArchivist"
    static let listImageTypes: [ImageType] = [.primary, .thumb, .backdrop, .logo, .banner]
    static let liveTVImageTypes: [ImageType] = [.primary, .thumb, .backdrop, .logo, .screenshot, .banner]

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

    static let liveTVFields: [ItemFields] = listFields + [.channelInfo, .airTime]

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

        let ownPrimary = primaryTag(from: dto)
        let borrowedStill = kind == .liveTV && ownPrimary == nil
        let stillItemID = borrowedStill ? (dto.parentPrimaryImageItemID ?? dto.seriesID) : nil
        let stillTag = ownPrimary ?? (borrowedStill ? (dto.parentPrimaryImageTag ?? dto.seriesPrimaryImageTag) : nil)

        return MediaItem(
            id: id,
            name: name,
            kind: kind,
            overview: overview(from: dto),
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
            primaryImageTag: stillTag,
            thumbImageTag: imageTag(from: dto, named: "Thumb") ?? imageTag(from: dto, named: "Screenshot"),
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
            imageItemID: stillItemID,
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
            tmdbID: JellyfinTmdbCatalog.tmdbID(from: dto.providerIDs),
            isFavorite: dto.userData?.isFavorite ?? false,
            likes: dto.userData?.isLikes,
            premiereDate: dto.premiereDate,
            bannerImageTag: imageTag(from: dto, named: "Banner"),
            youTubeID: youTubeID(from: dto.providerIDs)
        )
    }

    static func youTubeID(from providerIDs: [String: String]?) -> String? {
        guard let providerIDs else { return nil }
        return providerIDs.first {
            $0.key.compare(tubeArchivistProvider, options: .caseInsensitive) == .orderedSame
        }?.value
    }

    static func isTubeArchivist(_ dto: BaseItemDto) -> Bool {
        youTubeID(from: dto.providerIDs) != nil
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

    /// `source` is the user-scoped media source. Jellyfin resolves the user's audio and
    /// subtitle settings (preferred language, play default audio track, subtitle mode) into its
    /// `defaultAudioStreamIndex` / `defaultSubtitleStreamIndex`, so when it is present those win
    /// over the file's own default flags.
    static func tracks(from streams: [MediaStream]?, kind: MediaTrack.Kind, source: MediaSourceInfo? = nil) -> [MediaTrack] {
        let wanted: MediaStreamType = kind == .audio ? .audio : .subtitle
        let serverDefault: Int?? = source.map { kind == .audio ? $0.defaultAudioStreamIndex : $0.defaultSubtitleStreamIndex }
        return (streams ?? []).compactMap { stream in
            guard stream.type == wanted, let index = stream.index else { return nil }
            let isSelected: Bool
            if let serverDefault {
                isSelected = serverDefault == index
            } else {
                isSelected = stream.isDefault == true
            }
            return MediaTrack(
                id: index,
                kind: kind,
                language: stream.language,
                title: stream.displayTitle ?? stream.title ?? stream.language ?? "Track \(index)",
                codec: stream.codec,
                isSelected: isSelected,
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

    private static func overview(from dto: BaseItemDto) -> String? {
        let text = dto.overview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !text.isEmpty { return dto.overview }
        let program = dto.currentProgram?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return program.isEmpty ? nil : dto.currentProgram?.name
    }

    private static func kind(from type: BaseItemKind?) -> MediaKind? {
        switch type {
        case .movie: .movie
        case .series: .series
        case .season: .season
        case .episode: .episode
        case .boxSet: .collection
        case .genre: .genre
        case .playlist: .playlist
        case .tvChannel, .liveTvProgram, .tvProgram: .liveTV
        case .recording, .video: .movie
        case .book: .book
        case .photo: .photo
        case .photoAlbum: .collection
        case .collectionFolder, .userView, .userRootFolder, .aggregateFolder, .basePluginFolder:
            nil
        default: .unknown
        }
    }

    private static func libraryKind(from collectionType: CollectionType?, name: String) -> LibraryKind {
        switch collectionType {
        case .movies: .movies
        case .tvshows: .shows
        case .music, .musicvideos: .music
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
        case .shows, .youTube: .series
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

    static func extraCaption(from dto: BaseItemDto) -> String {
        switch dto.extraType {
        case .behindTheScenes: "Behind the Scenes"
        case .deletedScene: "Deleted Scene"
        case .interview: "Interview"
        case .scene: "Scene"
        case .featurette: "Featurette"
        case .clip: "Clip"
        case .short: "Short"
        case .sample: "Sample"
        case .themeVideo: "Theme"
        case .trailer: "Trailer"
        default: "Extra"
        }
    }

    static func chapters(from dto: BaseItemDto) -> [MediaChapter] {
        (dto.chapters ?? []).enumerated().compactMap { index, chapter in
            guard let ticks = chapter.startPositionTicks else { return nil }
            let name = chapter.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MediaChapter(
                index: index,
                name: name.isEmpty ? "Chapter \(index + 1)" : name,
                startTime: TickClock.seconds(from: ticks),
                imageTag: chapter.imageTag
            )
        }
    }

    static func versions(from sources: [MediaSourceInfo]?) -> [MediaVersion] {
        (sources ?? []).compactMap { source in
            guard let id = source.id, !id.isEmpty else { return nil }
            return MediaVersion(id: id, title: versionTitle(from: source))
        }
    }

    static func versionTitle(from source: MediaSourceInfo) -> String {
        if let name = source.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        if let path = source.path?.split(separator: "/").last.map(String.init), !path.isEmpty {
            return path
        }
        if let container = source.container, !container.isEmpty {
            return container.uppercased()
        }
        return "Version"
    }

    static func trickplay(from dto: BaseItemDto, sourceID: String?) -> TrickplayInfo? {
        guard let manifest = dto.trickplay, !manifest.isEmpty else { return nil }
        let sourceKey = sourceID.flatMap { key in
            manifest[key] != nil ? key : nil
        } ?? manifest.keys.sorted().first
        guard let sourceKey, let widths = manifest[sourceKey], !widths.isEmpty else { return nil }
        let chosen = widths.min { lhs, rhs in
            abs((Int(lhs.key) ?? 0) - 320) < abs((Int(rhs.key) ?? 0) - 320)
        }
        guard let chosen, let width = Int(chosen.key) ?? chosen.value.width else { return nil }
        let info = chosen.value
        let intervalMs = info.interval ?? 10_000
        return TrickplayInfo(
            width: width,
            interval: TimeInterval(intervalMs) / 1000,
            thumbnailCount: info.thumbnailCount ?? 0,
            tileWidth: info.tileWidth ?? 10,
            tileHeight: info.tileHeight ?? 10,
            thumbnailWidth: info.width ?? width,
            thumbnailHeight: info.height ?? 180,
            mediaSourceID: sourceKey
        )
    }

    static func searchHit(from hint: SearchHint) -> LibrarySearchHit? {
        guard let id = hint.id, let name = hint.name, !name.isEmpty else { return nil }
        let kind: LibrarySearchHit.Kind
        switch hint.type {
        case .movie: kind = .title(.movie)
        case .series: kind = .title(.series)
        case .episode: kind = .title(.episode)
        case .boxSet: kind = .title(.collection)
        case .tvChannel, .liveTvProgram, .tvProgram: kind = .title(.liveTV)
        case .person: kind = .person
        case .genre:
            guard HomeLayoutPreferences.isBrowsableGenre(name) else { return nil }
            kind = .genre
        case .studio: kind = .studio
        case .audio, .musicArtist, .musicAlbum, .musicGenre, .musicVideo, .audioBook, .playlist, .book, .photo, .photoAlbum, .video:
            return nil
        default:
            return nil
        }
        var subtitleParts: [String] = []
        switch kind {
        case .title(.movie): subtitleParts.append("Movie")
        case .title(.series): subtitleParts.append("Show")
        case .title(.episode): subtitleParts.append(hint.series ?? "Episode")
        case .title(.collection): subtitleParts.append("Collection")
        case .title(.playlist): subtitleParts.append("Playlist")
        case .title(.liveTV): subtitleParts.append("Live TV")
        case .title(.book): subtitleParts.append("Book")
        case .title(.photo): subtitleParts.append("Photo")
        case .title: subtitleParts.append("Title")
        case .person: subtitleParts.append("Person")
        case .genre: subtitleParts.append("Genre")
        case .studio: subtitleParts.append("Studio")
        }
        if let year = hint.productionYear {
            subtitleParts.append("\(year)")
        }
        return LibrarySearchHit(
            id: id,
            name: name,
            kind: kind,
            subtitle: subtitleParts.joined(separator: " · "),
            year: hint.productionYear,
            imageTag: hint.primaryImageTag
        )
    }

    static func liveChannel(from dto: BaseItemDto) -> LiveChannel? {
        guard let item = mediaItem(from: dto) else { return nil }
        let program = dto.currentProgram.flatMap { liveProgram(from: $0, channel: item, channelNumber: dto.number) }
        return LiveChannel(item: item, number: dto.number, currentProgram: program)
    }

    static func liveProgram(from dto: BaseItemDto, channel: MediaItem? = nil, channelNumber: String? = nil) -> LiveProgram? {
        guard let item = mediaItem(from: dto) else { return nil }
        let channelID = dto.channelID ?? channel?.id
        let channelName = dto.channelName ?? channel?.name ?? "Channel"
        guard let channelID, !channelID.isEmpty else { return nil }
        let playChannel = channel ?? MediaItem.liveChannelStub(
            id: channelID,
            name: channelName,
            primaryImageTag: dto.channelPrimaryImageTag ?? channel?.primaryImageTag
        )
        return LiveProgram(
            item: item,
            channel: playChannel,
            channelNumber: channelNumber ?? dto.number,
            startDate: dto.startDate,
            endDate: dto.endDate,
            episodeTitle: dto.episodeTitle,
            isMovie: dto.isMovie ?? false,
            isSeries: dto.isSeries ?? false,
            isNews: dto.isNews ?? false,
            isKids: dto.isKids ?? false,
            isSports: dto.isSports ?? false,
            timerID: dto.timerID,
            seriesTimerID: dto.seriesTimerID
        )
    }

    static func recordingItem(from dto: BaseItemDto, treatAsInProgress: Bool = false) -> LiveTVRecording? {
        if dto.isFolder == true { return nil }
        var dto = dto
        let name = dto.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if name.isEmpty {
            let series = dto.seriesName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            dto.name = series.isEmpty ? "Recording" : series
        }
        if dto.type == nil {
            dto.type = .recording
        }
        guard let item = mediaItem(from: dto) else { return nil }
        return LiveTVRecording(
            item: item,
            isInProgress: treatAsInProgress || isInProgressRecordingStatus(dto.status),
            timerID: dto.timerID
        )
    }

    static func isInProgressRecordingStatus(_ status: String?) -> Bool {
        let raw = status?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.caseInsensitiveCompare(RecordingStatus.inProgress.rawValue) == .orderedSame
    }

    static func recommendationTitle(from dto: RecommendationDto) -> String {
        let name = dto.baselineItemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch dto.recommendationType {
        case .similarToRecentlyPlayed:
            return name.isEmpty ? "Because You Watched" : "Because You Watched \(name)"
        case .similarToLikedItem:
            return name.isEmpty ? "Because You Liked" : "Because You Liked \(name)"
        case .hasDirectorFromRecentlyPlayed, .hasLikedDirector:
            return name.isEmpty ? "More From This Director" : "Directed Like \(name)"
        case .hasActorFromRecentlyPlayed, .hasLikedActor:
            return name.isEmpty ? "More From This Cast" : "Starring Like \(name)"
        default:
            return name.isEmpty ? "Recommended" : name
        }
    }
}
