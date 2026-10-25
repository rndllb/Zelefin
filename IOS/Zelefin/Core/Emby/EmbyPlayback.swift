import Foundation
import JellyfinAPI

/// The parts of Emby's PlaybackInfo and item JSON the shared DTOs have no field for.
struct EmbyChapter: Decodable, Hashable, Sendable {
    var startPositionTicks: Int64?
    var name: String?
    var markerType: String?
    var imageTag: String?
    var chapterIndex: Int?

    enum CodingKeys: String, CodingKey {
        case startPositionTicks = "StartPositionTicks"
        case name = "Name"
        case markerType = "MarkerType"
        case imageTag = "ImageTag"
        case chapterIndex = "ChapterIndex"
    }

    var startTime: TimeInterval? {
        startPositionTicks.map { TickClock.seconds(from: $0) }
    }

    var isMarker: Bool {
        guard let markerType else { return false }
        return markerType.caseInsensitiveCompare("Chapter") != .orderedSame
    }
}

struct EmbyMediaSourceExtras: Decodable, Sendable {
    var id: String?
    var directStreamURL: String?
    var chapters: [EmbyChapter]?
    var runTimeTicks: Int64?

    enum CodingKeys: String, CodingKey {
        case id = "Id"
        case directStreamURL = "DirectStreamUrl"
        case chapters = "Chapters"
        case runTimeTicks = "RunTimeTicks"
    }
}

struct EmbyPlaybackExtras: Decodable, Sendable {
    var mediaSources: [EmbyMediaSourceExtras]?
    var chapters: [EmbyChapter]?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources"
        case chapters = "Chapters"
    }

    func source(id: String?) -> EmbyMediaSourceExtras? {
        mediaSources?.first(where: { $0.id == id }) ?? mediaSources?.first
    }
}

enum EmbyPlayback {
    /// Emby media source ids look like `mediasource_1093`, not the item id.
    static func selectSource(_ sources: [MediaSourceInfo], requested: String?) -> MediaSourceInfo? {
        if let requested, let match = sources.first(where: { $0.id == requested }) {
            return match
        }
        return sources.first
    }

    /// Direct Play and Direct Stream use the `DirectStreamUrl` Emby returns (already carrying the
    /// play session and media source); a transcode uses its HLS `TranscodingUrl`.
    static func streamURL(
        itemID: String,
        source: MediaSourceInfo,
        directStreamPath: String?,
        serverURL: URL,
        token: String
    ) throws -> URL {
        let method = ItemMapper.playbackMethod(from: source)
        if method != .directPlay, let transcoding = source.transcodingURL, !transcoding.isEmpty {
            guard let url = ServerURL.resolve(base: serverURL, path: transcoding, token: token) else {
                throw ZelefinError.missingStreamURL
            }
            return StreamResumeURL.strippingStartTimeTicks(url)
        }
        if let directStreamPath, !directStreamPath.isEmpty,
           let url = ServerURL.resolve(base: serverURL, path: directStreamPath, token: token) {
            return url
        }
        let container = StreamContainer.pathExtension(from: source)
        var query = "Static=true"
        if let sourceID = source.id, !sourceID.isEmpty {
            query += "&MediaSourceId=\(sourceID)"
        }
        guard let url = ServerURL.resolve(
            base: serverURL,
            path: "/Videos/\(itemID)/stream.\(container)?\(query)",
            token: token
        ) else {
            throw ZelefinError.missingStreamURL
        }
        return url
    }

    /// Chapters for the scrubber. Intro and credits markers are skip ranges, not chapters.
    static func chapters(from raw: [EmbyChapter]) -> [MediaChapter] {
        raw.enumerated().compactMap { offset, chapter in
            guard !chapter.isMarker, let start = chapter.startTime else { return nil }
            let index = chapter.chapterIndex ?? offset
            let name = chapter.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return MediaChapter(
                index: index,
                name: name.isEmpty ? "Chapter \(index + 1)" : name,
                startTime: start,
                imageTag: chapter.imageTag
            )
        }
    }

