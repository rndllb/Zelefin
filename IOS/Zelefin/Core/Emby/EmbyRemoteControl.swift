import Foundation
import JellyfinAPI

/// Emby's session socket (`/embywebsocket`) and the capabilities Zelefin reports to it.
enum EmbySocket {
    static func url(base: URL, token: String, deviceID: String) -> URL? {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        switch components.scheme?.lowercased() {
        case "https": components.scheme = "wss"
        case "http": components.scheme = "ws"
        default: return nil
        }
        var path = components.path
        while path.hasSuffix("/") {
            path.removeLast()
        }
        components.path = path + "/embywebsocket"
        components.queryItems = [
            URLQueryItem(name: "api_key", value: token),
            URLQueryItem(name: "deviceId", value: deviceID)
        ]
        return components.url
    }

    static var capabilities: [String: Any] {
        [
            "PlayableMediaTypes": ["Video"],
            "SupportedCommands": (RemoteControlProfile.capabilities.supportedCommands ?? []).map(\.rawValue),
            "SupportsMediaControl": true,
            "SupportsSync": false
        ]
    }
}

/// One message from Emby's session socket.
enum EmbySocketEvent: Equatable, Sendable {
    case forceKeepAlive(seconds: Int)
    case keepAlive
    case play(itemIDs: [String], startIndex: Int, startPositionTicks: Int64?)
    case playstate(command: String, seekPositionTicks: Int64?)
    case generalCommand(name: String, arguments: [String: String])
    case sessions([PlaybackSession])
    case libraryChanged
    case userDataChanged
    case other(String)

    static func parse(_ data: Data) -> EmbySocketEvent? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = root["MessageType"] as? String
        else { return nil }
        let payload = root["Data"]
        let object = payload as? [String: Any] ?? [:]
        switch type {
        case "ForceKeepAlive":
            return .forceKeepAlive(seconds: int(payload).map(Int.init) ?? 60)
        case "KeepAlive":
            return .keepAlive
        case "Play":
            return .play(
                itemIDs: (object["ItemIds"] as? [Any] ?? []).compactMap(string),
                startIndex: int(object["StartIndex"]).map(Int.init) ?? 0,
                startPositionTicks: int(object["StartPositionTicks"])
            )
        case "Playstate":
            guard let command = string(object["Command"]) else { return nil }
            return .playstate(command: command, seekPositionTicks: int(object["SeekPositionTicks"]))
        case "GeneralCommand":
            guard let name = string(object["Name"]) else { return nil }
            let arguments = (object["Arguments"] as? [String: Any] ?? [:]).compactMapValues(string)
            return .generalCommand(name: name, arguments: arguments)
        case "Sessions":
            guard let array = payload as? [Any],
                  let raw = try? JSONSerialization.data(withJSONObject: array),
                  let dtos = try? EmbyJSON.decode([SessionInfoDto].self, from: raw)
            else { return .sessions([]) }
            return .sessions(PlaybackSession.sorted(dtos.compactMap(PlaybackSession.init(dto:))))
        case "LibraryChanged":
            return .libraryChanged
        case "UserDataChanged":
            return .userDataChanged
        default:
            return .other(type)
        }
    }

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let text as String: text.isEmpty ? nil : text
        case let number as NSNumber: number.stringValue
        default: nil
        }
    }

    private static func int(_ value: Any?) -> Int64? {
        switch value {
        case let number as NSNumber: number.int64Value
        case let text as String: Int64(text)
        default: nil
        }
    }
}
