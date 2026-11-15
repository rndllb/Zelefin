import Foundation
import Observation
#if canImport(GoogleCast)
import GoogleCast
#endif

/// Chromecast sender for the Default Media Receiver. Functional on iPhone/iPad (and Catalyst
/// when the dynamic Cast SDK is linked); no-ops where GoogleCast is unavailable.
@MainActor
@Observable
final class CastManager: NSObject {
    static let shared = CastManager()

    private(set) var isCastAvailable = false
    private(set) var isConnected = false
    private(set) var isConnecting = false
    private(set) var isPaused = false
    private(set) var volume: Float = 1
    private(set) var nowPlayingTitle: String?
    private(set) var nowPlayingItemID: String?
    private(set) var playbackFinishedCount = 0
    private(set) var deviceName: String?
    /// Kept across session teardown so local playback can resume at the TV playhead.
    private(set) var lastKnownPositionSeconds: TimeInterval?

    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var lastStatusWasFinished = false

    private override init() {
        super.init()
    }

    func start() {
        #if canImport(GoogleCast)
        guard !didStart else { return }
        didStart = true
        let criteria = GCKDiscoveryCriteria(applicationID: kGCKDefaultMediaReceiverApplicationID)
        let options = GCKCastOptions(discoveryCriteria: criteria)
        options.physicalVolumeButtonsWillControlDeviceVolume = true
        GCKCastContext.setSharedInstanceWith(options)
        GCKCastContext.sharedInstance().sessionManager.add(self)
        isCastAvailable = true
        #endif
    }

    struct SubtitleTrack: Sendable {
        let id: Int
        let url: URL
        let languageCode: String?
        let name: String?
    }

    func loadMedia(
        itemID: String,
        streamURL: URL,
        title: String,
        subtitle: String?,
        posterImageURL: URL?,
        contentType: String,
        startPositionSeconds: TimeInterval,
        subtitleTracks: [SubtitleTrack] = [],
        activeSubtitleTrackID: Int? = nil,
        isTransportStreamHLS: Bool = false,
        isLive: Bool = false
    ) {
        #if canImport(GoogleCast)
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else {
            return
        }
        nowPlayingTitle = title
        nowPlayingItemID = itemID

        let metadata = GCKMediaMetadata(metadataType: .movie)
        metadata.setString(title, forKey: kGCKMetadataKeyTitle)
        if let subtitle {
            metadata.setString(subtitle, forKey: kGCKMetadataKeySubtitle)
        }
        if let posterImageURL {
            metadata.addImage(GCKImage(url: posterImageURL, width: 480, height: 720))
        }

        let infoBuilder = GCKMediaInformationBuilder(contentURL: streamURL)
        infoBuilder.contentType = contentType
        infoBuilder.streamType = isLive ? .live : .buffered
        infoBuilder.metadata = metadata
        infoBuilder.customData = [Self.itemIDKey: itemID]
        if isTransportStreamHLS {
            infoBuilder.hlsSegmentFormat = .TS_AAC
            infoBuilder.hlsVideoSegmentFormat = .MPEG2_TS
        }
        infoBuilder.mediaTracks = subtitleTracks.compactMap {
            GCKMediaTrack(
                identifier: $0.id,
                contentIdentifier: $0.url.absoluteString,
                contentType: "text/vtt",
                type: .text,
                textSubtype: .subtitles,
                name: $0.name,
                languageCode: $0.languageCode,
                customData: nil
            )
        }

        let requestBuilder = GCKMediaLoadRequestDataBuilder()
        requestBuilder.mediaInformation = infoBuilder.build()
        if !isLive {
            requestBuilder.startTime = startPositionSeconds
        }
        requestBuilder.autoplay = true
        if let activeSubtitleTrackID {
            requestBuilder.activeTrackIDs = [NSNumber(value: activeSubtitleTrackID)]
        }
        client.loadMedia(with: requestBuilder.build())
        #endif
    }

    private nonisolated static let itemIDKey = "zelefinItemId"

    func setActiveSubtitleTrack(id: Int?) {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?
            .setActiveTrackIDs(id.map { [NSNumber(value: $0)] } ?? [])
        #endif
    }

