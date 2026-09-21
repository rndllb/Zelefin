import Foundation

struct LibraryAlert: Equatable, Sendable, Identifiable {
    enum Kind: String, Equatable, Sendable {
        case newTitle
        case streamStarted
        case userOnline
        case seerrRequest
        case scheduledTask
    }

    var kind: Kind
    var title: String
    var body: String
    var itemID: String?
    var id: String

    var opensScheduledTasks: Bool { kind == .scheduledTask }
}

extension LibraryAlert {
    static func addedToLibrary(body: String, itemID: String?, id: String) -> LibraryAlert {
        LibraryAlert(kind: .newTitle, title: "Added to library", body: body, itemID: itemID, id: id)
    }

    static func streamStarted(user: String, title: String, itemID: String?, key: String) -> LibraryAlert {
        LibraryAlert(
            kind: .streamStarted,
            title: "Now playing",
            body: "\(user) started \(title).",
            itemID: itemID,
            id: "stream-\(key)"
        )
    }

    static func userOnline(user: String, device: String, sessionID: String) -> LibraryAlert {
        LibraryAlert(
            kind: .userOnline,
            title: "User online",
            body: "\(user) is on \(device).",
            itemID: nil,
            id: "online-\(sessionID)"
        )
    }

    static func seerrRequest(requester: String, title: String, id: String) -> LibraryAlert {
        LibraryAlert(
            kind: .seerrRequest,
            title: "New request",
            body: "\(requester) requested \(title).",
            itemID: nil,
            id: "request-\(id)"
        )
    }

    static func scheduledTaskStarted(name: String, id: String) -> LibraryAlert {
        LibraryAlert(
            kind: .scheduledTask,
            title: "Scheduled task started",
            body: "\(name) is running.",
            itemID: nil,
            id: "task-\(id)"
        )
    }
}
