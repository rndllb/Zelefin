import Foundation

struct SiloHealth: Decodable, Sendable, Equatable {
    var status: String
    var serverName: String?
    var serverID: String?
    var version: String?

    enum CodingKeys: String, CodingKey {
        case status, version
        case serverName = "server_name"
        case serverID = "server_id"
    }

    var isReady: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ok" || normalized == "healthy" || normalized == "ready"
    }

    var displayName: String {
        let name = serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Silo" : name
    }
}

struct SiloLoginRequest: Encodable, Sendable {
    var username: String
    var password: String
}

struct SiloRefreshRequest: Encodable, Sendable {
    var refreshToken: String
}

struct SiloAuthResponse: Decodable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int?
    var user: SiloUser

    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct SiloUser: Decodable, Sendable {
    var id: Int
    var username: String
    var email: String?
    var role: String?
    var downloadAllowed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, email, role
        case downloadAllowed = "download_allowed"
    }

    var isAdmin: Bool {
        (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "admin"
    }
}

struct SiloHouseholdProfile: Decodable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var avatar: String?
    var avatarSource: String?
    var avatarURL: URL?
    var hasPin: Bool
    var isChild: Bool
    var isPrimary: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, avatar
        case avatarURL = "avatar_url"
        case avatarSource = "avatar_source"
        case hasPin = "has_pin"
        case isChild = "is_child"
        case isPrimary = "is_primary"
    }

    init(id: String, name: String, avatarURL: URL?, hasPin: Bool, isChild: Bool, isPrimary: Bool) {
        self.init(
            id: id,
            name: name,
            avatarURL: avatarURL,
            hasPin: hasPin,
            isChild: isChild,
            isPrimary: isPrimary,
            avatar: nil,
            avatarSource: nil
        )
    }

    init(
        id: String,
        name: String,
        avatarURL: URL?,
        hasPin: Bool,
        isChild: Bool,
        isPrimary: Bool,
        avatar: String?,
        avatarSource: String?
    ) {
        self.id = id
        self.name = name
        self.avatar = avatar
        self.avatarSource = avatarSource
        self.avatarURL = avatarURL
        self.hasPin = hasPin
        self.isChild = isChild
        self.isPrimary = isPrimary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        name = container.decodeNonEmptyString(.name) ?? "Profile"
        avatar = container.decodeNonEmptyString(.avatar)
        avatarSource = container.decodeNonEmptyString(.avatarSource)
        avatarURL = container.decodeFlexibleURL(.avatarURL)
        hasPin = (try? container.decodeIfPresent(Bool.self, forKey: .hasPin)) ?? false
        isChild = (try? container.decodeIfPresent(Bool.self, forKey: .isChild)) ?? false
        isPrimary = (try? container.decodeIfPresent(Bool.self, forKey: .isPrimary)) ?? false
    }

    var isUploadedAvatar: Bool {
        (avatarSource ?? "").lowercased() == "upload"
    }

    var hasAvatar: Bool {
        isUploadedAvatar || avatarURL != nil || !(avatar ?? "").isEmpty
    }

    func resolved(against baseURL: URL) -> SiloHouseholdProfile {
        var copy = self
        if let raw = avatarURL?.absoluteString, !raw.isEmpty {
            copy.avatarURL = SiloProfileAvatars.displayURL(baseURL: baseURL, raw: raw)
        } else if let avatar, let preview = SiloProfileAvatars.previewURL(forPreset: avatar) {
            copy.avatarURL = preview
        }
        return copy
    }
}

struct SiloProfilesResponse: Decodable, Sendable {
    var profiles: [SiloHouseholdProfile]?
    var items: [SiloHouseholdProfile]?
    var avatarUploadEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case profiles, items
        case avatarUploadEnabled = "avatar_upload_enabled"
    }

    var entries: [SiloHouseholdProfile] { profiles ?? items ?? [] }

    func resolved(against baseURL: URL) -> SiloProfilesResponse {
        var copy = self
        copy.profiles = entries.map { $0.resolved(against: baseURL) }
        copy.items = nil
        return copy
    }
}

struct SiloProfileAvatarUpdate: Encodable, Sendable {
    var avatar: String?

    enum CodingKeys: String, CodingKey {
        case avatar
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(avatar, forKey: .avatar)
    }
}

struct SiloPINVerification: Encodable, Sendable {
    var pin: String
}

struct SiloPINResult: Decodable, Sendable {
    var valid: Bool
    var profileToken: String?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case valid
        case profileToken = "profile_token"
        case expiresAt = "expires_at"
    }
}

struct SiloPendingSignIn: Equatable, Sendable {
    var serverURL: URL
    var accessToken: String
    var refreshToken: String?
    var userID: String
    var userName: String
    var deviceID: String
    var serverName: String?
    var serverVersion: String?
    var userRole: String?
    var profiles: [SiloHouseholdProfile]

    var needsProfileChoice: Bool {
        profiles.count != 1 || profiles.contains(where: \.hasPin)
    }

    var singleUnlockedProfile: SiloHouseholdProfile? {
        guard profiles.count == 1, let profile = profiles.first, !profile.hasPin else { return nil }
        return profile
    }
}

struct SiloLibraryRecord: Decodable, Sendable, Identifiable {
    var id: Int
    var name: String
    var type: String?
    var kind: String?
    var mediaType: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, kind
        case mediaType = "media_type"
    }

    var catalogKind: String {
        (type ?? kind ?? mediaType ?? "").lowercased()
    }
}

struct SiloLibrariesEnvelope: Decodable, Sendable {
    var libraries: [SiloLibraryRecord]?
}

struct SiloUserState: Decodable, Sendable {
    var playbackPosition: TimeInterval?
    var position: TimeInterval?
    var positionSeconds: TimeInterval?
    var played: Bool?
    var isPlayed: Bool?
    var isFavorite: Bool?
    var favorite: Bool?

    enum CodingKeys: String, CodingKey {
        case position, played, favorite
        case playbackPosition = "playback_position"
        case positionSeconds = "position_seconds"
        case isPlayed = "is_played"
        case isFavorite = "is_favorite"
    }

    var seconds: TimeInterval {
        playbackPosition ?? positionSeconds ?? position ?? 0
    }

    var watched: Bool {
        played ?? isPlayed ?? false
    }

    var favoriteFlag: Bool {
        isFavorite ?? favorite ?? false
    }
}

/// Per-item quality summary the Silo server attaches to catalog, home, and
/// detail items (wire key `overlay_summary`). Drives the poster quality/audio
/// badges — the same information the reference clients render as card overlays.
struct SiloOverlaySummary: Decodable, Sendable {
    var resolution: String?
    var hdr: String?
    var audio: String?
    var audioChannels: String?
    var videoCodec: String?

    enum CodingKeys: String, CodingKey {
        case resolution, hdr, audio
        case audioChannels = "audio_channels"
        case videoCodec = "video_codec"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = container.decodeNonEmptyString(.resolution)
        hdr = container.decodeNonEmptyString(.hdr)
        audio = container.decodeNonEmptyString(.audio)
        audioChannels = container.decodeFlexibleString(.audioChannels)
        videoCodec = container.decodeNonEmptyString(.videoCodec)
    }
}

