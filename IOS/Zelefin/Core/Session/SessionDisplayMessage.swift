import Foundation

extension Notification.Name {
    static let zelefinSessionMessage = Notification.Name("zelefin.sessionMessage")
}

/// A Jellyfin `DisplayMessage` from the dashboard or another client.
struct SessionDisplayMessage: Equatable, Sendable, Identifiable {
    var id: String
    var header: String
    var text: String
    var timeoutMs: Int?

    var alertTitle: String { header }
    var alertBody: String? {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty || body.caseInsensitiveCompare(header) == .orderedSame {
            return nil
        }
        return body
    }

    static func parse(arguments: [String: String]?) -> SessionDisplayMessage? {
        parse(values: arguments ?? [:])
    }

    static func isPush(_ userInfo: [AnyHashable: Any]) -> Bool {
        let kind = string(in: userInfo, keys: "kind", "type", "Name", "name")
        return kind?.caseInsensitiveCompare("sessionMessage") == .orderedSame
            || kind?.caseInsensitiveCompare("DisplayMessage") == .orderedSame
    }

    static func fromPush(
        _ userInfo: [AnyHashable: Any],
        fallbackTitle: String? = nil,
        fallbackBody: String? = nil
    ) -> SessionDisplayMessage? {
        guard isPush(userInfo) else { return nil }
        let alert = ((userInfo["aps"] as? [String: Any])?["alert"] as? [String: Any]) ?? [:]
        let header = string(in: userInfo, keys: "Header", "header", "title")
            ?? string(in: alert, keys: "title")
            ?? fallbackTitle
        let text = string(in: userInfo, keys: "Text", "text", "body", "message")
            ?? string(in: alert, keys: "body")
            ?? fallbackBody
        guard !(header?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            || !(text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        else { return nil }
        let title = header?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionDisplayMessage(
            id: UUID().uuidString,
            header: (title?.isEmpty == false ? title : nil) ?? "Message",
            text: (body?.isEmpty == false ? body : nil) ?? title ?? "",
            timeoutMs: string(in: userInfo, keys: "TimeoutMs", "timeoutMs", "timeout")
                .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        )
    }

    static func parse(json data: Data) -> SessionDisplayMessage? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let type = string(in: root, keys: "MessageType", "messageType")
        let payload = root["Data"] as? [String: Any] ?? root["data"] as? [String: Any]
        let name = string(in: payload ?? [:], keys: "Name", "name")
        let isDisplay = type?.caseInsensitiveCompare("DisplayMessage") == .orderedSame
            || type?.caseInsensitiveCompare("GeneralCommand") == .orderedSame
            && name?.caseInsensitiveCompare("DisplayMessage") == .orderedSame
        guard isDisplay else { return nil }
        let arguments = payload?["Arguments"] as? [String: Any]
            ?? payload?["arguments"] as? [String: Any]
            ?? payload
            ?? [:]
        var values: [String: String] = [:]
        for (key, value) in arguments {
            values[key] = stringValue(value)
        }
        return parse(values: values)
    }

    private static func parse(values: [String: String]) -> SessionDisplayMessage? {
        let text = first(in: values, keys: "Text", "text", "Message", "message")
        let header = first(in: values, keys: "Header", "header", "Title", "title")
        let body = text ?? ""
        let title = header ?? "Message"
        guard !body.isEmpty || header != nil else { return nil }
        let timeout = first(in: values, keys: "TimeoutMs", "timeoutMs", "Timeout", "timeout")
            .flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return SessionDisplayMessage(
            id: UUID().uuidString,
            header: title.isEmpty ? "Message" : title,
            text: body.isEmpty ? title : body,
            timeoutMs: timeout
        )
    }

    private static func first(in values: [String: String], keys: String...) -> String? {
        for key in keys {
            if let match = values.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value {
                let trimmed = match.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private static func string(in object: [String: Any], keys: String...) -> String? {
        string(in: object as [AnyHashable: Any], keys: keys)
    }

    private static func string(in object: [AnyHashable: Any], keys: String...) -> String? {
        string(in: object, keys: keys)
    }

    private static func string(in object: [AnyHashable: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] {
                let text = stringValue(value)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let text, !text.isEmpty { return text }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any) -> String? {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}
