import Foundation
import JellyfinAPI

extension Notification.Name {
    static let zelefinRemotePlayItem = Notification.Name("zelefin.remotePlayItem")
    static let zelefinRemoteStopPlayback = Notification.Name("zelefin.remoteStopPlayback")
    static let zelefinRemoteNextTrack = Notification.Name("zelefin.remoteNextTrack")
    static let zelefinSyncPlayJoined = Notification.Name("zelefin.syncPlayJoined")
    static let zelefinSyncPlayLeft = Notification.Name("zelefin.syncPlayLeft")
    static let zelefinSyncPlayQueueItem = Notification.Name("zelefin.syncPlayQueueItem")
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
            .displayMessage,
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
    private var socketKind: ServerKind = .jellyfin

    func connect(client: JellyfinClient, session: SavedSession) {
        disconnect()
        generation += 1
        socketKind = .jellyfin
        let token = generation
        connection = Task { [client, session] in
            await self.advertiseCapabilities(using: client)
            await self.runSocket(client: client, session: session, generation: token)
        }
    }

    /// Emby speaks the same message types over `/embywebsocket`, in its own JSON.
    func connect(emby api: EmbyAPI) {
        disconnect()
        generation += 1
        socketKind = .emby
        let token = generation
        connection = Task { [api] in
            _ = try? await api.data("POST", "/Sessions/Capabilities/Full", body: try api.json(EmbySocket.capabilities))
            guard let url = EmbySocket.url(base: api.serverURL, token: api.accessToken, deviceID: api.deviceID) else { return }
            await self.runSocket(generation: token) {
                var request = URLRequest(url: url)
                AccessGateway.apply(&request)
                request.setValue(api.accessToken, forHTTPHeaderField: "X-Emby-Token")
                request.setValue(EmbyAPI.authorization(deviceID: api.deviceID), forHTTPHeaderField: "X-Emby-Authorization")
                return URLSession.shared.webSocketTask(with: request)
            }
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
        await runSocket(generation: generation) { Self.socketTask(url: url, session: session) }
    }

    private func runSocket(generation: Int, makeTask: () -> URLSessionWebSocketTask) async {
        var backoff: TimeInterval = 1
        while !Task.isCancelled, generation == self.generation {
            let task = makeTask()
            socket = task
            task.resume()
            let dropped = await openAndListen(task, generation: generation)
            keepAlive?.cancel()
            socket = nil
            guard dropped, !Task.isCancelled, generation == self.generation else { return }
            try? await Task.sleep(for: .seconds(backoff))
            backoff = min(30, backoff * 2)
        }
    }

    /// This server rejects a socket that only carries `api_key`. The handshake
    /// has to include the same MediaBrowser authorization header as the API.
    private static func socketTask(url: URL, session: SavedSession) -> URLSessionWebSocketTask {
        var request = URLRequest(url: url)
        AccessGateway.apply(&request)
        request.setValue(
            "MediaBrowser Client=\"\(DeviceIdentity.clientName)\", Device=\"\(DeviceIdentity.deviceName)\", DeviceId=\"\(session.deviceID)\", Version=\"\(DeviceIdentity.version)\", Token=\"\(session.accessToken)\"",
            forHTTPHeaderField: "Authorization"
        )
        return URLSession.shared.webSocketTask(with: request)
    }

    private func openAndListen(_ task: URLSessionWebSocketTask, generation: Int) async -> Bool {
        if socketKind == .emby {
            await subscribeToSessions(task)
            startKeepAlive(every: 30, generation: generation)
            return await listen(task, generation: generation)
        }
        do {
            let first = try await task.receive()
            guard !Task.isCancelled, generation == self.generation else { return false }
            await subscribeToSessions(task)
            startKeepAlive(every: 30, generation: generation)
            handle(first)
        } catch {
            return true
        }
        return await listen(task, generation: generation)
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
        if socketKind == .emby {
            handleEmby(data)
            return
        }
        publishRawSyncPlayGroup(data)
        let shownDisplayMessage = SessionDisplayMessage.parse(json: data).map {
            SessionMessageCenter.present($0)
            return true
        } ?? false
        guard let payload = try? Self.decoder.decode(OutboundWebSocketMessage.self, from: data) else { return }
        switch payload {
        case let .forceKeepAliveMessage(keep):
            let interval = TimeInterval(max(5, (keep.data ?? 30) / 2))
            startKeepAlive(every: interval, generation: generation)
        case let .sessionsMessage(message):
            guard let dtos = message.data else { return }
            publishSessions(dtos)
        case .libraryChangedMessage:
            NotificationCenter.default.post(name: .zelefinLibraryChanged, object: nil)
        case let .playstateMessage(message):
            if let command = message.data?.command,
               let action = RemotePlaybackAction.playstate(command, seekTicks: message.data?.seekPositionTicks)
            {
                apply(action)
            }
        case let .generalCommandMessage(message):
            if message.data?.name == .displayMessage {
                if !shownDisplayMessage, let inbound = SessionDisplayMessage.parse(arguments: message.data?.arguments) {
                    SessionMessageCenter.present(inbound)
                }
            } else if let name = message.data?.name, let action = RemotePlaybackAction.general(name) {
                apply(action)
            }
        case let .playMessage(message):
            publishRemotePlay(itemIDs: message.data?.itemIDs ?? [], startIndex: message.data?.startIndex ?? 0)
        case let .syncPlayCommandMessage(message):
            applySyncPlay(message.data)
        case let .syncPlayGroupUpdateMessage(message):
            applySyncPlayGroup(message.data)
        default:
            break
        }
    }

    private func handleEmby(_ data: Data) {
        let shownDisplayMessage = SessionDisplayMessage.parse(json: data).map {
            SessionMessageCenter.present($0)
            return true
        } ?? false
        guard let event = EmbySocketEvent.parse(data) else { return }
        switch event {
        case let .forceKeepAlive(seconds):
            startKeepAlive(every: TimeInterval(max(5, seconds / 2)), generation: generation)
        case let .sessions(sessions):
            NotificationCenter.default.post(name: .zelefinPlaybackSessions, object: sessions)
        case .libraryChanged:
            NotificationCenter.default.post(name: .zelefinLibraryChanged, object: nil)
        case let .playstate(command, seekTicks):
            if let command = PlaystateCommand(rawValue: command),
               let action = RemotePlaybackAction.playstate(command, seekTicks: seekTicks.map(Int.init)) {
                apply(action)
            }
        case let .generalCommand(name, arguments):
            if name == GeneralCommandType.displayMessage.rawValue {
                if !shownDisplayMessage, let inbound = SessionDisplayMessage.parse(arguments: arguments) {
                    SessionMessageCenter.present(inbound)
                }
            } else if let command = GeneralCommandType(rawValue: name),
                      let action = RemotePlaybackAction.general(command) {
                apply(action)
            }
        case let .play(itemIDs, startIndex, _):
            publishRemotePlay(itemIDs: itemIDs, startIndex: startIndex)
        case .keepAlive, .userDataChanged, .other:
            break
        }
    }

    private func applySyncPlay(_ command: SendCommand?) {
        guard let command else { return }
        switch command.command {
        case .pause:
            apply(.pause)
        case .unpause:
            apply(.play)
        case .stop:
            apply(.stop)
        case .seek:
            if let ticks = command.positionTicks {
                apply(.seek(TickClock.seconds(from: ticks)))
            }
        default:
            break
        }
    }

    private func applySyncPlayGroup(_ update: GroupUpdate?) {
        guard let update else { return }
        switch update {
        case let .syncPlayGroupJoinedUpdate(joined):
            let id = joined.groupID ?? joined.data?.groupID
            NotificationCenter.default.post(
                name: .zelefinSyncPlayJoined,
                object: id,
                userInfo: ["name": joined.data?.groupName ?? ""]
            )
        case .syncPlayGroupLeftUpdate, .syncPlayGroupDoesNotExistUpdate, .syncPlayNotInGroupUpdate:
            NotificationCenter.default.post(name: .zelefinSyncPlayLeft, object: nil)
        case let .syncPlayPlayQueueUpdate(queue):
            let items = queue.data?.playlist ?? []
            let index = queue.data?.playingItemIndex ?? 0
            let current = items.indices.contains(index) ? items[index] : items.first
            publishSyncPlayQueue(
                itemID: current?.itemID,
                playlistItemID: current?.playlistItemID,
                startSeconds: queue.data?.startPositionTicks.map { TickClock.seconds(from: $0) }
            )
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

    /// Official `GroupUpdate` decoding can drop PlayQueue. Read the JSON Jellyfin actually sends.
    private func publishRawSyncPlayGroup(_ data: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let messageType = (root["MessageType"] as? String) ?? (root["messageType"] as? String)
        guard messageType == "SyncPlayGroupUpdate" else { return }
        let update = (root["Data"] as? [String: Any]) ?? [:]
        let type = (update["Type"] as? String) ?? (update["type"] as? String)
        switch type {
        case "GroupJoined":
            let info = update["Data"] as? [String: Any]
            let id = stringID(update["GroupId"]) ?? stringID(info?["GroupId"])
            NotificationCenter.default.post(
                name: .zelefinSyncPlayJoined,
                object: id,
                userInfo: ["name": stringID(info?["GroupName"]) ?? ""]
            )
        case "GroupLeft", "GroupDoesNotExist", "NotInGroup":
            NotificationCenter.default.post(name: .zelefinSyncPlayLeft, object: nil)
        case "PlayQueue":
            let queue = update["Data"] as? [String: Any] ?? [:]
            let playlist = queue["Playlist"] as? [[String: Any]] ?? []
            let index = queue["PlayingItemIndex"] as? Int ?? 0
            let current = playlist.indices.contains(index) ? playlist[index] : playlist.first
            publishSyncPlayQueue(
                itemID: stringID(current?["ItemId"]),
                playlistItemID: stringID(current?["PlaylistItemId"]),
                startSeconds: secondsFromTicks(queue["StartPositionTicks"])
            )
        default:
            break
        }
    }

    private func publishSyncPlayQueue(itemID: String?, playlistItemID: String?, startSeconds: TimeInterval?) {
        if let playlistItemID, !playlistItemID.isEmpty {
            NotificationCenter.default.post(name: .zelefinSyncPlayQueueItem, object: playlistItemID)
        }
        if let itemID, !itemID.isEmpty {
            var info: [AnyHashable: Any] = [:]
            if let startSeconds {
                info["startSeconds"] = startSeconds
            }
            NotificationCenter.default.post(
                name: .zelefinRemotePlayItem,
                object: itemID,
                userInfo: info.isEmpty ? nil : info
            )
        }
    }

    private func secondsFromTicks(_ value: Any?) -> TimeInterval? {
        switch value {
        case let ticks as Int:
            return TickClock.seconds(from: ticks)
        case let ticks as Int64:
            return TickClock.seconds(from: ticks)
        case let number as NSNumber:
            return TickClock.seconds(from: number.int64Value)
        default:
            return nil
        }
    }

    private func stringID(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let uuid as UUID:
            return uuid.uuidString
        default:
            return nil
        }
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

    private static let decoder = JellyfinJSONDate.decoder
}

enum JellyfinJSONDate {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom(parse)
        return decoder
    }()

    static func parse(_ decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let date = date(from: raw) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Invalid Jellyfin date \(raw)"
        )
    }

    static func date(from raw: String) -> Date? {
        if let date = fractionalInternet.date(from: raw) {
            return date
        }
        if let date = internet.date(from: raw) {
            return date
        }
        if let date = fractionalOffset.date(from: raw) {
            return date
        }
        if let date = offset.date(from: raw) {
            return date
        }
        return dateByTruncatingFraction(raw)
    }

    /// Jellyfin often sends 7 fractional digits (`...1234567Z`). ISO8601DateFormatter
    /// only accepts milliseconds, so keep the first three and try again.
    private static func dateByTruncatingFraction(_ raw: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(\.\d{3})\d+"#) else { return nil }
        let trimmed = regex.stringByReplacingMatches(
            in: raw,
            range: NSRange(raw.startIndex..., in: raw),
            withTemplate: "$1"
        )
        guard trimmed != raw else { return nil }
        return fractionalInternet.date(from: trimmed)
            ?? fractionalOffset.date(from: trimmed)
            ?? internet.date(from: trimmed)
            ?? offset.date(from: trimmed)
    }

    private nonisolated(unsafe) static let fractionalInternet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private nonisolated(unsafe) static let internet: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalOffset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSSXXXXX"
        return formatter
    }()

    private static let offset: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()
}