    /// Emby's intro detection writes `IntroStart` / `IntroEnd` / `CreditsStart` markers. Libraries
    /// without marker detection often still name chapters "Intro" and "Credits", so those count too.
    static func skipSegments(from raw: [EmbyChapter], runtime: TimeInterval?) -> [SkipSegment] {
        let ordered = raw
            .compactMap { chapter in chapter.startTime.map { (chapter, $0) } }
            .sorted { $0.1 < $1.1 }
        func marker(_ type: String) -> [TimeInterval] {
            ordered.filter { $0.0.markerType?.caseInsensitiveCompare(type) == .orderedSame }.map(\.1)
        }

        var segments: [SkipSegment] = []
        if let introStart = marker("IntroStart").first,
           let introEnd = marker("IntroEnd").first(where: { $0 > introStart }) {
            segments.append(SkipSegment(kind: .intro, start: introStart, end: introEnd))
        }
        if let creditsStart = marker("CreditsStart").first, let runtime, runtime > creditsStart {
            segments.append(SkipSegment(kind: .outro, start: creditsStart, end: runtime))
        }

        let chapters = ordered.filter { !$0.0.isMarker }
        func namedRange(_ name: String) -> (TimeInterval, TimeInterval)? {
            guard let position = chapters.firstIndex(where: {
                $0.0.name?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(name) == .orderedSame
            }) else { return nil }
            let start = chapters[position].1
            let end = position + 1 < chapters.count ? chapters[position + 1].1 : runtime
            guard let end, end > start else { return nil }
            return (start, end)
        }
        if !segments.contains(where: { $0.kind == .intro }), let range = namedRange("Intro") {
            segments.append(SkipSegment(kind: .intro, start: range.0, end: range.1))
        }
        if !segments.contains(where: { $0.kind == .outro }), let range = namedRange("Credits") {
            segments.append(SkipSegment(kind: .outro, start: range.0, end: range.1))
        }
        return segments.filter { $0.end - $0.start >= 3 }
    }

    static func playMethod(_ method: PlaybackMethod) -> String {
        switch method {
        case .directPlay: "DirectPlay"
        case .remux: "DirectStream"
        case .transcode: "Transcode"
        }
    }

    /// The device profile Jellyfin gets, minus codec conditions on `VideoRangeType`, a property
    /// Emby does not have.
    static func deviceProfileBody(maxBitrate: Int) throws -> Data {
        var profile = AVDeviceProfileFactory.make(
            preferFMP4InHLS: PlaybackPreferences.effectivePreferFMP4InHLS,
            maxBitrate: maxBitrate
        )
        profile.codecProfiles = nil
        let encoded = try JSONEncoder().encode(profile)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try JSONSerialization.data(withJSONObject: ["DeviceProfile": object])
    }
}

@MainActor
final class EmbyPlaybackReporter: PlaybackReporting {
    private let api: EmbyAPI
    private let plan: PlaybackPlan
    private var lastReport: TimeInterval = 0

    init(api: EmbyAPI, plan: PlaybackPlan) {
        self.api = api
        self.plan = plan
    }

    func started(at position: TimeInterval) async {
        await post("/Sessions/Playing", Self.body(plan: plan, position: position, isPaused: false))
        lastReport = position
    }

    func progress(at position: TimeInterval, isPaused: Bool) async {
        guard abs(position - lastReport) >= 10 || isPaused else { return }
        lastReport = position
        var json = Self.body(plan: plan, position: position, isPaused: isPaused)
        json["EventName"] = "TimeUpdate"
        await post("/Sessions/Playing/Progress", json)
    }

    func stopped(at position: TimeInterval) async {
        await post("/Sessions/Playing/Stopped", Self.body(plan: plan, position: position, isPaused: false))
        if let liveStreamID = plan.liveStreamID, !liveStreamID.isEmpty {
            _ = try? await api.data("POST", "/LiveStreams/Close", query: [("LiveStreamId", liveStreamID)])
        }
    }

    private func post(_ path: String, _ json: [String: Any]) async {
        guard let body = try? JSONSerialization.data(withJSONObject: json) else { return }
        _ = try? await api.data("POST", path, body: body)
    }

    nonisolated static func body(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) -> [String: Any] {
        var json: [String: Any] = [
            "ItemId": plan.item.id,
            "PositionTicks": TickClock.intTicks(from: position),
            "IsPaused": isPaused,
            "CanSeek": !plan.isLive,
            "PlayMethod": EmbyPlayback.playMethod(plan.method)
        ]
        if let mediaSourceID = plan.mediaSourceID { json["MediaSourceId"] = mediaSourceID }
        if let playSessionID = plan.playSessionID { json["PlaySessionId"] = playSessionID }
        if let liveStreamID = plan.liveStreamID { json["LiveStreamId"] = liveStreamID }
        if let audio = plan.audioTracks.first(where: \.isSelected)?.id { json["AudioStreamIndex"] = audio }
        if let subtitle = plan.subtitleTracks.first(where: \.isSelected)?.id { json["SubtitleStreamIndex"] = subtitle }
        return json
    }
}