struct SiloCatalogItem: Decodable, Sendable {
    var contentID: String
    var playContentID: String?
    var type: String?
    var title: String?
    var name: String?
    var seriesID: String?
    var seriesTitle: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var year: Int?
    var runtime: Int?
    var genres: [String]?
    var contentRating: String?
    var overview: String?
    var posterURL: URL?
    var backdropURL: URL?
    var logoURL: URL?
    var itemSource: String?
    var ratingImdb: Double?
    var ratingTmdb: Double?
    var ratingRt: Double?
    var ratingRtAudience: Double?
    var userState: SiloUserState?
    var addedAt: Date?
    var tmdbID: Int?
    var imdbID: String?
    var originalTitle: String?
    var releaseDate: String?
    var firstAirDate: String?
    var showStatus: String?
    var airTime: String?
    var studios: [String]?
    var networks: [String]?
    var countries: [String]?
    var positionSeconds: TimeInterval?
    var durationSeconds: TimeInterval?
    var versions: [SiloMediaVersion]?
    var files: [SiloMediaVersion]?
    var playbackVariants: [SiloPlaybackVariant]?
    var cast: [SiloCreditRecord]?
    var crew: [SiloCreditRecord]?
    var videos: [SiloItemVideo]?
    var extras: [SiloItemExtra]?
    var overlaySummary: SiloOverlaySummary?

    enum CodingKeys: String, CodingKey {
        case type, title, name, year, runtime, genres, overview, versions, files, cast, crew, studios, networks, countries, videos, extras
        case playbackVariants = "playback_variants"
        case overlaySummary = "overlay_summary"
        case contentID = "content_id"
        case playContentID = "play_content_id"
        case seriesID = "series_id"
        case seriesTitle = "series_title"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case contentRating = "content_rating"
        case posterURL = "poster_url"
        case backdropURL = "backdrop_url"
        case logoURL = "logo_url"
        case itemSource = "item_source"
        case ratingImdb = "rating_imdb"
        case ratingTmdb = "rating_tmdb"
        case ratingRt = "rating_rt"
        case ratingRtCritic = "rating_rt_critic"
        case ratingRtAudience = "rating_rt_audience"
        case userState = "user_state"
        case userData = "user_data"
        case addedAt = "added_at"
        case tmdbID = "tmdb_id"
        case imdbID = "imdb_id"
        case originalTitle = "original_title"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case showStatus = "show_status"
        case airTime = "air_time"
        case positionSeconds = "position_seconds"
        case durationSeconds = "duration_seconds"
    }

    init(contentID: String) {
        self.contentID = contentID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let contentID = container.decodeFlexibleString(.contentID) {
            self.contentID = contentID
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.contentID,
                .init(codingPath: decoder.codingPath, debugDescription: "content_id is required")
            )
        }
        playContentID = container.decodeNonEmptyString(.playContentID)
        type = container.decodeNonEmptyString(.type)
        title = container.decodeNonEmptyString(.title)
        name = container.decodeNonEmptyString(.name)
        seriesID = container.decodeNonEmptyString(.seriesID)
        seriesTitle = container.decodeNonEmptyString(.seriesTitle)
        seasonNumber = container.decodeFlexibleInt(.seasonNumber)
        episodeNumber = container.decodeFlexibleInt(.episodeNumber)
        year = container.decodeFlexibleInt(.year)
        runtime = container.decodeFlexibleInt(.runtime)
        genres = container.decodeNamedStrings(.genres)
        contentRating = container.decodeNonEmptyString(.contentRating)
        overview = container.decodeNonEmptyString(.overview)
        posterURL = container.decodeFlexibleURL(.posterURL)
        backdropURL = container.decodeFlexibleURL(.backdropURL)
        logoURL = container.decodeFlexibleURL(.logoURL)
        itemSource = container.decodeNonEmptyString(.itemSource)
        ratingImdb = container.decodeFlexibleDouble(.ratingImdb)
        ratingTmdb = container.decodeFlexibleDouble(.ratingTmdb)
        ratingRt = container.decodeFlexibleDouble(.ratingRt)
            ?? container.decodeFlexibleDouble(.ratingRtCritic)
            ?? container.decodeFlexibleInt(.ratingRtCritic).map(Double.init)
        ratingRtAudience = container.decodeFlexibleDouble(.ratingRtAudience)
        userState = (try? container.decodeIfPresent(SiloUserState.self, forKey: .userState))
            ?? (try? container.decodeIfPresent(SiloUserState.self, forKey: .userData))
        addedAt = try? container.decodeIfPresent(Date.self, forKey: .addedAt)
        tmdbID = container.decodeFlexibleInt(.tmdbID)
        imdbID = container.decodeNonEmptyString(.imdbID)
        originalTitle = container.decodeNonEmptyString(.originalTitle)
        releaseDate = container.decodeNonEmptyString(.releaseDate)
        firstAirDate = container.decodeNonEmptyString(.firstAirDate)
        showStatus = container.decodeNonEmptyString(.showStatus)
        airTime = container.decodeNonEmptyString(.airTime)
        studios = container.decodeNamedStrings(.studios)
        networks = container.decodeNamedStrings(.networks)
        countries = container.decodeNamedStrings(.countries)
        positionSeconds = container.decodeFlexibleDouble(.positionSeconds)
        durationSeconds = container.decodeFlexibleDouble(.durationSeconds)
        versions = container.decodeLossyArray(.versions)
        files = container.decodeLossyArray(.files)
        playbackVariants = container.decodeLossyArray(.playbackVariants)
        cast = container.decodeLossyArray(.cast)
        crew = container.decodeLossyArray(.crew)
        videos = container.decodeLossyArray(.videos)
        extras = container.decodeLossyArray(.extras)
        overlaySummary = try? container.decodeIfPresent(SiloOverlaySummary.self, forKey: .overlaySummary)
    }

    var displayTitle: String {
        let value = (title ?? name)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Untitled" : value
    }

    var playbackID: String {
        let play = playContentID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return play.isEmpty ? contentID : play
    }

    var isDirectlyPlayable: Bool {
        switch (type ?? "").lowercased() {
        case "movie", "episode", "audiobook", "ebook":
            true
        default:
            false
        }
    }

    var fileIDGroups: [[SiloMediaVersion]] {
        var groups = [versions ?? [], files ?? []]
        if let playbackVariants {
            groups.append(playbackVariants.flatMap(\.fileIDs))
        }
        return groups
    }

    var resolvedFileIDs: [Int] {
        fileIDGroups.flatMap { $0.compactMap(\.resolvedFileID) }
    }

    func withFileIDs(from data: Data) -> SiloCatalogItem {
        if !resolvedFileIDs.isEmpty { return self }
        let scraped = SiloMediaVersion.versions(from: data)
        guard !scraped.isEmpty else { return self }
        var item = self
        item.versions = scraped
        return item
    }

    static func salvage(from data: Data) -> SiloCatalogItem? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let source = (object["item"] as? [String: Any]) ?? object
        func string(_ key: String) -> String? {
            let value = (source[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        guard let contentID = string("content_id") ?? string("id") else { return nil }
        var item = SiloCatalogItem(contentID: contentID)
        item.playContentID = string("play_content_id")
        item.type = string("type")
        item.title = string("title") ?? string("name")
        item.seriesID = string("series_id")
        item.seriesTitle = string("series_title")
        let scraped = SiloMediaVersion.versions(from: data)
        item.versions = scraped.isEmpty ? nil : scraped
        return item
    }
}

struct SiloCatalogResponse: Decodable, Sendable {
    var items: [SiloCatalogItem]?
    var results: [SiloCatalogItem]?
    var total: Int?
    var totalCount: Int?

    enum CodingKeys: String, CodingKey {
        case items, results, total
        case totalCount = "total_count"
    }

    var entries: [SiloCatalogItem] { items ?? results ?? [] }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.decodeLossyArray(.items)
        results = container.decodeLossyArray(.results)
        total = container.decodeFlexibleInt(.total)
        totalCount = container.decodeFlexibleInt(.totalCount)
    }
}

