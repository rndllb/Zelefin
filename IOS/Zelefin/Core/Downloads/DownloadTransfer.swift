import Foundation

enum DownloadHTTP {
    static func isSuccessfulFileResponse(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        guard (200 ..< 300).contains(http.statusCode) else { return false }
        guard let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() else {
            return true
        }
        return !type.contains("text/html")
    }

    static func pathExtension(from response: URLResponse, fallback: String) -> String {
        guard let http = response as? HTTPURLResponse,
              let header = http.value(forHTTPHeaderField: "Content-Disposition"),
              let ext = filenameExtension(fromContentDisposition: header)
        else {
            return fallback
        }
        return ext
    }

    static func filenameExtension(fromContentDisposition header: String) -> String? {
        let filename: String?
        if let star = header.range(of: "filename*=", options: .caseInsensitive) {
            let rest = header[star.upperBound...]
            filename = decodeRFC5987(String(rest.split(separator: ";")[0]))
        } else if let plain = header.range(of: "filename=", options: .caseInsensitive) {
            var rest = header[plain.upperBound...]
            if let end = rest.firstIndex(of: ";") {
                rest = rest[..<end]
            }
            filename = String(rest)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        } else {
            filename = nil
        }
        guard let filename else { return nil }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return StreamContainer.pathExtension(fromContainer: ext) ?? ext
    }

    private static func decodeRFC5987(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let tick = trimmed.range(of: "''") {
            let encoded = String(trimmed[tick.upperBound...])
            return encoded.removingPercentEncoding ?? encoded
        }
        return trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    /// Turns a refused download into the server's own reason. Silo answers 403 when Allow
    /// downloads is off or the account may not download, and 503 when downloads aren't set up.
    static func failure(statusCode: Int, body: Data?) -> ZelefinError {
        let message = serverMessage(in: body)
        switch statusCode {
        case 401:
            return .missingUser
        case 403:
            return .server(message ?? "This server doesn't allow downloads for this account.")
        case 503:
            return .server(message ?? "Downloads aren't available on this server.")
        default:
            return message.map(ZelefinError.server) ?? .downloadFailed
        }
    }

    /// `Message` (Silo, older Jellyfin) or `detail` / `title` (Jellyfin problem details).
    static func serverMessage(in body: Data?) -> String? {
        guard let body, !body.isEmpty, body.count < 64 * 1024,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        for key in ["Message", "message", "detail", "title"] {
            if let text = (json[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }
}

/// Where a finished download landed: renamed to the extension the server's filename carries.
struct DownloadedFile: Sendable {
    let url: URL
    let byteSize: Int64
}

enum DownloadTransfer {
    static func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await JellyfinNetworking.data(for: request)
        guard DownloadHTTP.isSuccessfulFileResponse(response) else {
            throw ZelefinError.downloadFailed
        }
        return data
    }
}
