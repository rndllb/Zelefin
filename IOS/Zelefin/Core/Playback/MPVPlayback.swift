import AVFoundation
import UIKit
import Foundation
import ZelefinMPV

/// libmpv playing into an `AVSampleBufferDisplayLayer` through `vo_avfoundation`. mpv demuxes and
/// decodes (VideoToolbox), renders subtitles with libass into the frames, and switches audio and
/// subtitle tracks in-process, so every track in the file is choosable without a server round trip.
@MainActor
final class MPVPlayback {
    struct Track: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case audio
            case subtitle
        }

        let id: Int
        let kind: Kind
        /// FFmpeg stream index inside the file. Matches Jellyfin's `MediaStream.Index` for embedded
        /// streams of a file played as-is; nil for external subtitles.
        let streamIndex: Int?
        let language: String?
        let title: String?
        let codec: String?
        let channels: Int?
        let isExternal: Bool
        let isDefault: Bool
        let isForced: Bool
    }

    enum Event: Sendable {
        case time(Double)
        case duration(Double)
        case paused(Bool)
        case buffering(Bool)
        case firstFrame
        case tracks([Track])
        case audioSelected(Int?)
        case subtitleSelected(Int?)
        case videoSize(CGSize)
        case ended
        case failed(String)
    }

    struct Source {
        var url: URL
        var headers: [String: String]
        var startPosition: TimeInterval?
        var externalSubtitles: [ExternalSubtitleSidecar]
    }

    let displayLayer = AVSampleBufferDisplayLayer()
    var onEvent: (Event) -> Void = { _ in }

    private let core: MPVCore

    init() throws {
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        core = try MPVCore(layer: displayLayer)
        core.onEvent = { [weak self] event in
            Task { @MainActor in self?.onEvent(event) }
        }
    }

    func load(_ source: Source) {
        core.load(source)
    }

    func play() { core.setFlag("pause", false) }
    func pause() { core.setFlag("pause", true) }
    func seek(to seconds: TimeInterval) { core.command(["seek", String(format: "%.3f", seconds), "absolute"]) }
    func setRate(_ rate: Float) { core.setString("speed", String(format: "%.3f", rate)) }
    func selectAudio(_ id: Int) { core.setString("aid", String(id)) }
    func selectSubtitle(_ id: Int?) { core.setString("sid", id.map(String.init) ?? "no") }

    func setFillsScreen(_ fills: Bool) {
        displayLayer.videoGravity = fills ? .resizeAspectFill : .resizeAspect
    }

    /// mpv's own view of the session, for the stats overlay.
    func stats() -> MPVStats {
        core.stats()
    }

    func stop() {
        core.shutdown()
    }
}

/// Owns the mpv handle off the main actor. mpv's client API is thread-safe; events are drained on
/// one serial queue and handed out through `onEvent`.
private final class MPVCore: @unchecked Sendable {
    var onEvent: @Sendable (MPVPlayback.Event) -> Void = { _ in }

    private let queue = DispatchQueue(label: "app.zelefin.mpv", qos: .userInitiated)
    private var handle: OpaquePointer?
    /// vo_avfoundation keeps a raw pointer to the layer, so the layer must outlive the core.
    private let layer: AVSampleBufferDisplayLayer
    private var pendingSubtitles: [ExternalSubtitleSidecar] = []
    private var sawFirstFrame = false
    private var lastReportedTime: Double = -1
    private var isShutDown = false

    private static var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private enum Observed: UInt64 {
        case timePos = 1, duration, pause, pausedForCache, seeking, eofReached, trackCount, aid, sid, width, height
    }