    func setVolume(_ volume: Float) {
        let clamped = min(max(volume, 0), 1)
        self.volume = clamped
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?
            .setStreamVolume(clamped)
        #endif
    }

    func play() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.play()
        #endif
    }

    func pause() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?.pause()
        #endif
    }

    func togglePlayPause() {
        if isPaused { play() } else { pause() }
    }

    func seek(toSeconds seconds: TimeInterval) {
        #if canImport(GoogleCast)
        guard let client = GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient else {
            return
        }
        let options = GCKMediaSeekOptions()
        options.interval = seconds
        client.seek(with: options)
        lastKnownPositionSeconds = seconds
        #endif
    }

    func currentPositionSeconds() -> TimeInterval? {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.currentSession?.remoteMediaClient?
            .approximateStreamPosition()
        #else
        nil
        #endif
    }

    func endSession() {
        #if canImport(GoogleCast)
        GCKCastContext.sharedInstance().sessionManager.endSessionAndStopCasting(true)
        #endif
    }

    /// MIME type Chromecast's Default Media Receiver expects for this stream URL.
    static func contentType(for url: URL, container: String?) -> String {
        let path = url.path.lowercased()
        let query = url.query?.lowercased() ?? ""
        if path.contains(".m3u8") || query.contains("playlist") || (container ?? "").lowercased().contains("hls") {
            return "application/x-mpegURL"
        }
        let ext = (container ?? url.pathExtension).lowercased()
        switch ext {
        case "mp4", "m4v", "mov":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mkv", "matroska":
            return "video/x-matroska"
        default:
            return "video/mp4"
        }
    }

    static func isTransportStreamHLS(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8"
    }
}

#if canImport(GoogleCast)
extension CastManager: GCKSessionManagerListener {
    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, willStart session: GCKSession) {
        MainActor.assumeIsolated { isConnecting = true }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didStart session: GCKSession) {
        let name = session.device.friendlyName
        (session as? GCKCastSession)?.remoteMediaClient?.add(self)
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = name
            lastKnownPositionSeconds = nil
        }
    }

    public nonisolated func sessionManager(_ sessionManager: GCKSessionManager, didResumeSession session: GCKSession) {
        let name = session.device.friendlyName
        let client = (session as? GCKCastSession)?.remoteMediaClient
        client?.add(self)
        client?.requestStatus()
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = true
            deviceName = name
            lastKnownPositionSeconds = nil
        }
    }

    public nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didEnd session: GCKSession,
        withError error: Error?
    ) {
        (session as? GCKCastSession)?.remoteMediaClient?.remove(self)
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = false
            isPaused = false
            deviceName = nil
            nowPlayingTitle = nil
            nowPlayingItemID = nil
        }
    }

    public nonisolated func sessionManager(
        _ sessionManager: GCKSessionManager,
        didFailToStart session: GCKSession,
        withError error: Error
    ) {
        MainActor.assumeIsolated {
            isConnecting = false
            isConnected = false
        }
    }
}

extension CastManager: GCKRemoteMediaClientListener {
    public nonisolated func remoteMediaClient(_ client: GCKRemoteMediaClient, didUpdate mediaStatus: GCKMediaStatus?) {
        let paused = mediaStatus?.playerState == .paused
        let finished = mediaStatus?.playerState == .idle && mediaStatus?.idleReason == .finished
        let position = mediaStatus?.streamPosition
        let receiverVolume = mediaStatus?.volume
        let info = mediaStatus?.mediaInformation
        let title = info?.metadata?.string(forKey: kGCKMetadataKeyTitle)
        let itemID = (info?.customData as? [String: Any])?[Self.itemIDKey] as? String
        MainActor.assumeIsolated {
            if nowPlayingTitle == nil, let title { nowPlayingTitle = title }
            if nowPlayingItemID == nil, let itemID { nowPlayingItemID = itemID }
            if finished, !lastStatusWasFinished { playbackFinishedCount += 1 }
            lastStatusWasFinished = finished
            isPaused = paused
            if let receiverVolume { volume = receiverVolume }
            if let position { lastKnownPositionSeconds = position }
        }
    }
}
#endif