struct SiloSeasonRecord: Decodable, Sendable {
    var id: String?
    var contentID: String?
    var title: String?
    var name: String?
    var overview: String?
    var seasonNumber: Int?
    var isSpecials: Bool?
    var posterURL: URL?
    var episodeCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview
        case contentID = "content_id"
        case seasonNumber = "season_number"
        case isSpecials = "is_specials"
        case posterURL = "poster_url"
        case episodeCount = "episode_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        contentID = container.decodeFlexibleString(.contentID) ?? id
        title = container.decodeNonEmptyString(.title)
        name = container.decodeNonEmptyString(.name)
        overview = container.decodeNonEmptyString(.overview)
        seasonNumber = container.decodeFlexibleInt(.seasonNumber)
        isSpecials = container.decodeFlexibleBool(.isSpecials)
        posterURL = container.decodeFlexibleURL(.posterURL)
        episodeCount = container.decodeFlexibleInt(.episodeCount)
    }
}

struct SiloSeasonsResponse: Decodable, Sendable {
    var seasons: [SiloSeasonRecord]?
    var items: [SiloSeasonRecord]?

    enum CodingKeys: String, CodingKey {
        case seasons, items
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            seasons = container.decodeLossyArray(.seasons)
            items = container.decodeLossyArray(.items)
            return
        }
        seasons = try SiloLossyArray<SiloSeasonRecord>(from: decoder).items
    }

    var entries: [SiloSeasonRecord] { seasons ?? items ?? [] }
}

struct SiloEpisodeRecord: Decodable, Sendable {
    var contentID: String?
    var id: String?
    var title: String?
    var name: String?
    var overview: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var runtime: Int?
    var posterURL: URL?
    var backdropURL: URL?
    var userState: SiloUserState?
    var seriesID: String?
    var seriesTitle: String?
    var files: [SiloMediaVersion]?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, runtime, files
        case contentID = "content_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case posterURL = "poster_url"
        case stillURL = "still_url"
        case backdropURL = "backdrop_url"
        case userState = "user_state"
        case userData = "user_data"
        case seriesID = "series_id"
        case seriesTitle = "series_title"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        contentID = container.decodeFlexibleString(.contentID) ?? id
        title = container.decodeNonEmptyString(.title)
        name = container.decodeNonEmptyString(.name)
        overview = container.decodeNonEmptyString(.overview)
        seasonNumber = container.decodeFlexibleInt(.seasonNumber)
        episodeNumber = container.decodeFlexibleInt(.episodeNumber)
        runtime = container.decodeFlexibleInt(.runtime)
        posterURL = container.decodeFlexibleURL(.stillURL) ?? container.decodeFlexibleURL(.posterURL)
        backdropURL = container.decodeFlexibleURL(.backdropURL)
        userState = (try? container.decodeIfPresent(SiloUserState.self, forKey: .userState))
            ?? (try? container.decodeIfPresent(SiloUserState.self, forKey: .userData))
        seriesID = container.decodeNonEmptyString(.seriesID)
        seriesTitle = container.decodeNonEmptyString(.seriesTitle)
        files = container.decodeLossyArray(.files)
    }

    var resolvedFileID: Int? {
        files?.compactMap(\.resolvedFileID).first
    }
}

struct SiloEpisodesResponse: Decodable, Sendable {
    var episodes: [SiloEpisodeRecord]?
    var items: [SiloEpisodeRecord]?

    enum CodingKeys: String, CodingKey {
        case episodes, items
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self) {
            episodes = container.decodeLossyArray(.episodes)
            items = container.decodeLossyArray(.items)
            return
        }
        episodes = try SiloLossyArray<SiloEpisodeRecord>(from: decoder).items
    }

    var entries: [SiloEpisodeRecord] { episodes ?? items ?? [] }
}

struct SiloStreamTrack: Decodable, Sendable {
    var index: Int?
    var language: String?
    var codec: String?
    var title: String?
    var embeddedTitle: String?
    var layout: String?
    var channels: Int?
    var isDefault: Bool?
    var forced: Bool?
    var hearingImpaired: Bool?
    var external: Bool?

    enum CodingKeys: String, CodingKey {
        case index, language, codec, title, layout, channels, forced, external
        case embeddedTitle = "embedded_title"
        case isDefault = "default"
        case hearingImpaired = "hearing_impaired"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = container.decodeFlexibleInt(.index)
        language = container.decodeFlexibleString(.language)
        codec = container.decodeFlexibleString(.codec)
        title = container.decodeNonEmptyString(.title)
        embeddedTitle = container.decodeNonEmptyString(.embeddedTitle)
        layout = container.decodeNonEmptyString(.layout)
        channels = container.decodeFlexibleInt(.channels)
        isDefault = container.decodeFlexibleBool(.isDefault)
        forced = container.decodeFlexibleBool(.forced)
        hearingImpaired = container.decodeFlexibleBool(.hearingImpaired)
        external = container.decodeFlexibleBool(.external)
    }

    init(json: [String: Any]) {
        index = Self.jsonInt(json["index"])
        language = Self.jsonString(json["language"])
        codec = Self.jsonString(json["codec"])
        title = Self.jsonString(json["title"])
        embeddedTitle = Self.jsonString(json["embedded_title"])
        layout = Self.jsonString(json["layout"])
        channels = Self.jsonInt(json["channels"])
        isDefault = Self.jsonBool(json["default"])
        forced = Self.jsonBool(json["forced"])
        hearingImpaired = Self.jsonBool(json["hearing_impaired"])
        external = Self.jsonBool(json["external"])
    }