    init(layer: AVSampleBufferDisplayLayer) throws {
        self.layer = layer
        guard let handle = mpv_create() else { throw ZelefinError.playbackEngineUnavailable }
        self.handle = handle

        var wid = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &wid)
        let options: [(String, String)] = [
            ("vo", "avfoundation"),
            // On a device, subtitles are drawn into the frames so they also show in Picture in
            // Picture. Core Image can't composite the simulator's software-decoded frames, so the
            // simulator keeps mpv's separate subtitle overlay and decodes in software.
            ("avfoundation-composite-osd", Self.isSimulator ? "no" : "yes"),
            ("hwdec", Self.isSimulator ? "no" : "videotoolbox"),
            ("hwdec-codecs", "all"),
            ("hwdec-software-fallback", "yes"),
            ("target-colorspace-hint", "yes"),
            ("ao", "audiounit"),
            ("keep-open", "yes"),
            ("idle", "yes"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("ytdl", "no"),
            ("terminal", "no"),
            ("msg-level", "all=warn"),
            ("cache", "yes"),
            ("demuxer-max-bytes", "150MiB"),
            ("demuxer-max-back-bytes", "50MiB"),
            ("sub-auto", "no"),
            ("subs-fallback", "yes"),
            ("sub-scale-with-window", "no"),
            ("sub-use-margins", "no"),
            ("embeddedfonts", "yes"),
        ]
        for (name, value) in options {
            mpv_set_option_string(handle, name, value)
        }
        guard mpv_initialize(handle) >= 0 else {
            mpv_terminate_destroy(handle)
            self.handle = nil
            throw ZelefinError.playbackEngineUnavailable
        }

        observe("time-pos", MPV_FORMAT_DOUBLE, .timePos)
        observe("duration", MPV_FORMAT_DOUBLE, .duration)
        observe("pause", MPV_FORMAT_FLAG, .pause)
        observe("paused-for-cache", MPV_FORMAT_FLAG, .pausedForCache)
        observe("seeking", MPV_FORMAT_FLAG, .seeking)
        observe("eof-reached", MPV_FORMAT_FLAG, .eofReached)
        observe("track-list/count", MPV_FORMAT_INT64, .trackCount)
        observe("aid", MPV_FORMAT_STRING, .aid)
        observe("sid", MPV_FORMAT_STRING, .sid)
        observe("video-params/dw", MPV_FORMAT_INT64, .width)
        observe("video-params/dh", MPV_FORMAT_INT64, .height)

        mpv_set_wakeup_callback(handle, { context in
            guard let context else { return }
            Unmanaged<MPVCore>.fromOpaque(context).takeUnretainedValue().drainSoon()
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
        }
    }

    func load(_ source: MPVPlayback.Source) {
        queue.async { [self] in
            guard let handle, !isShutDown else { return }
            pendingSubtitles = source.externalSubtitles
            sawFirstFrame = false
            mpv_set_option_string(handle, "http-header-fields", Self.headerList(source.headers))
            if let start = source.startPosition, start > 0 {
                mpv_set_option_string(handle, "start", String(format: "%.3f", start))
            } else {
                mpv_set_option_string(handle, "start", "none")
            }
            let target = source.url.isFileURL ? source.url.path : source.url.absoluteString
            runCommand(handle, ["loadfile", target, "replace"])
        }
    }

    func command(_ args: [String]) {
        queue.async { [self] in
            guard let handle, !isShutDown else { return }
            runCommand(handle, args)
        }
    }

    func setString(_ name: String, _ value: String) {
        queue.async { [self] in
            guard let handle, !isShutDown else { return }
            mpv_set_property_string(handle, name, value)
        }
    }

    func setFlag(_ name: String, _ value: Bool) {
        setString(name, value ? "yes" : "no")
    }

    /// Read on the core's queue so a read can never race `mpv_terminate_destroy`.
    func stats() -> MPVStats {
        queue.sync { [self] in
            guard let handle, !isShutDown else { return MPVStats() }
            func text(_ name: String) -> String? { stringProperty(handle, name) }
            func number(_ name: String) -> Double? {
                var value: Double = 0
                return mpv_get_property(handle, name, MPV_FORMAT_DOUBLE, &value) >= 0 ? value : nil
            }
            return MPVStats(
                videoCodec: text("video-format"),
                videoCodecDescription: text("video-codec"),
                width: intProperty(handle, "video-params/w"),
                height: intProperty(handle, "video-params/h"),
                displayWidth: intProperty(handle, "dwidth"),
                displayHeight: intProperty(handle, "dheight"),
                frameRate: number("container-fps"),
                estimatedFrameRate: number("estimated-vf-fps"),
                videoBitrate: number("video-bitrate"),
                pixelFormat: text("video-params/pixelformat"),
                hardwarePixelFormat: text("video-params/hw-pixelformat"),
                primaries: text("video-params/primaries"),
                transfer: text("video-params/gamma"),
                colorMatrix: text("video-params/colormatrix"),
                container: text("file-format"),
                hardwareDecoder: text("hwdec-current"),
                videoOutput: text("current-vo"),
                audioOutput: text("current-ao"),
                audioCodec: text("audio-codec-name"),
                audioCodecDescription: text("audio-codec"),
                audioChannels: text("audio-params/channels"),
                audioSampleRate: intProperty(handle, "audio-params/samplerate"),
                audioBitrate: number("audio-bitrate"),
                audioLanguage: text("current-tracks/audio/lang"),
                audioTitle: text("current-tracks/audio/title"),
                subtitleCodec: text("current-tracks/sub/codec"),
                subtitleLanguage: text("current-tracks/sub/lang"),
                subtitleTitle: text("current-tracks/sub/title"),
                cacheSeconds: number("demuxer-cache-duration"),
                cacheSpeed: number("cache-speed"),
                droppedFrames: intProperty(handle, "frame-drop-count"),
                decoderDroppedFrames: intProperty(handle, "decoder-frame-drop-count"),
                avSync: number("avsync"),
                isBuffering: text("paused-for-cache") == "yes",
                isSeeking: text("seeking") == "yes"
            )
        }
    }

    func shutdown() {
        queue.async { [self] in
            guard let handle, !isShutDown else { return }
            isShutDown = true
            mpv_set_wakeup_callback(handle, nil, nil)
            runCommand(handle, ["stop"])
            mpv_terminate_destroy(handle)
            self.handle = nil
        }
    }

    // MARK: - Events

    private func drainSoon() {
        queue.async { [self] in drain() }
    }

    private func drain() {
        guard let handle, !isShutDown else { return }
        while let event = mpv_wait_event(handle, 0), event.pointee.event_id != MPV_EVENT_NONE {
            process(event.pointee, on: handle)
            if isShutDown { return }
        }
    }

    private func process(_ event: mpv_event, on handle: OpaquePointer) {
        switch event.event_id {
        case MPV_EVENT_PROPERTY_CHANGE:
            guard let data = event.data else { return }
            propertyChanged(data.assumingMemoryBound(to: mpv_event_property.self).pointee,
                            id: event.reply_userdata, on: handle)
        case MPV_EVENT_FILE_LOADED:
            addPendingSubtitles(on: handle)
            publishTracks(on: handle)
        case MPV_EVENT_PLAYBACK_RESTART:
            if !sawFirstFrame {
                sawFirstFrame = true
                onEvent(.firstFrame)
            }
            onEvent(.buffering(false))
        case MPV_EVENT_END_FILE:
            guard let data = event.data else { return }
            let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
            if end.reason == MPV_END_FILE_REASON_ERROR {
                let message = String(cString: mpv_error_string(end.error))
                onEvent(.failed("mpv could not play this stream (\(message))."))
            }
        default:
            break
        }
    }

    private func propertyChanged(_ property: mpv_event_property, id: UInt64, on handle: OpaquePointer) {
        guard let observed = Observed(rawValue: id) else { return }
        switch observed {
        case .timePos:
            guard let seconds = double(property), seconds.isFinite else { return }
            // time-pos moves every frame; the player only needs a few updates a second.
            guard abs(seconds - lastReportedTime) >= 0.2 else { return }
            lastReportedTime = seconds
            onEvent(.time(seconds))
        case .duration:
            if let seconds = double(property), seconds.isFinite, seconds > 0 { onEvent(.duration(seconds)) }
        case .pause:
            onEvent(.paused(flag(property) ?? false))
        case .pausedForCache, .seeking:
            onEvent(.buffering(flag(property) ?? false))
        case .eofReached:
            if flag(property) == true { onEvent(.ended) }
        case .trackCount:
            publishTracks(on: handle)
        case .aid:
            onEvent(.audioSelected(string(property).flatMap(Int.init)))
        case .sid:
            onEvent(.subtitleSelected(string(property).flatMap(Int.init)))
        case .width, .height:
            let width = intProperty(handle, "video-params/dw") ?? 0
            let height = intProperty(handle, "video-params/dh") ?? 0
            if width > 0, height > 0 { onEvent(.videoSize(CGSize(width: width, height: height))) }
        }
    }

    private func addPendingSubtitles(on handle: OpaquePointer) {
        let sidecars = pendingSubtitles
        pendingSubtitles = []
        for sidecar in sidecars {
            // "auto" adds the track without switching to it; Zelefin picks the track afterwards.
            runCommand(handle, ["sub-add", sidecar.url.absoluteString, "auto", sidecar.name, sidecar.language ?? ""])
        }
    }

    private func publishTracks(on handle: OpaquePointer) {
        let count = intProperty(handle, "track-list/count") ?? 0
        var tracks: [MPVPlayback.Track] = []
        for index in 0..<max(0, count) {
            let prefix = "track-list/\(index)/"
            let kind: MPVPlayback.Track.Kind
            switch stringProperty(handle, prefix + "type") {
            case "audio": kind = .audio
            case "sub": kind = .subtitle
            default: continue
            }
            guard let id = intProperty(handle, prefix + "id") else { continue }
            tracks.append(MPVPlayback.Track(
                id: id,
                kind: kind,
                streamIndex: intProperty(handle, prefix + "ff-index"),
                language: stringProperty(handle, prefix + "lang"),
                title: stringProperty(handle, prefix + "title"),
                codec: stringProperty(handle, prefix + "codec"),
                channels: intProperty(handle, prefix + "demux-channel-count"),
                isExternal: stringProperty(handle, prefix + "external") == "yes",
                isDefault: stringProperty(handle, prefix + "default") == "yes",
                isForced: stringProperty(handle, prefix + "forced") == "yes"
            ))
        }
        onEvent(.tracks(tracks))
    }

    // MARK: - mpv helpers

    private func observe(_ name: String, _ format: mpv_format, _ id: Observed) {
        guard let handle else { return }
        mpv_observe_property(handle, id.rawValue, name, format)
    }

    private func runCommand(_ handle: OpaquePointer, _ args: [String]) {
        var cStrings = args.map { strdup($0) }
        cStrings.append(nil)
        defer { cStrings.forEach { free($0) } }
        cStrings.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress?.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buffer.count) {
                _ = mpv_command(handle, $0)
            }
        }
    }

    private func stringProperty(_ handle: OpaquePointer, _ name: String) -> String? {
        guard let raw = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(raw) }
        let value = String(cString: raw)
        return value.isEmpty ? nil : value
    }

    private func intProperty(_ handle: OpaquePointer, _ name: String) -> Int? {
        var value: Int64 = 0
        guard mpv_get_property(handle, name, MPV_FORMAT_INT64, &value) >= 0 else { return nil }
        return Int(value)
    }

    private func double(_ property: mpv_event_property) -> Double? {
        guard property.format == MPV_FORMAT_DOUBLE, let data = property.data else { return nil }
        return data.assumingMemoryBound(to: Double.self).pointee
    }

    private func flag(_ property: mpv_event_property) -> Bool? {
        guard property.format == MPV_FORMAT_FLAG, let data = property.data else { return nil }
        return data.assumingMemoryBound(to: Int32.self).pointee != 0
    }

    private func string(_ property: mpv_event_property) -> String? {
        guard property.format == MPV_FORMAT_STRING, let data = property.data,
              let pointer = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else { return nil }
        return String(cString: pointer)
    }

    /// mpv's list syntax: entries separated by commas, so a comma inside a value is escaped.
    static func headerList(_ headers: [String: String]) -> String {
        headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)".replacingOccurrences(of: ",", with: "\\,") }
            .joined(separator: ",")
    }
}

