import Foundation
#if os(iOS)
import UIKit
#endif

struct TitleShare: Hashable, Identifiable, Sendable {
    let itemID: String
    let title: String
    let year: Int?
    let serverURL: URL
    let serverName: String?

    var id: String { "\(itemID)|\(Self.fingerprint(serverURL))" }

    static let urlScheme = "zelefin"

    static func make(item: MediaItem, serverURL: URL, serverName: String?) -> TitleShare {
        let itemID = item.seriesDetailItemID ?? item.id
        let title = item.seriesDetailItemID == nil ? item.name : (item.seriesName ?? item.name)
        return TitleShare(
            itemID: itemID,
            title: title,
            year: item.year,
            serverURL: serverURL,
            serverName: serverName
        )
    }

    var zelefinURL: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        components.host = "item"
        components.queryItems = [
            URLQueryItem(name: "id", value: itemID),
            URLQueryItem(name: "server", value: serverURL.absoluteString),
        ]
        if let url = components.url {
            return url
        }
        return jellyfinURL
    }

    var jellyfinURL: URL {
        Self.jellyfinDetailsURL(serverURL: serverURL, itemID: itemID)
    }

    var shareText: String {
        var lines = [headline]
        if let serverName, !serverName.isEmpty {
            lines.append(serverName)
        }
        lines.append("")
        lines.append("Open in Zelefin:")
        lines.append(zelefinURL.absoluteString)
        lines.append("")
        lines.append("Or in a browser on this server:")
        lines.append(jellyfinURL.absoluteString)
        return lines.joined(separator: "\n")
    }

    var headline: String {
        if let year {
            return "\(title) (\(year))"
        }
        return title
    }

    /// Text plus the Jellyfin web URL so Messages/Mail get a real https preview.
    /// The Zelefin link lives in the text so another install can open the title.
    var activityItems: [Any] {
        [shareText, jellyfinURL]
    }

    struct Incoming: Hashable, Sendable {
        var itemID: String
        var serverURL: URL
    }

    static func parse(_ url: URL) -> Incoming? {
        if url.scheme?.caseInsensitiveCompare(urlScheme) == .orderedSame {
            return parseZelefin(url)
        }
        if url.scheme?.caseInsensitiveCompare("http") == .orderedSame
            || url.scheme?.caseInsensitiveCompare("https") == .orderedSame
        {
            return parseJellyfinWeb(url)
        }
        return nil
    }

    static func jellyfinDetailsURL(serverURL: URL, itemID: String) -> URL {
        let web = ServerURL.join(base: serverURL, path: "/web/index.html")
            ?? serverURL.appending(path: "web/index.html")
        guard var components = URLComponents(url: web, resolvingAgainstBaseURL: false) else {
            return web
        }
        components.fragment = "!/details?id=\(itemID)"
        return components.url ?? web
    }

    static func fingerprint(_ url: URL) -> String {
        let scheme = (url.scheme ?? "https").lowercased()
        let host = (url.host ?? "").lowercased()
        let port = url.port.map { ":\($0)" } ?? ""
        var path = url.path.lowercased()
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        if path == "/" { path = "" }
        return "\(scheme)://\(host)\(port)\(path)"
    }

    private static func parseZelefin(_ url: URL) -> Incoming? {
        let host = url.host?.lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard host == "item" || host == nil || path == "item" || path.hasPrefix("item/") else {
            return nil
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let queryID = items.first { $0.name == "id" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let pathID = path.hasPrefix("item/") ? String(path.dropFirst(5)) : nil
        let itemID = [queryID, pathID].compactMap { $0 }.first { !$0.isEmpty }
        let serverValue = items.first { $0.name == "server" }?.value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let itemID, let serverValue, let serverURL = URL(string: serverValue) else {
            return nil
        }
        return Incoming(itemID: itemID, serverURL: serverURL)
    }

    private static func parseJellyfinWeb(_ url: URL) -> Incoming? {
        let itemID = itemID(in: url)
        guard let itemID, !itemID.isEmpty, let serverURL = jellyfinServerURL(from: url) else {
            return nil
        }
        return Incoming(itemID: itemID, serverURL: serverURL)
    }

    private static func itemID(in url: URL) -> String? {
        if let fragment = url.fragment, let value = queryValue("id", in: fragment) {
            return value
        }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first { $0.name.lowercased() == "id" }?.value
    }

    private static func queryValue(_ name: String, in raw: String) -> String? {
        let query: String
        if let mark = raw.firstIndex(of: "?") {
            query = String(raw[raw.index(after: mark)...])
        } else if raw.contains("=") {
            query = raw
        } else {
            return nil
        }
        var components = URLComponents()
        if query.contains("%") {
            components.percentEncodedQuery = query
        } else {
            components.percentEncodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        }
        return components.queryItems?.first { $0.name.lowercased() == name }?.value
    }

    private static func jellyfinServerURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.query = nil
        var path = components.path
        if let range = path.range(of: "/web", options: [.caseInsensitive, .backwards]) {
            path = String(path[..<range.lowerBound])
        }
        components.path = path
        return components.url
    }
}

#if os(iOS)
enum TitleSharePresenter {
    @MainActor
    static func present(_ share: TitleShare) {
        let activity = UIActivityViewController(activityItems: share.activityItems, applicationActivities: nil)
        activity.excludedActivityTypes = [.addToReadingList, .assignToContact]
        guard let presenter = topViewController() else { return }
        if let popover = activity.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: 16, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
#endif