    static func list(from value: Any?) -> [SiloStreamTrack] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? [String: Any] }.map(SiloStreamTrack.init(json:))
    }

    func asTrack(kind: MediaTrack.Kind, ordinal: Int) -> MediaTrack {
        MediaTrack(
            id: index ?? ordinal,
            kind: kind,
            language: language,
            title: displayTitle(kind: kind, ordinal: ordinal),
            codec: codec,
            isSelected: isDefault == true,
            isDefault: isDefault == true
        )
    }

    private func displayTitle(kind: MediaTrack.Kind, ordinal: Int) -> String {
        let named = title ?? embeddedTitle
        if let named, !named.isEmpty { return named }
        if let language {
            let code = language.trimmingCharacters(in: .whitespacesAndNewlines)
            if let localized = Locale.current.localizedString(forLanguageCode: code), !localized.isEmpty {
                return localized
            }
            if code.count >= 2, let localized = Locale.current.localizedString(forLanguageCode: String(code.prefix(2))), !localized.isEmpty {
                return localized
            }
        }
        if kind == .audio, let layout, !layout.isEmpty { return layout }
        return kind == .audio ? "Audio \(ordinal + 1)" : "Subtitle \(ordinal + 1)"
    }

    private static func jsonString(_ value: Any?) -> String? {
        let raw = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }

    private static func jsonInt(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        if let raw = value as? String {
            return Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func jsonBool(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let number = jsonInt(value) { return number != 0 }
        switch jsonString(value)?.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
}

struct SiloMediaVersion: Decodable, Sendable {
    var id: Int?
    var fileID: Int?
    var label: String?
    var name: String?
    var width: Int?
    var height: Int?
    var audioTracks: [SiloStreamTrack]?
    var subtitleTracks: [SiloStreamTrack]?

    enum CodingKeys: String, CodingKey {
        case id, label, name, width, height
        case fileID = "file_id"
        case mediaFileID = "media_file_id"
        case audioTracks = "audio_tracks"
        case subtitleTracks = "subtitle_tracks"
    }

    init(fileID: Int) {
        self.fileID = fileID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleInt(.id)
        fileID = container.decodeFlexibleInt(.fileID)
            ?? container.decodeFlexibleInt(.mediaFileID)
            ?? container.decodeFlexibleInt(.id)
        label = container.decodeNonEmptyString(.label)
        name = container.decodeNonEmptyString(.name)
        width = container.decodeFlexibleInt(.width)
        height = container.decodeFlexibleInt(.height)
        audioTracks = container.decodeLossyArray(.audioTracks)
        subtitleTracks = container.decodeLossyArray(.subtitleTracks)
    }

    var resolvedFileID: Int? { fileID ?? id }

    var hasStreamTracks: Bool {
        !audioMediaTracks.isEmpty || !subtitleMediaTracks.isEmpty
    }

    var audioMediaTracks: [MediaTrack] {
        (audioTracks ?? []).enumerated().map { $0.element.asTrack(kind: .audio, ordinal: $0.offset) }
    }

    var subtitleMediaTracks: [MediaTrack] {
        (subtitleTracks ?? []).enumerated().map { $0.element.asTrack(kind: .subtitle, ordinal: $0.offset) }
    }

    static func versions(from data: Data) -> [SiloMediaVersion] {
        var decoded: [SiloMediaVersion] = []
        if let envelope = try? SiloJSON.decoder.decode(SiloWatchEnvelope.self, from: data) {
            decoded = envelope.entries.filter { $0.resolvedFileID != nil }
        }
        if decoded.isEmpty, let collection = try? SiloJSON.decoder.decode(SiloVersionsResponse.self, from: data) {
            decoded = collection.entries.filter { $0.resolvedFileID != nil }
        }
        let withTracks = attachingTracks(from: data, onto: decoded)
        if withTracks.contains(where: \.hasStreamTracks) {
            return withTracks
        }
        if !decoded.isEmpty { return decoded }
        return SiloFileID.scrape(from: data).map(SiloMediaVersion.init(fileID:))
    }

    private static func attachingTracks(from data: Data, onto versions: [SiloMediaVersion]) -> [SiloMediaVersion] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return versions }
        var byFileID: [Int: SiloMediaVersion] = [:]
        for version in versions {
            if let fileID = version.resolvedFileID {
                byFileID[fileID] = version
            }
        }
        collectTracks(from: object, into: &byFileID)
        var seen = Set<Int>()
        var ordered: [SiloMediaVersion] = []
        for version in versions {
            guard let fileID = version.resolvedFileID, seen.insert(fileID).inserted else { continue }
            ordered.append(byFileID[fileID] ?? version)
        }
        for (fileID, version) in byFileID where seen.insert(fileID).inserted {
            ordered.append(version)
        }
        return ordered
    }

    private static func collectTracks(from value: Any, into versions: inout [Int: SiloMediaVersion]) {
        if let array = value as? [Any] {
            for nested in array {
                collectTracks(from: nested, into: &versions)
            }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }
        if let rawID = dictionary["file_id"] ?? dictionary["media_file_id"] ?? dictionary["fileId"],
           let fileID = SiloFileID.int(from: rawID)
        {
            let audio = SiloStreamTrack.list(from: dictionary["audio_tracks"])
            let subtitles = SiloStreamTrack.list(from: dictionary["subtitle_tracks"])
            if !audio.isEmpty || !subtitles.isEmpty {
                var version = versions[fileID] ?? SiloMediaVersion(fileID: fileID)
                if (version.audioTracks ?? []).isEmpty { version.audioTracks = audio }
                if (version.subtitleTracks ?? []).isEmpty { version.subtitleTracks = subtitles }
                versions[fileID] = version
            }
        }
        for key in ["versions", "files", "items", "parts", "playback_variants"] {
            if let nested = dictionary[key] {
                collectTracks(from: nested, into: &versions)
            }
        }
    }
}

struct SiloVersionsResponse: Decodable, Sendable {
    var versions: [SiloMediaVersion]?
    var files: [SiloMediaVersion]?
    var items: [SiloMediaVersion]?

    var entries: [SiloMediaVersion] { versions ?? files ?? items ?? [] }
}

struct SiloPlaybackVariantPart: Decodable, Sendable {
    var defaultFileID: Int?
    var versions: [SiloMediaVersion]?

    enum CodingKeys: String, CodingKey {
        case versions
        case defaultFileID = "default_file_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileID = container.decodeFlexibleInt(.defaultFileID)
        versions = container.decodeLossyArray(.versions)
    }

    var fileIDs: [SiloMediaVersion] {
        if let versions, !versions.isEmpty { return versions }
        if let defaultFileID { return [SiloMediaVersion(fileID: defaultFileID)] }
        return []
    }
}

struct SiloPlaybackVariant: Decodable, Sendable {
    var defaultFileID: Int?
    var parts: [SiloPlaybackVariantPart]?

    enum CodingKeys: String, CodingKey {
        case parts
        case defaultFileID = "default_file_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultFileID = container.decodeFlexibleInt(.defaultFileID)
        parts = container.decodeLossyArray(.parts)
    }

    var fileIDs: [SiloMediaVersion] {
        let nested = parts?.flatMap(\.fileIDs) ?? []
        if !nested.isEmpty { return nested }
        if let defaultFileID { return [SiloMediaVersion(fileID: defaultFileID)] }
        return []
    }
}

struct SiloWatchEnvelope: Decodable, Sendable {
    var versions: [SiloMediaVersion]?
    var files: [SiloMediaVersion]?
    var playbackVariants: [SiloPlaybackVariant]?
    var item: SiloCatalogItem?
    var nestedItem: SiloItemEnvelope?