/// A snapshot of mpv properties; nil where mpv has no value yet (before the first frame, audio-only).
struct MPVStats: Equatable, Sendable {
    var videoCodec: String?
    var videoCodecDescription: String?
    var width: Int?
    var height: Int?
    var displayWidth: Int?
    var displayHeight: Int?
    var frameRate: Double?
    var estimatedFrameRate: Double?
    var videoBitrate: Double?
    var pixelFormat: String?
    var hardwarePixelFormat: String?
    var primaries: String?
    var transfer: String?
    var colorMatrix: String?
    var container: String?
    var hardwareDecoder: String?
    var videoOutput: String?
    var audioOutput: String?
    var audioCodec: String?
    var audioCodecDescription: String?
    var audioChannels: String?
    var audioSampleRate: Int?
    var audioBitrate: Double?
    var audioLanguage: String?
    var audioTitle: String?
    var subtitleCodec: String?
    var subtitleLanguage: String?
    var subtitleTitle: String?
    var cacheSeconds: Double?
    var cacheSpeed: Double?
    var droppedFrames: Int?
    var decoderDroppedFrames: Int?
    var avSync: Double?
    var isBuffering = false
    var isSeeking = false

    /// "HDR10", "HLG" or "SDR" from the transfer function mpv reports, with the primaries.
    var rangeLabel: String {
        guard let transfer else { return "—" }
        let range: String
        switch transfer.lowercased() {
        case "pq": range = "HDR10 (PQ)"
        case "hlg": range = "HLG"
        default: range = "SDR"
        }
        guard let primaries else { return range }
        return "\(range) · \(primaries.uppercased())"
    }

