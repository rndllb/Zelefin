import Foundation

/// User-facing playback path: Apple’s AVPlayer versus Zelefin Direct Play.
enum PlaybackPreferences {
    static let useNativeVideoPlayerKey = "zelefin.playback.use-native-player"
    static let preferFMP4InHLSKey = "zelefin.playback.prefer-fmp4-hls"
    static let skipBackwardKey = "zelefin.playback.skip-backward-seconds"
    static let skipForwardKey = "zelefin.playback.skip-forward-seconds"
    static let maxBitrateKey = "zelefin.playback.max-bitrate"
    static let adaptiveBitrateKey = "zelefin.playback.adaptive-bitrate"
    static let autoPlayNextEpisodeKey = "zelefin.playback.autoplay-next-episode"
    static let autoSkipIntroKey = "zelefin.playback.auto-skip-intro"
    static let autoSkipCreditsKey = "zelefin.playback.auto-skip-credits"
    static let defaultRateKey = "zelefin.playback.default-rate"
    static let audioLanguageKey = "zelefin.playback.audio-language"
    static let subtitleLanguageKey = "zelefin.playback.subtitle-language"

    static var useNativeVideoPlayer: Bool {
        bool(for: useNativeVideoPlayerKey, default: false)
    }

    static var preferFMP4InHLS: Bool {
        bool(for: preferFMP4InHLSKey, default: true)
    }

    static var autoPlayNextEpisode: Bool {
        bool(for: autoPlayNextEpisodeKey, default: true)
    }

    static var autoSkipIntro: Bool {
        bool(for: autoSkipIntroKey, default: false)
    }

    static var autoSkipCredits: Bool {
        bool(for: autoSkipCreditsKey, default: false)
    }

    static var skipBackward: TimeInterval {
        PlaybackSkipInterval.resolved(storedInt(skipBackwardKey, default: 10)).time
    }

    static var skipForward: TimeInterval {
        PlaybackSkipInterval.resolved(storedInt(skipForwardKey, default: 10)).time
    }

    static var selectedQuality: PlaybackQuality {
        PlaybackQuality.resolved(storedInt(maxBitrateKey, default: 0))
    }

    static var adaptiveBitrateEnabled: Bool {
        bool(for: adaptiveBitrateKey, default: true)
    }

    static var maxStreamingBitrate: Int {
        selectedQuality.bitsPerSecond
    }

    static var defaultRate: Float {
        AVKitPlaybackSpeed.resolved(UserDefaults.standard.object(forKey: defaultRateKey) as? Double)
    }

    /// Empty / `automatic` means the server or title default. ISO language code otherwise.
    static var audioLanguageCode: String {
        get { UserDefaults.standard.string(forKey: audioLanguageKey) ?? PlaybackLanguage.automaticCode }
        set { UserDefaults.standard.set(newValue, forKey: audioLanguageKey) }
    }

    /// Empty means off. `automatic` follows the audio language with Smart subs.
    static var subtitleLanguageCode: String {
        get { UserDefaults.standard.string(forKey: subtitleLanguageKey) ?? PlaybackLanguage.automaticCode }
        set { UserDefaults.standard.set(newValue, forKey: subtitleLanguageKey) }
    }

    /// MPEG-TS HLS is only optional while Apple’s player is on. Direct Play needs fMP4.
    static func usesFMP4HLS(nativePlayer: Bool, preferFMP4: Bool) -> Bool {
        !nativePlayer || preferFMP4
    }

    static var effectivePreferFMP4InHLS: Bool {
        usesFMP4HLS(nativePlayer: useNativeVideoPlayer, preferFMP4: preferFMP4InHLS)
    }

    static func shouldAutoSkip(_ kind: SkipSegment.Kind, intro: Bool, credits: Bool) -> Bool {
        switch kind {
        case .intro: intro
        case .outro: credits
        }
    }

    static func shouldAutoSkip(_ kind: SkipSegment.Kind) -> Bool {
        shouldAutoSkip(kind, intro: autoSkipIntro, credits: autoSkipCredits)
    }

    private static func bool(for key: String, default fallback: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? fallback
    }

    private static func storedInt(_ key: String, default fallback: Int) -> Int {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.integer(forKey: key)
    }
}

enum PlaybackSkipInterval: Int, CaseIterable, Identifiable, Hashable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case thirty = 30
    case sixty = 60

    var id: Int { rawValue }
    var time: TimeInterval { TimeInterval(rawValue) }
    var title: String { "\(rawValue) seconds" }

    var backwardSymbol: String { "gobackward.\(rawValue)" }
    var forwardSymbol: String { "goforward.\(rawValue)" }

    static func resolved(_ seconds: Int) -> PlaybackSkipInterval {
        Self(rawValue: seconds) ?? .ten
    }
}

