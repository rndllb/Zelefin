#if targetEnvironment(macCatalyst)
import AVFoundation
import Combine
import UIKit

// Mac Catalyst builds without AetherEngine: its FFmpeg and LibDovi ship no Catalyst slices
// (AetherEngine#253). These stand-ins carry the shapes the shared player code compiles against.
// `DirectPlayEngine()` always throws, so the Mac never runs one; its players are MPV and AVPlayer.

protocol DirectPlayByteSource: AnyObject, Sendable {
    func read(_ buffer: UnsafeMutablePointer<UInt8>?, size: Int32) -> Int32
    func seek(offset: Int64, whence: Int32) -> Int64
    func close()
    func cancel()
    func makeIndependentReader() -> DirectPlayByteSource?
    var discImageProbeEnabled: Bool { get }
}

extension DirectPlayByteSource {
    func cancel() {}
}

struct DirectPlayTrack: Identifiable, Sendable, Equatable {
    let id: Int
    let name: String
    let codec: String
    let language: String?
    var channels = 0
    var bitrate: Int64 = 0
    var isDefault = false
    var isForced = false
    var isHearingImpaired = false
    var isAtmos = false
    var isExternal = false
}

struct DirectPlaySubtitlePlacement: Sendable, Equatable {
    let alignment: Int?
    let position: CGPoint?
}

struct DirectPlaySubtitleImage: @unchecked Sendable {
    let cgImage: CGImage
    let position: CGRect
    let canvasSize: CGSize
    let isForced: Bool
}

struct DirectPlaySubtitleTextRun: Sendable {
    let text: String
}

struct DirectPlaySubtitleCue: Identifiable, Sendable, Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.startTime == rhs.startTime && lhs.endTime == rhs.endTime
    }

    enum Body: Sendable {
        case text(String)
        case image(DirectPlaySubtitleImage)
        case richText([DirectPlaySubtitleTextRun])
    }

    let id: Int
    let startTime: Double
    let endTime: Double
    let body: Body
    let placement: DirectPlaySubtitlePlacement?
}

struct DirectPlaySeekEvent: Sendable, Equatable {
    enum Outcome: Sendable, Equatable {
        case began
        case landed(renderedTime: Double)
        case stalled
        case superseded
        case rejected
    }

    let outcome: Outcome
}

enum DirectPlayVideoFormat: Sendable, Equatable {
    case sdr, hdr10, hdr10Plus, dolbyVision, hlg
}

enum DirectPlayVideoRoute: Sendable, Equatable {
    case none, remoteBypass, loopback, software, audio
}

enum DirectPlayAudioDelivery: Sendable, Equatable {
    case none, noAudioInSource, streamCopy, bridged, decoded, droppedNoPipeline, playerManaged
}

enum DirectPlayPlaybackPhase: Sendable, Equatable {
    case idle, loading, playing, paused, seeking, rebuffering
    case stalled(reconnecting: Bool)
    case ended
    case error(String)
}

enum DirectPlayPlaybackState: Sendable, Equatable {
    case idle, loading, playing, paused, seeking, ended
    case error(String)
}

enum DirectPlayBackend: Sendable, Equatable {
    case none, audio, video
}

enum DirectPlaySource {
    case url(URL)
    case custom(DirectPlayByteSource, formatHint: String?)
}

struct DirectPlayLoadSettings {
    var httpHeaders: [String: String] = [:]
}

struct DirectPlayLiveTelemetry: Sendable, Equatable {
    var instantBitrateMbps: Double?
}

final class DirectPlayPlayerView: UIView {}

@MainActor
final class DirectPlayPiPSource {
    let layer = AVSampleBufferDisplayLayer()
    let isPaused = true

    func setPlaying(_ playing: Bool) {}
    func skip(by seconds: Double) {}
    func timeRange() -> CMTimeRange { CMTimeRange(start: .zero, duration: .zero) }
}

final class DirectPlayClock: ObservableObject {
    @Published var currentTime: Double = 0
}

@MainActor
final class DirectPlayEngine: ObservableObject {
    @Published private(set) var hasFirstFrameReadyForDisplay = false
    @Published private(set) var isBuffering = false
    @Published private(set) var isSeeking = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var audioTracks: [DirectPlayTrack] = []
    @Published private(set) var subtitleTracks: [DirectPlayTrack] = []
    @Published private(set) var activeAudioTrackIndex: Int?
    @Published private(set) var activeSubtitleTrackIndex: Int?
    @Published private(set) var subtitleCues: [DirectPlaySubtitleCue] = []
    @Published private(set) var softwareDisplaySize: CGSize?
    @Published private(set) var softwarePiPSource: DirectPlayPiPSource?
    @Published private(set) var state: DirectPlayPlaybackState = .idle
    let clock = DirectPlayClock()
    let seekEvents: AnyPublisher<DirectPlaySeekEvent, Never> = Empty().eraseToAnyPublisher()

    var ownsVideoNowPlayingSession = false
    var deactivatesAudioSessionOnStop = false
    var pictureInPictureActive = false
    var videoGravity: AVLayerVideoGravity = .resizeAspect
    private(set) var playbackBackend: DirectPlayBackend = .none
    private(set) var isLive = false
    private(set) var residentRanges: [ClosedRange<Double>] = []
    private(set) var liveTelemetry: DirectPlayLiveTelemetry?
    private(set) var sourceVideoWidth: Int32 = 0
    private(set) var sourceVideoHeight: Int32 = 0
    private(set) var sourceVideoFrameRate: Double?
    private(set) var sourceVideoBitrate: Int64 = 0
    private(set) var sourceVideoCodecName: String?
    private(set) var sourceContainerFormat: String?
    private(set) var sourceDVProfile: Int?
    private(set) var activeVideoDecoder: String?
    private(set) var activeAudioDecoder: String?
    private(set) var videoFormat: DirectPlayVideoFormat = .sdr
    private(set) var sourceVideoFormat: DirectPlayVideoFormat = .sdr
    private(set) var audioDelivery: DirectPlayAudioDelivery = .none
    private(set) var videoRoute: DirectPlayVideoRoute = .none
    private(set) var playbackPhase: DirectPlayPlaybackPhase = .idle

    init() throws {
        throw ZelefinError.playbackEngineUnavailable
    }

    func load(source: DirectPlaySource, startPosition: Double?, options: DirectPlayLoadSettings) async throws {
        throw ZelefinError.playbackEngineUnavailable
    }

    func reloadAtCurrentPosition() async throws {
        throw ZelefinError.playbackEngineUnavailable
    }

    func setExternalMetadata(_ items: [AVMetadataItem]) {}
    func play() {}
    func togglePlayPause() {}
    func stop() {}
    func seek(to seconds: Double) async {}
    func setRate(_ rate: Float) {}
    func selectAudioTrack(index: Int) {}
    func selectSubtitleTrack(index: Int) {}
    func clearSubtitle() {}
    func bind(view: DirectPlayPlayerView) {}
    func unbind(view: DirectPlayPlayerView) {}
}

extension DirectPlayLoadOptions {
    @MainActor
    static func make(for plan: PlaybackPlan) -> DirectPlayLoadSettings {
        DirectPlayLoadSettings()
    }
}
#endif
