import Foundation

/// Maps Seerr/Ombi request status onto the request Live Activity.
@MainActor
enum RequestLiveActivityBridge {
    static func noteSubmitted(_ title: SeerrTitle) {
        RequestActivityPresenter.start(
            id: activityID(for: title),
            title: title.name,
            subtitle: subtitle(for: title),
            statusLine: "Pending",
            badgeLabel: "PENDING"
        )
    }

    static func sync(_ title: SeerrTitle) {
        let id = activityID(for: title)
        switch title.availability {
        case .pending:
            RequestActivityPresenter.update(id: id, statusLine: "Pending", badgeLabel: "PENDING")
        case .processing, .partial:
            RequestActivityPresenter.update(id: id, statusLine: "Processing", badgeLabel: "PROCESSING")
        case .available:
            RequestActivityPresenter.finish(id: id, available: true, statusLine: "Available")
        case .missing, .unknown:
            if title.review == .declined {
                RequestActivityPresenter.finish(id: id, available: false, statusLine: "Declined")
            }
        }
        if title.review == .declined {
            RequestActivityPresenter.finish(id: id, available: false, statusLine: "Declined")
        }
    }

    /// APNs `LibraryAlert.seerrRequest` — keep or refresh a matching activity when present.
    static func notePush(alertID: String, body: String) {
        let title = body
            .replacingOccurrences(of: #"^.+ requested "#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        RequestActivityPresenter.start(
            id: alertID,
            title: title.isEmpty ? AppLanguage.string("ui.request", default: "Request") : title,
            subtitle: AppLanguage.string("ui.request", default: "Request"),
            statusLine: "Pending",
            badgeLabel: "PENDING"
        )
    }

    static func noteAvailable(title: String, id: String) {
        RequestActivityPresenter.finish(id: id, available: true, statusLine: "Available")
    }

    private static func activityID(for title: SeerrTitle) -> String {
        if let requestID = title.requestID {
            return "request-\(requestID)"
        }
        return title.id
    }

    private static func subtitle(for title: SeerrTitle) -> String {
        var parts: [String] = [title.kind == .movie ? "Movie" : "TV"]
        if let year = title.year {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }
}