    /// mpv reports channel layouts like "5.1(side)"; the side/back detail means nothing to a viewer.
    var channelLabel: String? {
        guard let audioChannels else { return nil }
        let layout = audioChannels.components(separatedBy: "(").first ?? audioChannels
        switch layout {
        case "mono": return "Mono"
        case "stereo": return "Stereo"
        default: return layout
        }
    }
}

/// Maps between Jellyfin's stream numbers and mpv's per-type track ids.
enum MPVTrackMatch {
    /// The mpv track for Jellyfin's pick: by stream index for a file played as-is, else by language.
    static func track(
        for jellyfinIndex: Int?,
        language: String?,
        in tracks: [MPVPlayback.Track],
        kind: MPVPlayback.Track.Kind
    ) -> MPVPlayback.Track? {
        let candidates = tracks.filter { $0.kind == kind }
        if let jellyfinIndex, let exact = candidates.first(where: { !$0.isExternal && $0.streamIndex == jellyfinIndex }) {
            return exact
        }
        guard let wanted = NativeLanguage.alpha2(language) else { return nil }
        return candidates.first { NativeLanguage.alpha2($0.language) == wanted }
    }

    static func title(for track: MPVPlayback.Track) -> String {
        var parts: [String] = []
        if let name = NativeLanguage.displayName(track.language) {
            parts.append(name)
        }
        if let title = track.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
           !parts.contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }),
           !(track.isForced && title.caseInsensitiveCompare("Forced") == .orderedSame) {
            parts.append(title)
        }
        if parts.isEmpty { parts.append(track.kind == .audio ? "Track \(track.id)" : "Subtitle \(track.id)") }
        var detail: [String] = []
        if let codec = track.codec { detail.append(codecLabel(codec)) }
        if let channels = track.channels, track.kind == .audio { detail.append(channelLabel(channels)) }
        if track.isForced { detail.append("Forced") }
        if track.isExternal { detail.append("External") }
        return ([parts.joined(separator: " · ")] + (detail.isEmpty ? [] : [detail.joined(separator: " ")]))
            .joined(separator: " — ")
    }

    private static func codecLabel(_ codec: String) -> String {
        switch codec.lowercased() {
        case "subrip", "srt": "SRT"
        case "ass", "ssa": "ASS"
        case "hdmv_pgs_subtitle", "pgssub": "PGS"
        case "dvd_subtitle", "dvdsub": "VobSub"
        case "webvtt": "WebVTT"
        case "mov_text": "Text"
        case "eac3": "E-AC-3"
        case "ac3": "AC-3"
        case "truehd": "TrueHD"
        case "dts": "DTS"
        default: codec.uppercased()
        }
    }

    private static func channelLabel(_ channels: Int) -> String {
        switch channels {
        case 1: "Mono"
        case 2: "Stereo"
        case 6: "5.1"
        case 8: "7.1"
        default: "\(channels)ch"
        }
    }
}