    enum CodingKeys: String, CodingKey {
        case versions, files, item, items
        case playbackVariants = "playback_variants"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        versions = container.decodeLossyArray(.versions)
        files = container.decodeLossyArray(.files)
        items = container.decodeLossyArray(.items)
        playbackVariants = container.decodeLossyArray(.playbackVariants)
        item = try? container.decode(SiloCatalogItem.self, forKey: .item)
        nestedItem = try? container.decode(SiloItemEnvelope.self, forKey: .item)
    }

    var items: [SiloMediaVersion]?

    var entries: [SiloMediaVersion] {
        var groups: [[SiloMediaVersion]] = [versions ?? [], files ?? [], items ?? []]
        if let playbackVariants {
            groups.append(playbackVariants.flatMap(\.fileIDs))
        }
        if let item {
            groups.append(contentsOf: item.fileIDGroups)
        }
        if let nested = nestedItem?.item {
            groups.append(contentsOf: nested.fileIDGroups)
        }
        if let match = groups.first(where: { $0.contains(where: \.hasStreamTracks) }) {
            return match
        }
        if let match = groups.first(where: { $0.contains(where: { $0.resolvedFileID != nil }) }) {
            return match
        }
        return groups.first(where: { !$0.isEmpty }) ?? []
    }
}

enum SiloFileID {
    private static let keys: Set<String> = [
        "file_id", "fileId", "media_file_id", "mediaFileId",
        "default_file_id", "defaultFileId", "last_file_id", "lastFileId"
    ]

    static func parse(_ raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed), value > 0, String(value) == trimmed else {
            return nil
        }
        return value
    }

    static func scrape(from data: Data) -> [Int] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var found: [Int] = []
        var seen = Set<Int>()
        collect(from: object, into: &found, seen: &seen, preferMediaKeys: true)
        return found
    }

    private static func collect(
        from value: Any,
        into found: inout [Int],
        seen: inout Set<Int>,
        preferMediaKeys: Bool
    ) {
        if let dictionary = value as? [String: Any] {
            if preferMediaKeys {
                for key in ["versions", "files", "playback_variants", "parts"] {
                    if let nested = dictionary[key] {
                        collect(from: nested, into: &found, seen: &seen, preferMediaKeys: true)
                    }
                }
            }
            for (key, nested) in dictionary {
                if keys.contains(key), let fileID = int(from: nested), seen.insert(fileID).inserted {
                    found.append(fileID)
                } else if preferMediaKeys, ["versions", "files", "playback_variants", "parts"].contains(key) {
                    continue
                } else {
                    collect(from: nested, into: &found, seen: &seen, preferMediaKeys: false)
                }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                collect(from: nested, into: &found, seen: &seen, preferMediaKeys: preferMediaKeys)
            }
        }
    }

    static func int(from value: Any) -> Int? {
        if let number = value as? Int, number > 0 { return number }
        if let number = value as? Int64, number > 0, let converted = Int(exactly: number) {
            return converted
        }
        if let number = value as? NSNumber {
            let integer = number.intValue
            if integer > 0, number.doubleValue == Double(integer) { return integer }
        }
        if let raw = value as? String { return parse(raw) }
        return nil
    }
}

struct SiloProgressItem: Decodable, Sendable {
    var contentID: String?
    var item: SiloCatalogItem?
    var position: TimeInterval?
    var duration: TimeInterval?
    var isCompleted: Bool?

    enum CodingKeys: String, CodingKey {
        case item, position, duration
        case contentID = "content_id"
        case isCompleted = "is_completed"
    }
}

struct SiloProgressResponse: Decodable, Sendable {
    var items: [SiloProgressItem]?
    var continueWatching: [SiloCatalogItem]?

    enum CodingKeys: String, CodingKey {
        case items
        case continueWatching = "continue_watching"
    }
}

struct SiloHomeSection: Decodable, Sendable, Identifiable {
    var id: String?
    var sectionType: String?
    var title: String?
    var featured: Bool?
    var items: [SiloCatalogItem]?

    enum CodingKeys: String, CodingKey {
        case id, title, featured, items
        case sectionType = "section_type"
    }

    var resolvedID: String {
        let value = id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? normalizedType : value
    }

    var normalizedType: String {
        (sectionType ?? id ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    var entries: [SiloCatalogItem] { items ?? [] }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        sectionType = container.decodeNonEmptyString(.sectionType)
        title = container.decodeNonEmptyString(.title)
        featured = try? container.decodeIfPresent(Bool.self, forKey: .featured)
        items = container.decodeLossyArray(.items)
    }
}

struct SiloHomeSectionsResponse: Decodable, Sendable {
    var sections: [SiloHomeSection]?
    var items: [SiloHomeSection]?

    var rows: [SiloHomeSection] {
        if let sections, !sections.isEmpty { return sections }
        if let items, !items.isEmpty { return items }
        return sections ?? items ?? []
    }
}

struct SiloHomeSectionItemsEnvelope: Decodable, Sendable {
    var section: SiloHomeSection?
    var items: [SiloCatalogItem]?

    var entries: [SiloCatalogItem] {
        if let items = section?.entries, !items.isEmpty { return items }
        return items ?? []
    }
}

struct SiloCatalogFilters: Decodable, Sendable {
    var genres: [String]?
}

struct SiloRecommendationRow: Decodable, Sendable {
    var type: String?
    var title: String?
    var kind: String?
    var key: String?
    var items: [SiloCatalogItem]?

    var entries: [SiloCatalogItem] { items ?? [] }

    var displayTitle: String {
        let value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Recommended for You" : value
    }

    var sectionID: String {
        let kind = (kind ?? type ?? "row").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return "recommend-\(kind)" }
        return "recommend-\(kind)-\(key)"
    }
}

struct SiloRecommendationRowsResponse: Decodable, Sendable {
    var items: [SiloRecommendationRow]?
    var rows: [SiloRecommendationRow]?

    var entries: [SiloRecommendationRow] { items ?? rows ?? [] }
}

struct SiloPersonalCollection: Decodable, Sendable {
    var id: String
    var name: String?
    var posterURL: URL?
    var itemCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name
        case posterURL = "poster_url"
        case itemCount = "item_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.decodeFlexibleString(.id) else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                .init(codingPath: decoder.codingPath, debugDescription: "id is required")
            )
        }
        self.id = id
        name = container.decodeNonEmptyString(.name)
        posterURL = container.decodeFlexibleURL(.posterURL)
        itemCount = container.decodeFlexibleInt(.itemCount)
    }
}

struct SiloPersonalCollectionsResponse: Decodable, Sendable {
    var items: [SiloPersonalCollection]?
    var collections: [SiloPersonalCollection]?

    var entries: [SiloPersonalCollection] { items ?? collections ?? [] }
}

struct SiloCalendarEvent: Decodable, Sendable {
    var contentID: String?
    var type: String?
    var title: String?
    var episodeTitle: String?
    var seriesID: String?
    var seasonNumber: Int?
    var episodeNumber: Int?
    var airDate: String?
    var localAirDate: String?
    var posterURL: URL?
    var watched: Bool?

