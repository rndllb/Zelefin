import Foundation
import JellyfinAPI

/// A Jellyfin client session, including whoever is playing and how the stream is served.
struct PlaybackSession: Identifiable, Equatable, Sendable {
    let id: String
    var userID: String?
    var userName: String
    var userImageTag: String?
    var client: String
    var deviceName: String
    var deviceType: String?
    var deviceID: String?
    var applicationVersion: String?
    var remoteEndPoint: String?
    var isActive: Bool
    var supportsRemoteControl: Bool
    var supportsMediaControl: Bool
    var nowPlaying: MediaItem?
    var nowPlayingName: String?
    var nowViewingName: String?
    var position: TimeInterval
    var runtime: TimeInterval?
    var isPaused: Bool
    var isMuted: Bool
    var canSeek: Bool
    var volumeLevel: Int?
    var playMethod: PlayMethodKind
    var transcoding: TranscodingSummary?
    var lastActivity: Date?
    var lastPlaybackCheckIn: Date?
    var supportedCommands: Set<String>

    var isPlaying: Bool { nowPlaying != nil || nowPlayingName != nil }

    var canControl: Bool { supportsRemoteControl || supportsMediaControl }

    var title: String {
        if let nowPlaying {
            return Self.title(for: nowPlaying)
        }
        return nowPlayingName ?? nowViewingName ?? "Idle"
    }

    var userLabel: String {
        userName.isEmpty ? "Unknown user" : userName
    }

    var deviceLabel: String {
        [client, deviceName].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var methodLabel: String { playMethod.label }

    var progressFraction: Double {
        guard let runtime, runtime > 0 else { return 0 }
        return min(1, max(0, position / runtime))
    }

    var positionLabel: String {
        let elapsed = PlaybackTimeFormatting.elapsed(position)
        guard let runtime, runtime > 0 else { return elapsed }
        return "\(elapsed) / \(PlaybackTimeFormatting.clock(runtime))"
    }

    func isThisDevice(_ localDeviceID: String?) -> Bool {
        guard let deviceID, let localDeviceID else { return false }
        return deviceID == localDeviceID
    }

    static func title(for item: MediaItem) -> String {
        if item.kind == .episode {
            var parts: [String] = []
            if let series = item.seriesName, !series.isEmpty {
                parts.append(series)
            }
            if let season = item.seasonIndex, let episode = item.episodeIndex {
                parts.append("S\(season):E\(episode)")
            }
            if parts.isEmpty || parts.first != item.name {
                parts.append(item.name)
            }
            return parts.joined(separator: " · ")
        }
        if let year = item.year {
            return "\(item.name) (\(year))"
        }
        return item.name
    }

    static func sorted(_ sessions: [PlaybackSession]) -> [PlaybackSession] {
        sessions.sorted { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return lhs.isPlaying && !rhs.isPlaying }
            if lhs.isPlaying {
                return (lhs.lastPlaybackCheckIn ?? lhs.lastActivity ?? .distantPast)
                    > (rhs.lastPlaybackCheckIn ?? rhs.lastActivity ?? .distantPast)
            }
            return (lhs.lastActivity ?? .distantPast) > (rhs.lastActivity ?? .distantPast)
        }
    }
}

enum PlayMethodKind: String, Equatable, Sendable {
    case directPlay
    case directStream
    case transcode
    case unknown

    var label: String {
        switch self {
        case .directPlay: "Direct Play"
        case .directStream: "Direct Stream"
        case .transcode: "Transcode"
        case .unknown: "Unknown"
        }
    }

    init(_ method: PlayMethod?) {
        guard let method else {
            self = .unknown
            return
        }
        switch method {
        case .directPlay: self = .directPlay
        case .directStream: self = .directStream
        case .transcode: self = .transcode
        @unknown default: self = .unknown
        }
    }
}

struct TranscodingSummary: Equatable, Sendable {
    var videoCodec: String?
    var audioCodec: String?
    var container: String?
    var width: Int?
    var height: Int?
    var bitrate: Int?
    var audioChannels: Int?
    var isVideoDirect: Bool
    var isAudioDirect: Bool
    var hardwareAcceleration: String?
    var completionPercentage: Double?
    var reasons: [String]

