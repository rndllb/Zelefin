import Foundation
import UIKit

/// Zelefin's own log: what the app did and what went wrong, kept on the device so a user can read it
/// in Settings → Log or send it to the developer. Tokens, passwords, and API keys are taken out of
/// every line before it's written, so a shared log never carries a sign-in.
final class ZelefinLog: @unchecked Sendable {
    enum Level: String, CaseIterable, Sendable {
        case info = "INFO"
        case warning = "WARN"
        case error = "ERROR"
    }

    static let shared = ZelefinLog()

    /// Two files of this size: the current one, and the one before it.
    private static let fileLimit = 1_000_000

    private let queue = DispatchQueue(label: "app.zelefin.log", qos: .utility)
    private let current: URL
    private let previous: URL
    private let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        current = base.appendingPathComponent("zelefin.log")
        previous = base.appendingPathComponent("zelefin.previous.log")
    }

    static func info(_ category: String, _ message: String) {
        shared.write(.info, category, message)
    }

    static func warning(_ category: String, _ message: String) {
        shared.write(.warning, category, message)
    }

    static func error(_ category: String, _ message: String) {
        shared.write(.error, category, message)
    }

    func write(_ level: Level, _ category: String, _ message: String) {
        let date = Date()
        let text = Self.redact(message)
        queue.async {
            let line = "\(self.stamp.string(from: date)) \(level.rawValue) [\(category)] \(text)\n"
            self.append(line)
        }
    }

    /// The whole log, oldest first.
    func contents() -> String {
        queue.sync {
            let older = (try? String(contentsOf: previous, encoding: .utf8)) ?? ""
            let newer = (try? String(contentsOf: current, encoding: .utf8)) ?? ""
            return older + newer
        }
    }

    func clear() {
        queue.sync {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.removeItem(at: current)
        }
    }

    /// A text file to share: what the app, device, and server are, then the log.
    func exportFile(header: String) -> URL? {
        let name = "Zelefin Log \(Self.fileDate.string(from: Date())).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let body = header + "\n\n" + contents()
        do {
            try body.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func append(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        let manager = FileManager.default
        if let size = (try? manager.attributesOfItem(atPath: current.path))?[.size] as? Int,
           size + data.count > Self.fileLimit {
            try? manager.removeItem(at: previous)
            try? manager.moveItem(at: current, to: previous)
        }
        if let handle = try? FileHandle(forWritingTo: current) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: current)
        }
    }

    private static let fileDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm"
        return formatter
    }()

    // MARK: Redaction

    private static let secretPatterns: [(NSRegularExpression, String)] = [
        // Query items and form fields: api_key=…, X-Emby-Token=…, Pw=…, password=…
        (#"(?i)\b(api_?key|x-emby-token|x-mediabrowser-token|access_?token|token|pw|password|secret|client_secret)=([^&\s"',]+)"#, "$1=REDACTED"),
        // JSON fields: "Pw":"…", "password": "…", "AccessToken":"…"
        (#"(?i)"(pw|password|accesstoken|access_token|token|api_?key|secret)"\s*:\s*"[^"]*""#, "\"$1\":\"REDACTED\""),
        // Authorization headers: Bearer …, MediaBrowser … Token="…"
        (#"(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+"#, "Bearer REDACTED"),
        (#"(?i)\btoken="[^"]*""#, "Token=\"REDACTED\"")
    ].compactMap { pattern, template in
        (try? NSRegularExpression(pattern: pattern)).map { ($0, template) }
    }

    static func redact(_ text: String) -> String {
        secretPatterns.reduce(text) { result, rule in
            rule.0.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: rule.1
            )
        }
    }

    /// A request for the log: its method and path, with its query items' secrets taken out.
    static func describe(_ request: URLRequest?) -> String {
        guard let request, let url = request.url else { return "request" }
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query, !query.isEmpty {
            path += "?" + query
        }
        return "\(request.httpMethod ?? "GET") \(url.host ?? "")\(path)"
    }

    // MARK: Header

    /// What a shared log starts with: the app, the device, and the server, never a sign-in.
    @MainActor
    static func header(session: SessionStore) -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let device = UIDevice.current
        var lines = [
            "Zelefin \(version) (\(build))",
            "\(deviceKind) · \(device.systemName) \(device.systemVersion) · \(machine)",
            "Generated \(stampNow())"
        ]
        if let saved = session.session {
            let kind = saved.isEmbyServer ? "Emby" : (saved.isSiloServer ? "Silo" : "Jellyfin")
            let version = saved.serverVersion.map { " \($0)" } ?? ""
            lines.append("Server: \(kind)\(version) · \(saved.serverURL.host ?? saved.serverURL.absoluteString)")
            lines.append("Administrator: \(session.isAdministrator ? "yes" : "no")")
        } else {
            lines.append("Server: not signed in")
        }
        if PluginSettings.hasRequestSession {
            lines.append("Requests: \(PluginSettings.requestService.name)")
        }
        return lines.joined(separator: "\n")
    }

    private static var deviceKind: String {
        #if targetEnvironment(macCatalyst)
        "Mac"
        #else
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
        #endif
    }

    /// The hardware model, such as iPhone14,2 or MacBookPro17,1.
    private static var machine: String {
        #if targetEnvironment(macCatalyst)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        #endif
    }

    private static func stampNow() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: Date())
    }
}