    enum CodingKeys: String, CodingKey {
        case type, title, watched
        case contentID = "content_id"
        case episodeTitle = "episode_title"
        case seriesID = "series_id"
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case localAirDate = "local_air_date"
        case posterURL = "poster_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentID = container.decodeFlexibleString(.contentID)
        type = container.decodeNonEmptyString(.type)
        title = container.decodeNonEmptyString(.title)
        episodeTitle = container.decodeNonEmptyString(.episodeTitle)
        seriesID = container.decodeFlexibleString(.seriesID)
        seasonNumber = container.decodeFlexibleInt(.seasonNumber)
        episodeNumber = container.decodeFlexibleInt(.episodeNumber)
        airDate = container.decodeNonEmptyString(.airDate)
        localAirDate = container.decodeNonEmptyString(.localAirDate)
        posterURL = container.decodeFlexibleURL(.posterURL)
        watched = try container.decodeIfPresent(Bool.self, forKey: .watched)
    }
}

struct SiloCalendarDay: Decodable, Sendable {
    var date: String?
    var items: [SiloCalendarEvent]?
}

struct SiloCalendar: Decodable, Sendable {
    var events: [SiloCalendarDay]?
    var items: [SiloCalendarEvent]?

    var allEvents: [SiloCalendarEvent] {
        if let items, !items.isEmpty { return items }
        return events?.flatMap { $0.items ?? [] } ?? []
    }
}

struct SiloItemEnvelope: Decodable, Sendable {
    var item: SiloCatalogItem?
}

/// One row of `/api/v1/recommendations/similar/{id}`. The server returns scored
/// references (an id + relevance score), not full items — the client resolves
/// each id to a catalog item. Tolerant: if a server inlines the whole item, we
/// use it directly instead of a second round-trip.
struct SiloSimilarEntry: Decodable, Sendable {
    var id: String
    var inlinedItem: SiloCatalogItem?

    enum CodingKeys: String, CodingKey {
        case mediaItemID = "media_item_id"
        case itemID = "item_id"
        case contentID = "content_id"
        case id
    }

    init(from decoder: Decoder) throws {
        if let full = try? SiloCatalogItem(from: decoder) {
            inlinedItem = full
            id = full.contentID
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let resolved = container.decodeFlexibleString(.mediaItemID)
            ?? container.decodeFlexibleString(.itemID)
            ?? container.decodeFlexibleString(.contentID)
            ?? container.decodeFlexibleString(.id)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.id,
                .init(codingPath: decoder.codingPath, debugDescription: "a similar-item id is required")
            )
        }
        id = resolved
    }
}

struct SiloSimilarResponse: Decodable, Sendable {
    var items: [SiloSimilarEntry]?
    var results: [SiloSimilarEntry]?
    var data: [SiloSimilarEntry]?

    var entries: [SiloSimilarEntry] { items ?? results ?? data ?? [] }
}

struct SiloCreditRecord: Decodable, Sendable {
    var id: String?
    var personID: String?
    var name: String?
    var character: String?
    var role: String?
    var job: String?
    var order: Int?
    var photoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, character, role, job, order
        case personID = "person_id"
        case photoURL = "photo_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id)
        personID = container.decodeFlexibleString(.personID) ?? id
        name = container.decodeNonEmptyString(.name)
        character = container.decodeNonEmptyString(.character)
        role = container.decodeNonEmptyString(.role)
        job = container.decodeNonEmptyString(.job)
        order = container.decodeFlexibleInt(.order)
        photoURL = container.decodeFlexibleURL(.photoURL)
    }
}

struct SiloItemVideo: Decodable, Sendable {
    var kind: String?
    var site: String?
    var siteKey: String?
    var name: String?
    var isOfficial: Bool?

    enum CodingKeys: String, CodingKey {
        case kind, site, name
        case siteKey = "site_key"
        case isOfficial = "is_official"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.decodeNonEmptyString(.kind)
        site = container.decodeNonEmptyString(.site)
        siteKey = container.decodeNonEmptyString(.siteKey)
        name = container.decodeNonEmptyString(.name)
        isOfficial = container.decodeFlexibleBool(.isOfficial)
    }
}

struct SiloItemExtra: Decodable, Sendable {
    var contentID: String?
    var kind: String?
    var title: String?
    var durationSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case kind, title
        case contentID = "content_id"
        case durationSeconds = "duration_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        contentID = container.decodeFlexibleString(.contentID)
        kind = container.decodeNonEmptyString(.kind)
        title = container.decodeNonEmptyString(.title)
        durationSeconds = container.decodeFlexibleDouble(.durationSeconds)
    }
}

struct SiloCreateProfileRequest: Encodable, Sendable {
    var name: String
    var pin: String?
    var isChild: Bool
}

struct SiloPasswordCapability: Decodable, Sendable {
    var allowed: Bool?
    var changePassword: Bool?
    var requiresCurrentPassword: Bool?
    var minimumPasswordLength: Int?
    var maximumPasswordBytes: Int?

    enum CodingKeys: String, CodingKey {
        case allowed
        case changePassword = "change_password"
        case requiresCurrentPassword = "requires_current_password"
        case minimumPasswordLength = "minimum_password_length"
        case maximumPasswordBytes = "maximum_password_bytes"
    }

    var canChange: Bool { allowed ?? changePassword ?? false }

    var minimumLength: Int { max(minimumPasswordLength ?? 8, 1) }
}

struct SiloChangePasswordRequest: Encodable, Sendable {
    var currentPassword: String
    var newPassword: String
}

struct SiloPageCollection<Element: Decodable>: Decodable, Sendable where Element: Sendable {
    var items: [Element]?

    enum CodingKeys: String, CodingKey {
        case items, entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = container.decodeLossyArray(.items) ?? container.decodeLossyArray(.entries)
    }

    var entries: [Element] { items ?? [] }
}

struct SiloAdminUsersResponse: Decodable, Sendable {
    var items: [SiloAdminUser]?
    var users: [SiloAdminUser]?

    var entries: [SiloAdminUser] { items ?? users ?? [] }
}

struct SiloAdminUser: Decodable, Sendable, Identifiable {
    var id: String
    var username: String
    var email: String?
    var role: String?
    var enabled: Bool?
    var lastActiveAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, username, email, role, enabled
        case lastActiveAt = "last_active_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        username = container.decodeNonEmptyString(.username) ?? "User"
        email = container.decodeNonEmptyString(.email)
        role = container.decodeNonEmptyString(.role)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        lastActiveAt = try? container.decodeIfPresent(Date.self, forKey: .lastActiveAt)
    }

    var isAdmin: Bool { (role ?? "").lowercased() == "admin" }
    var isEnabled: Bool { enabled ?? true }

    var subtitle: String {
        var parts: [String] = []
        if isAdmin { parts.append("Administrator") }
        if !isEnabled { parts.append("Disabled") }
        if let email, !email.isEmpty { parts.append(email) }
        return parts.joined(separator: " · ")
    }
}