enum PlaybackQuality: Int, CaseIterable, Identifiable, Hashable {
    case auto = 0
    case mbps120 = 120_000_000
    case mbps80 = 80_000_000
    case mbps60 = 60_000_000
    case mbps40 = 40_000_000
    case mbps20 = 20_000_000
    case mbps15 = 15_000_000
    case mbps10 = 10_000_000
    case mbps8 = 8_000_000
    case mbps6 = 6_000_000
    case mbps4 = 4_000_000
    case mbps3 = 3_000_000
    case mbps2 = 2_000_000
    case kbps1500 = 1_500_000
    case mbps1 = 1_000_000
    case kbps720 = 720_000
    case kbps420 = 420_000

    var id: Int { rawValue }

    var bitsPerSecond: Int {
        self == .auto ? AVDeviceProfileFactory.maxBitrate : rawValue
    }

    var title: String {
        switch self {
        case .auto: "Auto"
        case .mbps120: "120 Mbps"
        case .mbps80: "80 Mbps"
        case .mbps60: "60 Mbps"
        case .mbps40: "40 Mbps"
        case .mbps20: "20 Mbps"
        case .mbps15: "15 Mbps"
        case .mbps10: "10 Mbps"
        case .mbps8: "8 Mbps"
        case .mbps6: "6 Mbps"
        case .mbps4: "4 Mbps"
        case .mbps3: "3 Mbps"
        case .mbps2: "2 Mbps"
        case .kbps1500: "1.5 Mbps"
        case .mbps1: "1 Mbps"
        case .kbps720: "720 kbps"
        case .kbps420: "420 kbps"
        }
    }

    static func resolved(_ stored: Int) -> PlaybackQuality {
        Self(rawValue: stored) ?? .auto
    }
}

struct PlaybackLaunchOptions: Hashable, Sendable {
    var quality: PlaybackQuality?
    var audioIndex: Int?
    var subtitleIndex: Int?
    var subtitlesDisabled: Bool = false
    var mediaSourceID: String?
    var skipCinemaIntros: Bool = false

    var resolvedQuality: PlaybackQuality {
        quality ?? PlaybackPreferences.selectedQuality
    }

    var subtitleStreamIndex: Int? {
        if subtitlesDisabled { return -1 }
        return subtitleIndex
    }
}

enum PlaybackChromeIdlePolicy {
    static func shouldHide(
        controlsVisible: Bool,
        isPaused: Bool,
        isScrubbing: Bool,
        settingsOpen: Bool
    ) -> Bool {
        controlsVisible && !isPaused && !isScrubbing && !settingsOpen
    }
}

enum PlaybackEpisodeAdvance {
    static func next(after current: MediaItem, in episodes: [MediaItem]) -> MediaItem? {
        guard current.kind == .episode else { return nil }
        if let index = episodes.firstIndex(where: { $0.id == current.id }) {
            let next = episodes.index(after: index)
            return next < episodes.endIndex ? episodes[next] : nil
        }
        guard let season = current.seasonIndex, let episode = current.episodeIndex else {
            return nil
        }
        return episodes.first { candidate in
            let candidateSeason = candidate.seasonIndex ?? Int.min
            let candidateEpisode = candidate.episodeIndex ?? Int.min
            return candidateSeason > season
                || (candidateSeason == season && candidateEpisode > episode)
        }
    }
}

/// Which Apple-facing decoder path should open a planned stream.
enum PlaybackPipeline: Equatable, Sendable {
    /// AVPlayer opens server HLS (remux / transcode).
    case appleNative
    /// Zelefin Direct Play: FFmpeg demuxes the container, VideoToolbox decodes, and a sample-buffer layer paints.
    case directDecode
}

enum PlaybackPipelineResolver {
    static func pipeline(for plan: PlaybackPlan) -> PlaybackPipeline {
        pipeline(
            url: plan.streamURL,
            method: plan.method,
            container: plan.container,
            videoCodec: plan.videoCodec,
            usesNativePlayer: prefersNativePlayer(
                preference: PlaybackPreferences.useNativeVideoPlayer,
                hasSidecarSubtitles: !plan.externalSubtitles.isEmpty
            )
        )
    }

    /// AVPlayer cannot overlay Silo/Jellyfin sidecar SRT/VTT files.
    static func prefersNativePlayer(preference: Bool, hasSidecarSubtitles: Bool) -> Bool {
        preference && !hasSidecarSubtitles
    }

    static func pipeline(
        url: URL,
        method: PlaybackMethod,
        container: String? = nil,
        videoCodec: String? = nil,
        usesNativePlayer: Bool = true
    ) -> PlaybackPipeline {
        if usesNativePlayer, canNativePlayerOpen(
            url: url,
            method: method,
            container: container,
            videoCodec: videoCodec
        ) {
            return .appleNative
        }
        return .directDecode
    }

