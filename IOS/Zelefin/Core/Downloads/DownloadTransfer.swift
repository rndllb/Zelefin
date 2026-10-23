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
    static func download(
        from url: URL,
        headers: [String: String],
        to destination: URL,
        knownSize: Int64 = 0,
        progress: @escaping @MainActor @Sendable (_ written: Int64, _ expected: Int64) -> Void
    ) async throws -> DownloadedFile {
        try await FileDownloadRunner.download(
            from: url,
            headers: headers,
            to: destination,
            knownSize: knownSize,
            progress: progress
        )
    }

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

/// Streams the original file to disk. The temp location from `didFinishDownloadingTo` is only valid in that callback.
private final class FileDownloadRunner: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let knownSize: Int64
    private let progress: @MainActor @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<DownloadedFile, Error>?
    private var copiedSize: Int64 = 0
    private var session: URLSession?
    private var lastReport = Date.distantPast

    static func download(
        from url: URL,
        headers: [String: String],
        to destination: URL,
        knownSize: Int64,
        progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) async throws -> DownloadedFile {
        let runner = FileDownloadRunner(destination: destination, knownSize: knownSize, progress: progress)
        return try await runner.start(url: url, headers: headers)
    }

    private init(
        destination: URL,
        knownSize: Int64,
        progress: @escaping @MainActor @Sendable (Int64, Int64) -> Void
    ) {
        self.destination = destination
        self.knownSize = knownSize
        self.progress = progress
    }

    private func start(url: URL, headers: [String: String]) async throws -> DownloadedFile {
        let configuration = JellyfinNetworking.sessionConfiguration(cacheImages: false)
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 12 * 60 * 60
        configuration.allowsExpensiveNetworkAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 120
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        report(written: totalBytesWritten, httpExpected: totalBytesExpectedToWrite)
    }

    private func report(written: Int64, httpExpected: Int64, force: Bool = false) {
        let now = Date()
        guard force || now.timeIntervalSince(lastReport) >= 0.15 else { return }
        lastReport = now
        let expected = DownloadByteCount.resolvedExpected(httpExpected: httpExpected, knownSize: knownSize)
        Task { @MainActor in
            self.progress(written, expected)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: location, to: destination)
            let values = try FileManager.default.attributesOfItem(atPath: destination.path)
            copiedSize = (values[.size] as? NSNumber)?.int64Value ?? 0
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            try? FileManager.default.removeItem(at: destination)
            finish(.failure(error))
            return
        }
        guard let response = task.response, DownloadHTTP.isSuccessfulFileResponse(response) else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            let body = try? Data(contentsOf: destination)
            try? FileManager.default.removeItem(at: destination)
            finish(.failure(DownloadHTTP.failure(statusCode: status, body: body)))
            return
        }
        report(written: max(copiedSize, 1), httpExpected: max(copiedSize, knownSize), force: true)
        let ext = DownloadHTTP.pathExtension(from: response, fallback: destination.pathExtension)
        var saved = destination
        if ext != destination.pathExtension {
            let renamed = destination.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: renamed)
            if (try? FileManager.default.moveItem(at: destination, to: renamed)) != nil {
                saved = renamed
            }
        }
        finish(.success(DownloadedFile(url: saved, byteSize: copiedSize)))
    }

    private func finish(_ result: Result<DownloadedFile, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        session?.finishTasksAndInvalidate()
        continuation.resume(with: result)
    }
}