    var resolutionLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }

    var bitrateLabel: String? {
        guard let bitrate, bitrate > 0 else { return nil }
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        }
        if bitrate >= 1_000 {
            return "\(bitrate / 1_000) kbps"
        }
        return "\(bitrate) bps"
    }

    var codecLine: String? {
        var parts: [String] = []
        if let container, !container.isEmpty { parts.append(container.uppercased()) }
        if let videoCodec, !videoCodec.isEmpty {
            parts.append(isVideoDirect ? "\(videoCodec.uppercased()) direct" : videoCodec.uppercased())
        }
        if let audioCodec, !audioCodec.isEmpty {
            var audio = audioCodec.uppercased()
            if let audioChannels { audio += " \(audioChannels)ch" }
            if isAudioDirect { audio += " direct" }
            parts.append(audio)
        }
        if let hardwareAcceleration, !hardwareAcceleration.isEmpty, hardwareAcceleration != "none" {
            parts.append(hardwareAcceleration)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var reasonsLabel: String? {
        guard !reasons.isEmpty else { return nil }
        return reasons.joined(separator: ", ")
    }
}

extension PlaybackSession {
    init?(dto: SessionInfoDto) {
        guard let id = dto.id, !id.isEmpty else { return nil }
        let item = dto.nowPlayingItem.flatMap { ItemMapper.mediaItem(from: $0, queueKind: .resume) }
        let runtime = item?.runtime ?? dto.nowPlayingItem?.runTimeTicks.map(TickClock.seconds(from:))
        var method = PlayMethodKind(dto.playState?.playMethod)
        if dto.transcodingInfo != nil, method == .unknown {
            method = .transcode
        }
        let unresolvedPlayingName: String?
        if item == nil, let playing = dto.nowPlayingItem {
            unresolvedPlayingName = playing.name ?? "Playing"
        } else {
            unresolvedPlayingName = nil
        }
        self.init(
            id: id,
            userID: dto.userID,
            userName: dto.userName ?? "",
            userImageTag: dto.userPrimaryImageTag,
            client: dto.client ?? "",
            deviceName: dto.deviceName ?? "",
            deviceType: dto.deviceType,
            deviceID: dto.deviceID,
            applicationVersion: dto.applicationVersion,
            remoteEndPoint: dto.remoteEndPoint,
            isActive: dto.isActive ?? true,
            supportsRemoteControl: dto.isSupportsRemoteControl ?? false,
            supportsMediaControl: dto.isSupportsMediaControl ?? false,
            nowPlaying: item,
            nowPlayingName: unresolvedPlayingName,
            nowViewingName: dto.nowViewingItem?.name,
            position: TickClock.seconds(from: dto.playState?.positionTicks ?? 0),
            runtime: runtime,
            isPaused: dto.playState?.isPaused ?? false,
            isMuted: dto.playState?.isMuted ?? false,
            canSeek: dto.playState?.canSeek ?? false,
            volumeLevel: dto.playState?.volumeLevel,
            playMethod: method,
            transcoding: dto.transcodingInfo.map(TranscodingSummary.init(info:)),
            lastActivity: dto.lastActivityDate,
            lastPlaybackCheckIn: dto.lastPlaybackCheckIn,
            supportedCommands: Set((dto.supportedCommands ?? []).map(\.rawValue))
        )
    }
}

extension TranscodingSummary {
    init(info: TranscodingInfo) {
        self.init(
            videoCodec: info.videoCodec,
            audioCodec: info.audioCodec,
            container: info.container,
            width: info.width,
            height: info.height,
            bitrate: info.bitrate,
            audioChannels: info.audioChannels,
            isVideoDirect: info.isVideoDirect ?? false,
            isAudioDirect: info.isAudioDirect ?? false,
            hardwareAcceleration: info.hardwareAccelerationType.map(Self.hardwareLabel),
            completionPercentage: info.completionPercentage,
            reasons: (info.transcodeReasons ?? []).map(Self.reasonLabel)
        )
    }

    static func hardwareLabel(_ type: HardwareAccelerationType) -> String {
        switch type {
        case .none: "none"
        case .amf: "AMF"
        case .qsv: "Quick Sync"
        case .nvenc: "NVENC"
        case .v4l2m2m: "V4L2"
        case .vaapi: "VAAPI"
        case .videotoolbox: "VideoToolbox"
        case .rkmpp: "RKMPP"
        @unknown default: type.rawValue
        }
    }

    static func reasonLabel(_ reason: TranscodeReason) -> String {
        let raw = reason.rawValue
        var spaced = ""
        for character in raw {
            if character.isUppercase, !spaced.isEmpty {
                spaced.append(" ")
            }
            spaced.append(character)
        }
        return spaced.lowercased()
    }
}