    /// AVPlayer cannot demux MKV or MPEG-4 ASP. Native-on asks Jellyfin for HLS
    /// first. Silo keeps the original file — remuxing HDR there becomes a transcode.
    static func needsServerRemuxForNativePlayer(
        url: URL,
        method: PlaybackMethod,
        container: String? = nil,
        videoCodec: String? = nil,
        usesNativePlayer: Bool = true,
        keepOriginalFile: Bool = false
    ) -> Bool {
        guard usesNativePlayer, !keepOriginalFile else { return false }
        if url.isFileURL { return false }
        return !canNativePlayerOpen(url: url, method: method, container: container, videoCodec: videoCodec)
    }

    static func canNativePlayerOpen(
        url: URL,
        method: PlaybackMethod,
        container: String? = nil,
        videoCodec: String? = nil
    ) -> Bool {
        if isHLS(url) {
            return true
        }
        let ext = (container ?? url.pathExtension).lowercased()
        if ext.contains("hls") {
            return true
        }
        guard ["mp4", "m4v", "mov"].contains(ext) else {
            return false
        }
        if let codec = videoCodec?.lowercased(), nativeIncompatibleVideoCodecs.contains(codec) {
            return false
        }
        return true
    }

    static func isHLS(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        return path.hasSuffix(".m3u8") || path.contains(".m3u8")
    }

    private static let nativeIncompatibleVideoCodecs: Set<String> = [
        "mpeg4", "mpeg2video", "msmpeg4v1", "msmpeg4v2", "msmpeg4v3",
        "vc1", "wmv1", "wmv2", "wmv3"
    ]
}

/// Direct Play MKV often has Cues at EOF. A long `engine.seek` right after open can
/// time out and black the screen. Resume instead goes through Aether `load(startPosition:)`.
/// User skip / scrub still uses `engine.seek` once the session is running.
enum DirectPlaySeekPolicy {
    static func allowsAutomaticResumeSeek(_ pipeline: PlaybackPipeline) -> Bool {
        pipeline == .appleNative
    }
}

/// Where playback should begin. Direct Play files start at t=0 on the byte stream,
/// so the client must open at the saved playhead. Jellyfin plans always set
/// `clientOwnsPlayhead` because their HLS URLs carry no `StartTimeTicks` (see
/// `StreamResumeURL`). Silo `original_http` is Direct Play of the full file.
enum PlaybackResumePolicy {
    static let threshold: TimeInterval = 5

    static func clientStartPosition(
        method: PlaybackMethod,
        startTime: TimeInterval,
        clientOwnsPlayhead: Bool = false
    ) -> TimeInterval? {
        guard startTime > threshold else { return nil }
        guard method == .directPlay || clientOwnsPlayhead else { return nil }
        return startTime
    }

    static func reportStartPosition(playhead: TimeInterval, plannedStart: TimeInterval) -> TimeInterval {
        plannedStart > threshold ? max(playhead, plannedStart) : playhead
    }

    /// Direct Play opened at t=0 even though resume was requested. Seek after the first
    /// frame once the file index exists — not immediately at load, which times out on MKV.
    static func needsDeferredSeek(
        method: PlaybackMethod,
        playhead: TimeInterval,
        plannedStart: TimeInterval,
        clientOwnsPlayhead: Bool = false
    ) -> Bool {
        (method == .directPlay || clientOwnsPlayhead)
            && plannedStart > threshold
            && playhead <= threshold
    }
}

enum StreamResumeURL {
    /// Jellyfin 12.1 copies `StartTimeTicks` from the playlist URL onto the fMP4 init and
    /// every segment URL, then rejects those segments with 400 ("StartTimeTicks is not
    /// allowed"). HLS must open at t=0 and let the player seek to the resume point.
    static func strippingStartTimeTicks(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems
        else { return url }
        let kept = items.filter { $0.name.compare("StartTimeTicks", options: .caseInsensitive) != .orderedSame }
        guard kept.count != items.count else { return url }
        components.queryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }
}

/// Latest-wins queue for Direct Play seeks. Rapid scrubs must not stack `engine.seek`
/// calls: a superseded seek can tear down the session (`noActiveSession`) and reload
/// from t=0.
enum DirectPlaySeekCoalesce {
    /// Stores `latest` as the pending target. Returns true when the caller should
    /// start a drain loop; false when a drain is already in flight.
    static func enqueue(
        pending: inout TimeInterval?,
        latest: TimeInterval,
        isDraining: Bool
    ) -> Bool {
        pending = latest
        return !isDraining
    }
}

/// Jellyfin progress follows the on-screen frame. Direct Play jumps its clock to the
/// scrub target before video lands; reporting that makes the server think the skip
/// worked while the iPad is still on the previous picture.
enum DirectPlayProgressPolicy {
    static func shouldReport(playheadTrusted: Bool) -> Bool {
        playheadTrusted
    }

    static func playheadTrusted(after outcome: DirectPlaySeekEvent.Outcome) -> Bool {
        switch outcome {
        case .landed, .rejected:
            true
        case .began, .stalled, .superseded:
            false
        }
    }
}