struct SiloAdminUserCreateRequest: Encodable, Sendable {
    var username: String
    var email: String
    var password: String
    var role: String
    var createDefaultProfile: Bool
}

struct SiloAdminUserUpdateRequest: Encodable, Sendable {
    var username: String?
    var email: String?
    var password: String?
    var role: String?
    var enabled: Bool?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(password, forKey: .password)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(enabled, forKey: .enabled)
    }

    private enum CodingKeys: String, CodingKey {
        case username, email, password, role, enabled
    }
}

struct SiloAdminTask: Decodable, Sendable, Identifiable {
    var key: String?
    var name: String?
    var description: String?
    var category: String?
    var state: String?
    var progress: Double?
    var manualOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case key, name, description, category, state, progress
        case manualOnly = "manual_only"
    }

    var id: String { key ?? name ?? UUID().uuidString }

    var displayName: String {
        let value = (name ?? key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "Task" : value
    }

    var isRunning: Bool {
        let value = (state ?? "").lowercased()
        return value == "running" || value == "cancelling" || value == "canceling"
    }
}

struct SiloAdminDevice: Decodable, Sendable, Identifiable {
    var userID: String?
    var username: String?
    var deviceID: String?
    var deviceName: String?
    var devicePlatform: String?
    var lastUpdated: Date?

    enum CodingKeys: String, CodingKey {
        case username
        case userID = "user_id"
        case deviceID = "device_id"
        case deviceName = "device_name"
        case devicePlatform = "device_platform"
        case lastUpdated = "last_updated"
    }

    var id: String { "\(userID ?? "")|\(deviceID ?? UUID().uuidString)" }

    var displayName: String {
        let name = deviceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? (deviceID ?? "Device") : name
    }
}

struct SiloAuditLog: Decodable, Sendable, Identifiable {
    var logID: String?
    var timestamp: Date?
    var method: String?
    var path: String?
    var statusCode: Int?
    var username: String?
    var clientIP: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, method, path, username
        case logID = "id"
        case statusCode = "status_code"
        case clientIP = "client_ip"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logID = container.decodeFlexibleString(.logID)
        timestamp = try? container.decodeIfPresent(Date.self, forKey: .timestamp)
        method = container.decodeNonEmptyString(.method)
        path = container.decodeNonEmptyString(.path)
        statusCode = container.decodeFlexibleInt(.statusCode)
        username = container.decodeNonEmptyString(.username)
        clientIP = container.decodeNonEmptyString(.clientIP)
    }

    var id: String {
        logID ?? "\(method ?? "")|\(path ?? "")|\(timestamp?.timeIntervalSince1970 ?? 0)"
    }

    var title: String {
        let verb = method ?? ""
        let route = path ?? ""
        let joined = "\(verb) \(route)".trimmingCharacters(in: .whitespaces)
        return joined.isEmpty ? "Request" : joined
    }
}

struct SiloAdminLibrary: Decodable, Sendable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var enabled: Bool?
    var lastScannedAt: Date?
    var paths: [String]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, enabled, paths
        case lastScannedAt = "last_scanned_at"
    }

    init(id: String, name: String, type: String? = nil, enabled: Bool? = nil, lastScannedAt: Date? = nil, paths: [String]? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.enabled = enabled
        self.lastScannedAt = lastScannedAt
        self.paths = paths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        name = container.decodeNonEmptyString(.name) ?? "Library"
        type = container.decodeNonEmptyString(.type)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        lastScannedAt = try? container.decodeIfPresent(Date.self, forKey: .lastScannedAt)
        paths = try? container.decodeIfPresent([String].self, forKey: .paths)
    }

    var subtitle: String {
        var parts: [String] = []
        if let type, !type.isEmpty { parts.append(type.capitalized) }
        if enabled == false { parts.append("Disabled") }
        if let lastScannedAt {
            parts.append("Scanned \(lastScannedAt.formatted(date: .abbreviated, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }
}

struct SiloAdminInvitation: Decodable, Sendable, Identifiable {
    var id: String
    var email: String
    var role: String?
    var status: String?
    var note: String?
    var expiresAt: Date?
    var invitedByName: String?

    enum CodingKeys: String, CodingKey {
        case id, email, role, status, note
        case expiresAt = "expires_at"
        case invitedByName = "invited_by_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        email = container.decodeNonEmptyString(.email) ?? "Invite"
        role = container.decodeNonEmptyString(.role)
        status = container.decodeNonEmptyString(.status)
        note = container.decodeNonEmptyString(.note)
        expiresAt = try? container.decodeIfPresent(Date.self, forKey: .expiresAt)
        invitedByName = container.decodeNonEmptyString(.invitedByName)
    }

    var isPending: Bool { (status ?? "pending").lowercased() == "pending" }

    var subtitle: String {
        var parts: [String] = []
        if let role, !role.isEmpty { parts.append(role.capitalized) }
        if let status, !status.isEmpty { parts.append(status.capitalized) }
        if let invitedByName, !invitedByName.isEmpty { parts.append(invitedByName) }
        return parts.joined(separator: " · ")
    }
}

struct SiloInvitationCreateRequest: Encodable, Sendable {
    var email: String
    var role: String
    var note: String?
    var createProfile: Bool
    var showTour: Bool
}

struct SiloInvitationDelivery: Decodable, Sendable {
    var claimURL: URL?
    var deliveryStatus: String?
    var invitation: SiloAdminInvitation?

    enum CodingKeys: String, CodingKey {
        case invitation
        case claimURL = "claim_url"
        case deliveryStatus = "delivery_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claimURL = container.decodeFlexibleURL(.claimURL)
        deliveryStatus = container.decodeNonEmptyString(.deliveryStatus)
        invitation = try? container.decodeIfPresent(SiloAdminInvitation.self, forKey: .invitation)
    }
}

struct SiloAdminSession: Decodable, Sendable, Identifiable {
    var sessionID: String
    var username: String?
    var profileName: String?
    var mediaTitle: String?
    var playMethod: String?
    var clientName: String?
    var isPaused: Bool?
    var positionSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case username
        case sessionID = "session_id"
        case profileName = "profile_name"
        case mediaTitle = "media_title"
        case playMethod = "play_method"
        case clientName = "client_name"
        case isPaused = "is_paused"
        case positionSeconds = "position_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = container.decodeFlexibleString(.sessionID) ?? ""
        username = container.decodeNonEmptyString(.username)
        profileName = container.decodeNonEmptyString(.profileName)
        mediaTitle = container.decodeNonEmptyString(.mediaTitle)
        playMethod = container.decodeNonEmptyString(.playMethod)
        clientName = container.decodeNonEmptyString(.clientName)
        isPaused = try? container.decodeIfPresent(Bool.self, forKey: .isPaused)
        positionSeconds = container.decodeFlexibleDouble(.positionSeconds)
    }

    var id: String { sessionID }

    var title: String {
        let name = mediaTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Playback" : name
    }

    var subtitle: String {
        var parts: [String] = []
        if let username, !username.isEmpty { parts.append(username) }
        if let profileName, !profileName.isEmpty { parts.append(profileName) }
        if let clientName, !clientName.isEmpty { parts.append(clientName) }
        if isPaused == true { parts.append("Paused") }
        if let playMethod, !playMethod.isEmpty { parts.append(playMethod) }
        return parts.joined(separator: " · ")
    }
}

struct SiloAdminNode: Decodable, Sendable, Identifiable {
    var id: String
    var name: String
    var type: String?
    var url: String?
    var healthy: Bool?
    var enabled: Bool?
    var activeJobs: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, url, healthy, enabled
        case activeJobs = "active_jobs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeFlexibleString(.id) ?? ""
        name = container.decodeNonEmptyString(.name) ?? "Node"
        type = container.decodeNonEmptyString(.type)
        url = container.decodeNonEmptyString(.url)
        healthy = try? container.decodeIfPresent(Bool.self, forKey: .healthy)
        enabled = try? container.decodeIfPresent(Bool.self, forKey: .enabled)
        activeJobs = container.decodeFlexibleInt(.activeJobs)
    }

    var subtitle: String {
        var parts: [String] = []
        if let type, !type.isEmpty { parts.append(type.capitalized) }
        parts.append(healthy == true ? "Healthy" : "Unhealthy")
        if enabled == false { parts.append("Disabled") }
        if let activeJobs { parts.append("\(activeJobs) jobs") }
        return parts.joined(separator: " · ")
    }
}

