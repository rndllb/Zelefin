import AVFoundation
import CoreMedia
import CryptoKit
import Foundation
import VideoToolbox

struct SiloPlaybackDecision: Decodable, Sendable {
    var protocolVersion: Int? = nil
    var serverFeatures: [String]? = nil
    var outcome: String? = nil
    var sessionID: String? = nil
    var playbackPlan: SiloPlaybackPlanEnvelope? = nil
    var streamURL: URL? = nil
    var url: URL? = nil
    var playSessionID: String? = nil
    var terminal: SiloPlaybackTerminal? = nil
    var scrapedStreamURL: String? = nil

    enum CodingKeys: String, CodingKey {
        case outcome, url, terminal
        case protocolVersion = "protocol_version"
        case serverFeatures = "server_features"
        case sessionID = "session_id"
        case playbackPlan = "playback_plan"
        case streamURL = "stream_url"
        case playSessionID = "play_session_id"
    }

    var resolvedStreamPath: String? {
        let candidates = [
            playbackPlan?.stream?.url,
            scrapedStreamURL,
            streamURL?.absoluteString,
            url?.absoluteString
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

struct SiloPlaybackTerminal: Decodable, Sendable {
    var reason: String?
    var message: String?
    var retryable: Bool?
}

struct SiloPlaybackPlanEnvelope: Decodable, Sendable {
    var protocolVersion: Int? = nil
    var planID: String? = nil
    var sessionID: String? = nil
    var delivery: String? = nil
    var stream: SiloPlaybackStream? = nil
    var timeline: SiloPlaybackTimeline? = nil
    var source: SiloPlaybackSource? = nil
    var decisionReason: String? = nil
    var subtitle: SiloPlaybackSubtitleDecision? = nil

    enum CodingKeys: String, CodingKey {
        case delivery, stream, timeline, source, subtitle
        case protocolVersion = "protocol_version"
        case planID = "plan_id"
        case sessionID = "session_id"
        case decisionReason = "decision_reason"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try container.decodeIfPresent(Int.self, forKey: .protocolVersion)
        planID = try container.decodeIfPresent(String.self, forKey: .planID)
        sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID)
        delivery = try container.decodeIfPresent(String.self, forKey: .delivery)
        stream = try? container.decode(SiloPlaybackStream.self, forKey: .stream)
        timeline = try? container.decode(SiloPlaybackTimeline.self, forKey: .timeline)
        source = try? container.decode(SiloPlaybackSource.self, forKey: .source)
        subtitle = try? container.decode(SiloPlaybackSubtitleDecision.self, forKey: .subtitle)
        decisionReason = try container.decodeIfPresent(String.self, forKey: .decisionReason)
        if stream?.url == nil, let nested = try? container.nestedContainer(keyedBy: StreamURLKey.self, forKey: .stream) {
            if let url = try? nested.decode(String.self, forKey: .url) {
                stream = SiloPlaybackStream(url: url, protocolKind: nil, container: nil, mimeType: nil, headers: nil)
            }
        }
    }

    init(delivery: String? = nil, stream: SiloPlaybackStream? = nil) {
        self.delivery = delivery
        self.stream = stream
    }

    private enum StreamURLKey: String, CodingKey { case url }
}

struct SiloPlaybackStream: Decodable, Sendable {
    var url: String?
    var protocolKind: String?
    var container: String?
    var mimeType: String?
    var headers: [String: String]?

    enum CodingKeys: String, CodingKey {
        case url, container, headers
        case protocolKind = "protocol"
        case mimeType = "mime_type"
    }

    init(url: String?, protocolKind: String?, container: String?, mimeType: String?, headers: [String: String]?) {
        self.url = url
        self.protocolKind = protocolKind
        self.container = container
        self.mimeType = mimeType
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let keyed = try decoder.container(keyedBy: CodingKeys.self)
        url = try keyed.decodeIfPresent(String.self, forKey: .url)
        protocolKind = try keyed.decodeIfPresent(String.self, forKey: .protocolKind)
        container = try keyed.decodeIfPresent(String.self, forKey: .container)
        mimeType = try keyed.decodeIfPresent(String.self, forKey: .mimeType)
        headers = try? keyed.decode([String: String].self, forKey: .headers)
    }
}

struct SiloPlaybackTimeline: Decodable, Sendable {
    var playerStartSeconds: TimeInterval?
    var sourceStartSeconds: TimeInterval?
    var streamOriginSeconds: TimeInterval?
    var canSeekAnywhere: Bool?

    enum CodingKeys: String, CodingKey {
        case playerStartSeconds = "player_start_seconds"
        case sourceStartSeconds = "source_start_seconds"
        case streamOriginSeconds = "stream_origin_seconds"
        case canSeekAnywhere = "can_seek_anywhere"
    }

    init(
        playerStartSeconds: TimeInterval? = nil,
        sourceStartSeconds: TimeInterval? = nil,
        streamOriginSeconds: TimeInterval? = nil,
        canSeekAnywhere: Bool? = nil
    ) {
        self.playerStartSeconds = playerStartSeconds
        self.sourceStartSeconds = sourceStartSeconds
        self.streamOriginSeconds = streamOriginSeconds
        self.canSeekAnywhere = canSeekAnywhere
    }
}

struct SiloPlaybackSource: Decodable, Sendable {
    var mediaFileID: Int?
    var durationSeconds: TimeInterval?
    var container: String?
    var videoCodec: String?

    enum CodingKeys: String, CodingKey {
        case container
        case mediaFileID = "media_file_id"
        case durationSeconds = "duration_seconds"
        case videoCodec = "video_codec"
    }
}

struct SiloPlaybackEmbeddedSubtitle: Decodable, Sendable {
    var streamIndex: Int?

    enum CodingKeys: String, CodingKey {
        case streamIndex = "stream_index"
    }
}

struct SiloPlaybackSubtitleDecision: Decodable, Sendable {
    var mode: String?
    var trackID: String?
    var embedded: SiloPlaybackEmbeddedSubtitle?
    var inventory: [SiloPlaybackSubtitleTrack]?

    enum CodingKeys: String, CodingKey {
        case mode, inventory, embedded
        case trackID = "track_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = container.decodeFlexibleString(.mode)
        trackID = container.decodeFlexibleString(.trackID)
        embedded = try? container.decode(SiloPlaybackEmbeddedSubtitle.self, forKey: .embedded)
        inventory = container.decodeLossyArray(.inventory)
    }

    var selectedCombinedIndex: Int? {
        if let trackID, let match = inventory?.first(where: { $0.trackID == trackID }) {
            return match.combinedIndex
        }
        return nil
    }
}

struct SiloPlaybackSubtitleTrack: Decodable, Sendable {
    var trackID: String?
    var combinedIndex: Int?
    var source: String?
    var codec: String?
    var language: String?
    var label: String?
    var forced: Bool?
    var isDefault: Bool?
    var hearingImpaired: Bool?
    var delivery: String?
    var url: String?

    enum CodingKeys: String, CodingKey {
        case source, codec, language, label, forced, delivery, url
        case trackID = "track_id"
        case combinedIndex = "combined_index"
        case isDefault = "default"
        case hearingImpaired = "hearing_impaired"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trackID = container.decodeFlexibleString(.trackID)
        combinedIndex = container.decodeFlexibleInt(.combinedIndex)
        source = container.decodeFlexibleString(.source)
        codec = container.decodeFlexibleString(.codec)
        language = container.decodeFlexibleString(.language)
        label = container.decodeFlexibleString(.label)
        forced = container.decodeFlexibleBool(.forced)
        isDefault = container.decodeFlexibleBool(.isDefault)
        hearingImpaired = container.decodeFlexibleBool(.hearingImpaired)
        delivery = container.decodeFlexibleString(.delivery)
        url = container.decodeFlexibleString(.url)
    }

    var isSidecar: Bool {
        (delivery ?? "").lowercased() == "sidecar" && !(url ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Tracks this client can render without a server burn-in / transcode.
    var isClientRenderable: Bool {
        if isSidecar { return true }
        let delivery = (delivery ?? "").lowercased()
        if delivery.contains("burn") { return false }
        let source = (source ?? "").lowercased()
        return source == "embedded"
            || delivery == "embedded"
            || delivery == "overlay"
            || delivery == "copy"
    }

    var displayTitle: String {
        let name = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty { return name }
        if let language, let localized = Locale.current.localizedString(forLanguageCode: language) {
            return localized
        }
        if let language, !language.isEmpty { return language }
        return "Subtitle"
    }
}

struct SiloPlaybackSubtitleOverlay: Sendable {
    var tracks: [MediaTrack]
    var sidecars: [ExternalSubtitleSidecar]
}

struct SiloPlaybackCapability: Decodable, Sendable {
    var enabled: Bool?
    var protocolVersions: [Int]?
    var features: [String]?
    var deliveries: [String]?

    enum CodingKeys: String, CodingKey {
        case enabled, features, deliveries
        case protocolVersions = "protocol_versions"
    }

    var supportsV3: Bool {
        guard enabled ?? true else { return false }
        if let protocolVersions, !protocolVersions.contains(3) { return false }
        if let features, !features.contains("playback_plan_v3") { return false }
        return true
    }

    var authorizedMediaOrigins: Bool {
        (features ?? []).contains("authorized_media_origins_v1")
    }
}

struct SiloPlaybackV3StartRequest: Encodable, Sendable {
    var protocolVersion: Int
    var clientFeatures: [String]
    var fileID: Int
    var profileID: String
    var playbackAttemptID: String
    var qualityPreference: String
    var subtitleFidelityPreference: String
    var startPosition: TimeInterval
    var audioTrackIndex: Int?
    var subtitleTrackIndex: Int?
    var metered: Bool
    var bandwidthEstimateKbps: Int?
    var bandwidthCapKbps: Int?
    var clientCapabilities: SiloCodecCapabilities
    var clientPlaybackContext: SiloClientPlaybackContext
}

struct SiloCodecCapabilities: Encodable, Sendable {
    var videoEvidence: String
    var audioEvidence: String
    var codecsVideo: [String]
    var codecsVideoHardware: [String]
    var codecsAudio: [String]
    var containers: [String]
    var maxResolution: String
    var hdr: Bool
    var hdrDetails: SiloHDRDetails
    var videoDecode: [SiloVideoDecode]
}

struct SiloHDRDetails: Encodable, Sendable {
    var hdr10: Bool
    var hdr10Plus: Bool
    var hlg: Bool
    var dolbyVisionProfiles: [Int]
}

struct SiloVideoDecode: Encodable, Sendable {
    var codec: String
    var decoderName: String?
    var profiles: [String]
    var levels: [Int]
    var bitDepths: [Int]
    var maxWidth: Int
    var maxHeight: Int
    var maxFrameRate: Double
    var maxBitrateKbps: Int
    var hardware: Bool
}

struct SiloClientPlaybackContext: Encodable, Sendable {
    var protocolVersion: Int
    var formFactor: String
    var appVersion: String
    var appBuild: String?
    var appChannel: String?
    var device: SiloDeviceContext
    var output: SiloOutputContext
    var deliveries: [String: SiloDeliveryCapability]
}

struct SiloDeviceContext: Encodable, Sendable {
    var platform: String
    var osVersion: String
    var manufacturer: String
    var model: String?
    var platformDetails: [String: String]
}

struct SiloOutputContext: Encodable, Sendable {
    var hdrDetails: SiloHDRDetails
    var currentSink: String
    var sinkType: String
    var outputContextId: String
}

struct SiloNativeEmbeddedSubtitle: Encodable, Sendable {
    var container: String
    var codecs: [String]
    var trackIdentity: String
    var assStyling: Bool
    var fontAttachments: Bool
}

struct SiloDeliverySubtitles: Encodable, Sendable {
    var nativeEmbedded: [SiloNativeEmbeddedSubtitle]?
    var embeddedText: Bool
    var sidecarText: Bool
    var assStyling: Bool
    var embeddedBitmap: Bool
    var sidecarBitmap: Bool
    var fontAttachments: Bool
}

struct SiloPlaybackTransformation: Encodable, Sendable {
    var name: String
    var executor: String
    var recipeVersion: String
    var validatedClaims: [String]
}

struct SiloDeliveryCapability: Encodable, Sendable {
    var enabled: Bool
    var supportedOnDevice: Bool
    var containers: [String]
    var videoCodecs: [String]
    var audioDecodeCodecs: [String]
    var audioPassthroughCodecs: [String]
    var maxChannels: Int
    var hdrDetails: SiloHDRDetails
    var subtitles: SiloDeliverySubtitles
    var features: [String]
    var authHeaderRefresh: Bool
    var validatedClaims: [String]
    var transformations: [SiloPlaybackTransformation]
}

enum SiloPlaybackStart {
    static let clientFeatures = [
        "playback_plan_v3",
        "client_video_transformations_v1",
        "playback_route_diagnostics",
        "device_quirks_v1",
        "seek_reanchor_v1",
        "output_change_v1",
        "direct_stream_resume_v1",
        "header_authenticated_media_v1",
        "software_video_decode_v1",
        "embedded_subtitles_v1"
    ]

    private static let packagedVideo = ["h264", "hevc"]
    private static let packagedAudio = ["aac", "ac3", "eac3", "alac", "mp3"]
    private static let progressiveContainers = ["mp4", "mov", "m4v"]
    private static let commonClaims = ["authenticated_stream_headers"]
    /// Silo will not Direct Play HDR unless original_http owns presentation.
    /// VideoToolbox / Aether tone-maps onto whatever sink is active.
    private static let originalHTTPClaims = commonClaims + [
        "client_subtitle_overlay",
        "client_managed_dynamic_range_v1",
        "client_selected_audio_track_v1",
        "client_dv8_base_layer_fallback_v1"
    ]

    static func v3Request(
        fileID: Int,
        profileID: String,
        startPosition: TimeInterval,
        authorizedMediaOrigins: Bool = false,
        allowDirectPlay: Bool = true,
        preferFMP4InHLS: Bool = true,
        maxBitrate: Int? = nil,
        audioIndex: Int? = nil,
        subtitleIndex: Int? = nil,
        metered: Bool = false
    ) -> SiloPlaybackV3StartRequest {
        let snapshot = iOSSnapshot(
            allowDirectPlay: allowDirectPlay,
            preferFMP4InHLS: preferFMP4InHLS
        )
        var features = clientFeatures
        if authorizedMediaOrigins {
            features.append("authorized_media_origins_v1")
        }
        let cap = bandwidthCapKbps(from: maxBitrate)
        return SiloPlaybackV3StartRequest(
            protocolVersion: 3,
            clientFeatures: features,
            fileID: fileID,
            profileID: profileID,
            playbackAttemptID: "zelefin:\(UUID().uuidString.lowercased())",
            qualityPreference: qualityPreference(allowDirectPlay: allowDirectPlay, capKbps: cap),
            subtitleFidelityPreference: "preserve",
            startPosition: startPosition,
            audioTrackIndex: audioIndex,
            subtitleTrackIndex: subtitleIndex,
            metered: metered,
            bandwidthEstimateKbps: cap,
            bandwidthCapKbps: cap,
            clientCapabilities: snapshot.capabilities,
            clientPlaybackContext: snapshot.context
        )
    }

    /// Auto + Direct Play asks for the original file. A bitrate cap is a
    /// user-picked rung and must not silently become "original".
    static func qualityPreference(allowDirectPlay: Bool, capKbps: Int?) -> String {
        allowDirectPlay && capKbps == nil ? "original" : "auto"
    }

    /// HLS packaging this device asked for. Native MPEG-TS drops fMP4.
    static func hlsContainers(preferFMP4: Bool) -> [String] {
        preferFMP4 ? ["hls", "fmp4", "mp4"] : ["hls", "mpegts"]
    }

    /// Adaptive measurements must not force a Silo encode. Only a quality the
    /// user picked below Auto is a start cap.
    static func startBitrate(selected: PlaybackQuality) -> Int? {
        selected == .auto ? nil : selected.bitsPerSecond
    }

    /// Silo validates 100...1_000_000 kbps. The Auto sentinel is 200 Mbps and must not cap the plan.
    static func bandwidthCapKbps(from maxBitrate: Int?) -> Int? {
        guard let maxBitrate, maxBitrate > 0 else { return nil }
        if maxBitrate >= AVDeviceProfileFactory.maxBitrate { return nil }
        let kbps = maxBitrate / 1_000
        guard kbps >= 100 else { return 100 }
        return min(kbps, 1_000_000)
    }

    static func playableURL(from decision: SiloPlaybackDecision, client: SiloAPIClient) async -> URL? {
        guard let path = decision.resolvedStreamPath else { return nil }
        return await client.resolveURL(path)
    }

    static func scrapeStreamURL(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let plan = object["playback_plan"] as? [String: Any]
        let stream = plan?["stream"] as? [String: Any]
        let candidates = [
            stream?["url"] as? String,
            object["stream_url"] as? String,
            object["url"] as? String
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func playbackMethod(protocolKind: String, delivery: String) -> PlaybackMethod {
        let kind = protocolKind.lowercased()
        let route = delivery.lowercased()
        if kind.contains("hls") || route.contains("hls") {
            return route.contains("transcode") ? .transcode : .remux
        }
        if route.contains("original") {
            return .directPlay
        }
        return .remux
    }

    /// `player_start_seconds` is 0 for offset HLS/progressive remux, which must not
    /// replace the catalog resume point used for reporting and client-owned seeks.
    static func resolvedPlayerStart(requested: TimeInterval, timeline: SiloPlaybackTimeline?) -> TimeInterval {
        let advertised = timeline?.playerStartSeconds ?? 0
        if advertised > PlaybackResumePolicy.threshold { return advertised }
        return requested
    }

    /// Original HTTP is the full file; the player must seek. HLS copy / progressive remux
    /// already start at the resume origin (`can_seek_anywhere` false).
    static func clientOwnsPlayhead(
        protocolKind: String,
        delivery: String,
        timeline: SiloPlaybackTimeline?
    ) -> Bool {
        if timeline?.canSeekAnywhere == false { return false }
        let kind = protocolKind.lowercased()
        let route = delivery.lowercased()
        if kind.contains("hls") || route.contains("hls") { return false }
        if timeline?.canSeekAnywhere == true { return true }
        return route.contains("original")
    }

    static func subtitleOverlay(
        inventory: [SiloPlaybackSubtitleTrack],
        selectedCombinedIndex: Int? = nil,
        subtitlesOff: Bool,
        resolve: (String) async -> URL?
    ) async -> SiloPlaybackSubtitleOverlay {
        let renderable = inventory.filter(\.isClientRenderable)
        let selected = subtitlesOff ? nil : selectedRenderable(
            in: renderable,
            preferredCombinedIndex: selectedCombinedIndex
        )
        var tracks: [MediaTrack] = []
        var overlays: [ExternalSubtitleSidecar] = []
        for item in renderable {
            var resolved: URL?
            if item.isSidecar {
                guard let raw = item.url, let url = await resolve(raw) else { continue }
                resolved = url
            }
            let id = item.combinedIndex ?? tracks.count
            tracks.append(
                MediaTrack(
                    id: id,
                    kind: .subtitle,
                    language: item.language,
                    title: item.displayTitle,
                    codec: item.codec,
                    isSelected: !subtitlesOff && item.combinedIndex == selected?.combinedIndex,
                    isDefault: item.isDefault == true
                )
            )
            if let url = resolved {
                overlays.append(
                    ExternalSubtitleSidecar(
                        url: url,
                        name: item.displayTitle,
                        language: item.language,
                        formatHint: subtitleFormatHint(codec: item.codec, url: item.url),
                        isForced: item.forced == true,
                        isHearingImpaired: item.hearingImpaired == true
                    )
                )
            }
        }
        return SiloPlaybackSubtitleOverlay(tracks: tracks, sidecars: overlays)
    }

    /// Echo the combined index Silo assigned. `-1` is off; `nil` leaves Auto.
    static func subtitleStartIndex(_ requested: Int?) -> Int? {
        requested
    }

    static func applyingSubtitleSelection(_ tracks: [MediaTrack], requested: Int?) -> [MediaTrack] {
        guard let requested else { return tracks }
        return tracks.map { track in
            MediaTrack(
                id: track.id,
                kind: track.kind,
                language: track.language,
                title: track.title,
                codec: track.codec,
                isSelected: requested == -1 ? false : track.id == requested,
                isDefault: track.isDefault
            )
        }
    }

    private static func selectedRenderable(
        in tracks: [SiloPlaybackSubtitleTrack],
        preferredCombinedIndex: Int?
    ) -> SiloPlaybackSubtitleTrack? {
        if let preferredCombinedIndex,
           let exact = tracks.first(where: { $0.combinedIndex == preferredCombinedIndex })
        {
            return exact
        }
        let downloaded = tracks.filter { ($0.source ?? "").lowercased() == "downloaded" }
        if let match = downloaded.last(where: { languageMatchesPreferred($0.language) }) ?? downloaded.last {
            return match
        }
        if let flagged = tracks.first(where: { $0.isDefault == true }) {
            return flagged
        }
        return tracks.first(where: { $0.forced != true }) ?? tracks.first
    }

    private static func languageMatchesPreferred(_ language: String?) -> Bool {
        let code = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !code.isEmpty else { return false }
        let preferred = Locale.preferredLanguages.compactMap { identifier in
            Locale(identifier: identifier).language.languageCode?.identifier.lowercased()
        }
        return preferred.contains { code == $0 || code.hasPrefix($0) }
    }

    static func subtitleFormatHint(codec: String?, url: String?) -> String {
        let path = url?.split(separator: "?").first.map(String.init) ?? ""
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if !ext.isEmpty { return ext }
        let codec = (codec ?? "").lowercased()
        if codec.contains("ass") || codec.contains("ssa") { return "ass" }
        if codec.contains("vtt") { return "vtt" }
        if codec.contains("pgs") || codec.contains("sup") || codec.contains("hdmv") { return "sup" }
        return "srt"
    }

    static func unsupportedMessage(for decision: SiloPlaybackDecision, error: SiloHTTPError?) -> String {
        if let message = decision.terminal?.message?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
            return message
        }
        let delivery = decision.playbackPlan?.delivery?.lowercased() ?? ""
        let outcome = decision.outcome?.lowercased() ?? ""
        let code = (error?.code ?? decision.terminal?.reason)?.lowercased() ?? ""
        if delivery.contains("media3") || code.contains("media3") {
            return "This Silo server only offers a Media3 playback plan, which Zelefin does not play."
        }
        if outcome == "adaptation_unavailable" || code.contains("adaptation") {
            return decision.playbackPlan?.decisionReason
                ?? "This Silo server could not build a stream this device can play."
        }
        if let reason = decision.playbackPlan?.decisionReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            return "This Silo server did not return a playable stream (\(reason))."
        }
        if error?.isUpgradeRequired == true {
            return "This Silo server requires playback protocol v3. Zelefin asked for v3 but did not get a playable stream."
        }
        return error?.message ?? "This Silo server did not return a playable stream."
    }

    private struct Snapshot {
        var capabilities: SiloCodecCapabilities
        var context: SiloClientPlaybackContext
    }

    /// iOS Silo uses platform-attested VideoToolbox facts, not the Apple TV 4K
    /// empty `declared` Aether snapshot.
    private static func iOSSnapshot(
        allowDirectPlay: Bool = true,
        preferFMP4InHLS: Bool = true
    ) -> Snapshot {
        let displayHDR = displayHDRDetails()
        let decodeHDR = decodeHDRDetails()
        let decode = videoDecodeAttestation()
        var seen = Set<String>()
        let videoCodecs = decode.map(\.codec).filter { seen.insert($0).inserted }
        let hardwareVideo = decode.filter(\.hardware).map(\.codec)
        let audioCodecs = simulator
            ? ["aac", "ac3", "eac3", "mp3", "opus", "flac"]
            : [
                "aac", "ac3", "eac3", "dts", "truehd", "flac", "alac", "mp3",
                "opus", "vorbis", "pcm", "pcm_s16le", "pcm_s24le"
            ]
        let videoContainers = simulator
            ? ["mp4", "mov", "m4v", "mkv", "matroska", "ts", "m2ts", "mpegts"]
            : ["mp4", "mov", "m4v", "mkv", "matroska", "webm", "avi", "ts", "m2ts", "mpegts"]
        let containers = videoContainers + ["mp3", "m4a", "m4b", "aac", "flac", "wav"]
        let maxHeight = simulator ? 1_080 : 2_160
        let originalSubtitles = SiloDeliverySubtitles(
            nativeEmbedded: nativeEmbeddedSubtitles(containers: containers),
            embeddedText: true,
            sidecarText: true,
            assStyling: true,
            embeddedBitmap: true,
            sidecarBitmap: false,
            fontAttachments: true
        )
        let packagedSubtitles = SiloDeliverySubtitles(
            nativeEmbedded: nil,
            embeddedText: true,
            sidecarText: true,
            assStyling: true,
            embeddedBitmap: false,
            sidecarBitmap: false,
            fontAttachments: true
        )
        let sink = currentSink()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let machine = DeviceIdentity.hardwareIdentifier
        var details = ["os_name": "ios"]
        if !machine.isEmpty {
            details["machine"] = machine
        }
        if simulator {
            details["simulator"] = "true"
        }
        let hdrIdentity =
            "\(displayHDR.hdr10)|\(displayHDR.hdr10Plus)|\(displayHDR.hlg)|" +
            displayHDR.dolbyVisionProfiles.map(String.init).joined(separator: ",")
        let identity = ["ios", formFactor, sink.sink, sink.type, hdrIdentity].joined(separator: "|")
        let capabilities = SiloCodecCapabilities(
            videoEvidence: "platform_attested",
            audioEvidence: "declared",
            codecsVideo: videoCodecs,
            codecsVideoHardware: hardwareVideo,
            codecsAudio: audioCodecs,
            containers: containers,
            maxResolution: maxHeight >= 2_160 ? "2160p" : "1080p",
            hdr: displayHDR.hdr10 || decodeHDR.hdr10 || displayHDR.hlg || decodeHDR.hlg
                || !displayHDR.dolbyVisionProfiles.isEmpty || !decodeHDR.dolbyVisionProfiles.isEmpty,
            hdrDetails: displayHDR,
            videoDecode: decode
        )
        let context = SiloClientPlaybackContext(
            protocolVersion: 3,
            formFactor: formFactor,
            appVersion: DeviceIdentity.version,
            appBuild: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            appChannel: appChannel,
            device: SiloDeviceContext(
                platform: "ios",
                osVersion: osVersion,
                manufacturer: "Apple",
                model: String(machine.prefix(128)),
                platformDetails: details
            ),
            output: SiloOutputContext(
                hdrDetails: displayHDR,
                currentSink: String(sink.sink.prefix(128)),
                sinkType: String(sink.type.prefix(128)),
                outputContextId: hashedOutputContextID(identity)
            ),
            deliveries: [
                "original_http": SiloDeliveryCapability(
                    enabled: allowDirectPlay,
                    supportedOnDevice: allowDirectPlay,
                    containers: containers,
                    videoCodecs: videoCodecs,
                    audioDecodeCodecs: audioCodecs,
                    audioPassthroughCodecs: [],
                    maxChannels: 8,
                    hdrDetails: decodeHDR,
                    subtitles: originalSubtitles,
                    features: [],
                    authHeaderRefresh: false,
                    validatedClaims: originalHTTPClaims,
                    transformations: deviceClientTransformations
                ),
                "progressive": SiloDeliveryCapability(
                    enabled: true,
                    supportedOnDevice: true,
                    containers: progressiveContainers,
                    videoCodecs: packagedVideo.filter { hardwareVideo.contains($0) || $0 == "h264" },
                    audioDecodeCodecs: packagedAudio,
                    audioPassthroughCodecs: [],
                    maxChannels: 8,
                    hdrDetails: displayHDR,
                    subtitles: packagedSubtitles,
                    features: [],
                    authHeaderRefresh: false,
                    validatedClaims: commonClaims + ["client_subtitle_overlay"],
                    transformations: []
                ),
                "hls": SiloDeliveryCapability(
                    enabled: true,
                    supportedOnDevice: true,
                    containers: hlsContainers(preferFMP4: preferFMP4InHLS),
                    videoCodecs: packagedVideo.filter { hardwareVideo.contains($0) || $0 == "h264" },
                    audioDecodeCodecs: ["aac", "ac3", "eac3"],
                    audioPassthroughCodecs: [],
                    maxChannels: 8,
                    hdrDetails: displayHDR,
                    subtitles: packagedSubtitles,
                    features: [],
                    authHeaderRefresh: false,
                    validatedClaims: commonClaims + ["client_subtitle_overlay"],
                    transformations: []
                )
            ]
        )
        return Snapshot(capabilities: capabilities, context: context)
    }

    private static var simulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private static var formFactor: String {
        DeviceIdentity.clientFamily
    }

    private static var appChannel: String {
        #if DEBUG
        "dev"
        #else
        "release"
        #endif
    }

    private static var deviceClientTransformations: [SiloPlaybackTransformation] {
        if simulator { return [] }
        return [
            SiloPlaybackTransformation(
                name: "client_dv7_to_dv81",
                executor: "client",
                recipeVersion: "1",
                validatedClaims: [
                    "profile7_rpu_converted_to_profile81",
                    "hdr10_base_layer_preserved",
                    "enhancement_layer_discarded"
                ]
            ),
            SiloPlaybackTransformation(
                name: "client_dv7_to_hdr10",
                executor: "client",
                recipeVersion: "1",
                validatedClaims: [
                    "dolby_vision_metadata_removed",
                    "hdr10_base_layer_preserved",
                    "enhancement_layer_discarded"
                ]
            )
        ]
    }

    private static func nativeEmbeddedSubtitles(containers: [String]) -> [SiloNativeEmbeddedSubtitle] {
        var seen = Set<String>()
        return containers
            .map { $0.lowercased() == "matroska" ? "mkv" : $0.lowercased() }
            .filter { ["mkv", "mp4", "mov", "m4v", "webm"].contains($0) && seen.insert($0).inserted }
            .map { container in
                SiloNativeEmbeddedSubtitle(
                    container: container,
                    codecs: container == "mkv"
                        ? ["subrip", "ass", "ssa", "webvtt", "hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"]
                        : (container == "webm" ? ["webvtt"] : ["mov_text"]),
                    trackIdentity: "ffmpeg_stream_index",
                    assStyling: true,
                    fontAttachments: true
                )
            }
    }

    private static func videoDecodeAttestation() -> [SiloVideoDecode] {
        let maxHeight = simulator ? 1_080 : 2_160
        let maxWidth = maxHeight >= 2_160 ? 3_840 : 1_920
        let codecTypes: [(String, CMVideoCodecType)] = [
            ("h264", kCMVideoCodecType_H264),
            ("hevc", kCMVideoCodecType_HEVC)
        ]
        let hardware: [SiloVideoDecode] = codecTypes.compactMap { codec, codecType in
            guard hardwareDecodeSupported(codecType) else { return nil }
            return SiloVideoDecode(
                codec: codec,
                decoderName: "VideoToolbox",
                profiles: [],
                levels: [],
                bitDepths: codec == "hevc" ? [8, 10] : [8],
                maxWidth: maxWidth,
                maxHeight: maxHeight,
                maxFrameRate: 60,
                maxBitrateKbps: maxHeight >= 2_160 ? 120_000 : 25_000,
                hardware: true
            )
        }
        let software: [SiloVideoDecode] = [
            SiloVideoDecode(
                codec: "h264", decoderName: "libavcodec", profiles: ["high 10"], levels: [],
                bitDepths: [10], maxWidth: 1_920, maxHeight: 1_080, maxFrameRate: 30,
                maxBitrateKbps: 10_000, hardware: false
            ),
            SiloVideoDecode(
                codec: "av1", decoderName: "dav1d", profiles: ["main"], levels: [],
                bitDepths: [10], maxWidth: 1_920, maxHeight: 1_080, maxFrameRate: 30,
                maxBitrateKbps: 3_000, hardware: false
            ),
            SiloVideoDecode(
                codec: "vp9", decoderName: "libavcodec", profiles: ["profile 0"], levels: [],
                bitDepths: [8], maxWidth: 1_920, maxHeight: 1_080, maxFrameRate: 30,
                maxBitrateKbps: 3_000, hardware: false
            ),
            SiloVideoDecode(
                codec: "mpeg2video", decoderName: "libavcodec", profiles: ["main"], levels: [],
                bitDepths: [8], maxWidth: 720, maxHeight: 480, maxFrameRate: 31,
                maxBitrateKbps: 7_000, hardware: false
            ),
            SiloVideoDecode(
                codec: "vc1", decoderName: "libavcodec", profiles: ["advanced"], levels: [],
                bitDepths: [8], maxWidth: 1_920, maxHeight: 1_080, maxFrameRate: 30,
                maxBitrateKbps: 32_000, hardware: false
            )
        ]
        return hardware + software
    }

    private static func hardwareDecodeSupported(_ codecType: CMVideoCodecType) -> Bool {
        #if targetEnvironment(simulator)
        codecType == kCMVideoCodecType_H264
        #else
        VTIsHardwareDecodeSupported(codecType)
        #endif
    }

    /// What the current sink can show. Packaged HLS/progressive stay output-gated.
    private static func displayHDRDetails() -> SiloHDRDetails {
        #if targetEnvironment(simulator)
        return SiloHDRDetails(hdr10: false, hdr10Plus: false, hlg: false, dolbyVisionProfiles: [])
        #else
        let modes = AVPlayer.availableHDRModes
        let eligible = AVPlayer.eligibleForHDRPlayback
        return SiloHDRDetails(
            hdr10: eligible && modes.contains(.hdr10),
            hdr10Plus: false,
            hlg: eligible && modes.contains(.hlg),
            dolbyVisionProfiles: eligible && modes.contains(.dolbyVision) ? [5, 8] : []
        )
        #endif
    }

    /// Ranges the Direct Play engine can map onto any sink. Required for
    /// `client_managed_dynamic_range_v1` so Silo does not tone-map HDR to SDR.
    private static func decodeHDRDetails() -> SiloHDRDetails {
        if simulator {
            return SiloHDRDetails(hdr10: false, hdr10Plus: false, hlg: false, dolbyVisionProfiles: [])
        }
        return SiloHDRDetails(
            hdr10: true,
            hdr10Plus: false,
            hlg: true,
            dolbyVisionProfiles: [5, 8]
        )
    }

    private static func currentSink() -> (sink: String, type: String) {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.isEmpty {
            return ("built_in_speaker", "speaker")
        }
        let sink = outputs.map(\.uid).sorted().joined(separator: ",")
        let type = outputs.map(\.portType.rawValue).sorted().joined(separator: ",")
        return (sink.isEmpty ? "built_in_speaker" : sink, type.isEmpty ? "speaker" : type)
    }

    private static func hashedOutputContextID(_ identity: String) -> String {
        let digest = SHA256.hash(data: Data(identity.utf8))
        return "zelefin:" + digest.map { String(format: "%02x", $0) }.joined().prefix(16)
    }
}