/// Jellyfin tags tracks with ISO 639-2 codes ("jpn"); mpv and AVFoundation use BCP 47 ("ja").
enum NativeLanguage {
    static func alpha2(_ code: String?) -> String? {
        guard let code, !code.isEmpty, code.lowercased() != "und" else { return nil }
        let base = (code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code).lowercased()
        let terminology = bibliographic[base] ?? base
        return Locale.LanguageCode(terminology).identifier(.alpha2) ?? (base.count == 2 ? base : nil)
    }

    /// ISO 639-2/B codes Jellyfin and Emby still write ("ger"), which `Locale` only knows in their
    /// terminology form ("deu").
    private static let bibliographic: [String: String] = [
        "alb": "sqi", "arm": "hye", "baq": "eus", "bur": "mya", "chi": "zho", "cze": "ces", "dut": "nld",
        "fre": "fra", "geo": "kat", "ger": "deu", "gre": "ell", "ice": "isl", "mac": "mkd", "mao": "mri",
        "may": "msa", "per": "fas", "rum": "ron", "slo": "slk", "tib": "bod", "wel": "cym",
    ]

    static func displayName(_ code: String?) -> String? {
        guard let alpha2 = alpha2(code) else { return nil }
        return Locale.current.localizedString(forLanguageCode: alpha2)
    }
}