struct SiloOperationalLog: Decodable, Sendable, Identifiable {
    var logID: String?
    var timestamp: Date?
    var level: String?
    var component: String?
    var message: String?

    enum CodingKeys: String, CodingKey {
        case timestamp, level, component, message
        case logID = "id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        logID = container.decodeFlexibleString(.logID)
        timestamp = try? container.decodeIfPresent(Date.self, forKey: .timestamp)
        level = container.decodeNonEmptyString(.level)
        component = container.decodeNonEmptyString(.component)
        message = container.decodeNonEmptyString(.message)
    }

    var id: String {
        logID ?? "\(timestamp?.timeIntervalSince1970 ?? 0)|\(message ?? "")"
    }

    var title: String {
        let text = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "Log" : text
    }
}

struct SiloAPIErrorBody: Decodable, Sendable {
    var error: Nested?
    /// Silo auth endpoints return `error` as a bare string (e.g.
    /// `{"error":"session_revoked"}`), not an object. Decoding it as `Nested`
    /// used to throw and drop the entire body, so `code`/`message` came back
    /// nil and the raw JSON leaked into the message.
    var errorString: String?
    var code: String?
    var message: String?
    var errorCode: String?
    var title: String?
    var detail: String?
    var type: String?

    enum CodingKeys: String, CodingKey {
        case error, code, message, title, detail, type
        case errorCode = "error_code"
    }

    struct Nested: Decodable, Sendable {
        var code: String?
        var message: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let nested = try? container.decodeIfPresent(Nested.self, forKey: .error) {
            error = nested
        } else if let string = try? container.decodeIfPresent(String.self, forKey: .error) {
            errorString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        errorCode = try? container.decodeIfPresent(String.self, forKey: .errorCode)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        detail = try? container.decodeIfPresent(String.self, forKey: .detail)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
    }

    var resolvedCode: String? {
        if let code = error?.code ?? errorString ?? code ?? errorCode, !code.isEmpty {
            return code
        }
        let type = type?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if type.contains("invalid_watch_target") { return "invalid_watch_target" }
        if let last = type.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return nil
    }

    var resolvedMessage: String? { error?.message ?? message ?? detail ?? title }
}

struct SiloHTTPError: Error, Sendable {
    var statusCode: Int
    var code: String?
    var message: String

    var isUpgradeRequired: Bool { statusCode == 426 }
    var isUnauthorized: Bool { statusCode == 401 }
    var isMissing: Bool { statusCode == 404 || statusCode == 405 }
    /// The server rejected the session itself (not just a per-profile
    /// permission). Refreshing cannot recover this — the user must re-authenticate.
    var isSessionRevoked: Bool {
        guard statusCode == 401 else { return false }
        let haystack = "\(code ?? "") \(message)".lowercased()
        return haystack.contains("session_revoked") || haystack.contains("session has been revoked")
    }
    var shouldUseLegacySubtitles: Bool {
        if isMissing { return true }
        if statusCode == 408 || statusCode == 501 || statusCode == 502 || statusCode == 503 || statusCode == 504 {
            return true
        }
        let haystack = "\(code ?? "") \(message)".lowercased()
        return haystack.contains("dependency") || haystack.contains("not configured")
    }
    var isInvalidWatchTarget: Bool {
        let code = (self.code ?? "").lowercased()
        if code == "invalid_watch_target" { return true }
        return message.localizedCaseInsensitiveContains("not directly playable")
    }
}

extension SiloHTTPError: LocalizedError {
    var errorDescription: String? { message }
}

extension KeyedDecodingContainer {
    func decodeFlexibleInt(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let raw = try? decode(String.self, forKey: key) {
            return SiloFileID.parse(raw)
        }
        return nil
    }

    func decodeNonEmptyString(_ key: Key) -> String? {
        let value = (try? decode(String.self, forKey: key))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    func decodeFlexibleString(_ key: Key) -> String? {
        if let value = decodeNonEmptyString(key) { return value }
        if let value = decodeFlexibleInt(key) { return String(value) }
        return nil
    }

    func decodeFlexibleBool(_ key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) { return value }
        if let value = decodeFlexibleInt(key) { return value != 0 }
        switch decodeFlexibleString(key)?.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }

    func decodeFlexibleURL(_ key: Key) -> URL? {
        guard let raw = decodeNonEmptyString(key) else { return nil }
        return URL(string: raw)
    }

    func decodeFlexibleDouble(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let raw = try? decode(String.self, forKey: key) {
            return Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    func decodeLossyArray<Element: Decodable>(_ key: Key) -> [Element]? {
        guard contains(key) else { return nil }
        if (try? decodeNil(forKey: key)) == true { return nil }
        guard let decoded = try? decode(SiloLossyArray<Element>.self, forKey: key) else { return nil }
        return decoded.items
    }

    func decodeNamedStrings(_ key: Key) -> [String] {
        if let names = try? decode([String].self, forKey: key) {
            return names.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
        if let objects = try? decode([SiloNamedString].self, forKey: key) {
            return objects.compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return []
    }
}

private struct SiloNamedString: Decodable {
    var name: String?
}

private struct SiloLossyArray<Element: Decodable>: Decodable {
    var items: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            let index = container.currentIndex
            if let item = try? container.decode(Element.self) {
                items.append(item)
            } else {
                _ = try container.decode(SiloAnyJSON.self)
            }
            if container.currentIndex == index { break }
        }
        self.items = items
    }
}

private struct SiloAnyJSON: Decodable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { return }
        if (try? container.decode(Bool.self)) != nil { return }
        if (try? container.decode(Int.self)) != nil { return }
        if (try? container.decode(Double.self)) != nil { return }
        if (try? container.decode(String.self)) != nil { return }
        if (try? container.decode([SiloAnyJSON].self)) != nil { return }
        _ = try? container.decode([String: SiloAnyJSON].self)
    }
}
