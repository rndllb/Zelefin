import Foundation
import JellyfinAPI

extension Notification.Name {
    static let zelefinRemotePlayItem = Notification.Name("zelefin.remotePlayItem")
    static let zelefinRemoteStopPlayback = Notification.Name("zelefin.remoteStopPlayback")
    static let zelefinRemoteNextTrack = Notification.Name("zelefin.remoteNextTrack")
}

enum RemotePlaybackAction: Equatable, Sendable {
    case playPause
    case pause
    case play
    case stop
    case seek(TimeInterval)
    case skip(TimeInterval)
    case next
    case previous
    case mute
    case unmute
    case volumeUp
    case volumeDown

    static func playstate(_ command: PlaystateCommand, seekTicks: Int?) -> RemotePlaybackAction? {
        switch command {
        case .playPause: .playPause
        case .pause: .pause
        case .unpause: .play
        case .stop: .stop
        case .seek:
            seekTicks.map { .seek(TickClock.seconds(from: $0)) }
        case .rewind: .skip(-10)
        case .fastForward: .skip(10)
        case .nextTrack: .next
        case .previousTrack: .previous
        @unknown default: nil
        }
    }

    static func general(_ command: GeneralCommandType) -> RemotePlaybackAction? {
        switch command {
        case .mute, .toggleMute: .mute
        case .unmute: .unmute
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .playState: .playPause
        default: nil
        }
    }
}

enum RemoteControlProfile {
    static let capabilities = ClientCapabilitiesDto(
        isSupportsMediaControl: true,
        isSupportsPersistentIdentifier: true,
        playableMediaTypes: [.video],
        supportedCommands: [
            .play,
            .playState,
            .playNext,
            .mute,
            .unmute,
            .toggleMute,
            .volumeUp,
            .volumeDown
        ]
    )
}

/// Advertises media control to Jellyfin and applies session commands that arrive over the socket.
@MainActor
final class RemoteControlHub {
    static let shared = RemoteControlHub()

    private weak var player: PlayerModel?
    private var connection: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private var keepAlive: Task<Void, Never>?
    private var generation = 0

    func connect(client: JellyfinClient, session: SavedSession) {
        disconnect()
        generation += 1
        let token = generation
        connection = Task { [client, session] in
            await self.advertiseCapabilities(using: client)
            await self.runSocket(client: client, session: session, generation: token)
        }
    }

    func disconnect() {
        generation += 1
        keepAlive?.cancel()
        keepAlive = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connection?.cancel()
        connection = nil
        player = nil
    }

    func attach(_ player: PlayerModel) {
        self.player = player
    }

    func detach(_ player: PlayerModel) {
        if self.player === player {
            self.player = nil
        }
    }

    private func advertiseCapabilities(using client: JellyfinClient) async {
        _ = try? await client.send(Paths.postFullCapabilities(RemoteControlProfile.capabilities))
    }

    private func runSocket(client: JellyfinClient, session: SavedSession, generation: Int) async {
        guard let url = ServerURL.sessionSocket(
            base: client.configuration.url,
            token: session.accessToken,
            deviceID: session.deviceID
        ) else { return }

        var backoff: TimeInterval = 1
        while !Task.isCancelled, generation == self.generation {
            var request = URLRequest(url: url)
            AccessGateway.apply(&request)
            request.setValue(session.accessToken, forHTTPHeaderField: "X-Emby-Token")
            let task = URLSession.shared.webSocketTask(with: request)
            socket = task
            task.resume()
            await subscribeToSessions(task)
            startKeepAlive(every: 30, generation: generation)
            let dropped = await listen(task, generation: generation)
            keepAlive?.cancel()
            socket = nil
            guard dropped, !Task.isCancelled, generation == self.generation else { return }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(30, backoff * 2)
        }
    }

    private func startKeepAlive(every seconds: TimeInterval, generation: Int) {
        keepAlive?.cancel()
        keepAlive = Task { [weak self] in
            while !Task.isCancelled, generation == self?.generation {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled, generation == self?.generation else { return }
                try? await self?.socket?.send(.string(#"{"MessageType":"KeepAlive"}"#))
            }
        }
    }

    private func listen(_ task: URLSessionWebSocketTask, generation: Int) async -> Bool {
        while !Task.isCancelled, generation == self.generation {
            do {
                let message = try await task.receive()
                handle(message)
            } catch {
                return true
            }
        }
        return false
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case let .data(value): data = value
        case let .string(value): data = Data(value.utf8)
        @unknown default: return
        }
        guard let payload = try? Self.decoder.decode(OutboundWebSocketMessage.self, from: data) else { return }
        switch payload {
        case let .forceKeepAliveMessage(keep):
            let interval = TimeInterval(max(5, (keep.data ?? 30) / 2))
            startKeepAlive(every: interval, generation: generation)
        case let .sessionsMessage(message):
            publishSessions(message.data)
        case let .playstateMessage(message):
            if let command = message.data?.command,
               let action = RemotePlaybackAction.playstate(command, seekTicks: message.data?.seekPositionTicks)
            {
                apply(action)
            }
        case let .generalCommandMessage(message):
            if let name = message.data?.name, let action = RemotePlaybackAction.general(name) {
                apply(action)
            }
        case let .playMessage(message):
            publishRemotePlay(itemIDs: message.data?.itemIDs ?? [], startIndex: message.data?.startIndex ?? 0)
        default:
            break
        }
    }

    private func publishSessions(_ dtos: [SessionInfoDto]?) {
        let sessions = PlaybackSession.sorted((dtos ?? []).compactMap(PlaybackSession.init(dto:)))
        NotificationCenter.default.post(name: .zelefinPlaybackSessions, object: sessions)
    }

    private func publishRemotePlay(itemIDs: [String], startIndex: Int) {
        let itemID: String?
        if itemIDs.indices.contains(startIndex) {
            itemID = itemIDs[startIndex]
        } else {
            itemID = itemIDs.first
        }
        guard let itemID else { return }
        NotificationCenter.default.post(name: .zelefinRemotePlayItem, object: itemID)
    }

    private func apply(_ action: RemotePlaybackAction) {
        switch action {
        case .stop:
            Task { await player?.stop() }
            NotificationCenter.default.post(name: .zelefinRemoteStopPlayback, object: nil)
        case .next:
            NotificationCenter.default.post(name: .zelefinRemoteNextTrack, object: nil)
        default:
            player?.applyRemote(action)
        }
    }

    private func subscribeToSessions(_ task: URLSessionWebSocketTask) async {
        let payload = SessionsStartMessage(data: "0,1500", messageType: .sessionsStart)
        guard let data = try? JSONEncoder().encode(payload),
              let text = String(data: data, encoding: .utf8)
        else { return }
        try? await task.send(.string(text))
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(JellyfinISO8601DateFormatter())
        return decoder
    }()
}

/// Matches Jellyfin’s ISO-8601 timestamps, including values without fractional seconds.
private final class JellyfinISO8601DateFormatter: DateFormatter, @unchecked Sendable {
    private static let withoutSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter
    }()

    override init() {
        super.init()
        applyFractionalSecondsFormat()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        applyFractionalSecondsFormat()
    }

    override func date(from string: String) -> Date? {
        super.date(from: string) ?? Self.withoutSeconds.date(from: string)
    }

    private func applyFractionalSecondsFormat() {
        calendar = Calendar(identifier: .iso8601)
        locale = Locale(identifier: "en_US_POSIX")
        timeZone = TimeZone(secondsFromGMT: 0)
        dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
    }
}
