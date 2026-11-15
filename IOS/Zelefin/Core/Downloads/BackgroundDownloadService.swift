import Foundation

/// A queued or in-flight background download, persisted to disk so it can be finalised even
/// when iOS relaunches the app after the transfer finishes in the background.
struct DownloadJob: Codable, Sendable {
    var id: String                       // the item's id; one active download per item
    var item: MediaItem
    var destinationRelativePath: String  // media file path relative to the Downloads root
    var container: String
    var videoCodec: String?
    var videoRange: VideoRange
    var audioFormat: AudioFormat
    var knownSize: Int64
    var userID: String
    var serverHost: String
    var artworkRelativePath: String?
    var showArtworkRelativePath: String?
    var serverDownloadID: String?
}

/// Owns the single background `URLSession` that carries downloaded media. A background session
/// keeps transferring while the app is suspended, locked, or terminated — nsurlsessiond runs it
/// out of process and relaunches the app to deliver the completion. The old foreground session
/// died the moment the app left the foreground; this one does not.
///
/// The service is deliberately independent of `DownloadStore`: it recomputes the Downloads root
/// itself and persists its own job list, so a cold launch triggered purely by a finished transfer
/// can still move the file into place and hand the record back once the store attaches.
final class BackgroundDownloadService: NSObject, @unchecked Sendable {
    static let shared = BackgroundDownloadService()

    static let sessionIdentifier = "app.zelefin.downloads.background"

    private let lock = NSLock()
    private var jobs: [String: DownloadJob] = [:]
    private var staged: [String: DownloadedFile] = [:]
    private var bufferedFinished: [(DownloadJob, DownloadedFile)] = []
    private var bufferedFailed: [(DownloadJob, Error)] = []
    private var lastReport: [String: Date] = [:]
    private var didLoadPending = false

    /// Set by `DownloadStore`. Invoked on the main actor.
    var onProgress: (@MainActor @Sendable (_ jobID: String, _ written: Int64, _ expected: Int64) -> Void)?
    var onFinished: (@MainActor @Sendable (_ job: DownloadJob, _ file: DownloadedFile) -> Void)?
    var onFailed: (@MainActor @Sendable (_ job: DownloadJob, _ error: Error) -> Void)?

    /// Carries UIKit's (non-Sendable) background completion handler across the delegate queue.
    private struct UncheckedSendable<T>: @unchecked Sendable { let value: T }
    private var backgroundCompletion: UncheckedSendable<() -> Void>?

    /// Set by the app delegate from `handleEventsForBackgroundURLSession`; stored until the session
    /// finishes delivering its queued events, then called so UIKit can snapshot and re-suspend.
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock()
        backgroundCompletion = UncheckedSendable(value: handler)
        lock.unlock()
    }

    private lazy var session: URLSession = {
        loadPendingIfNeeded()
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 24 * 60 * 60
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

    private var rootDirectory: URL {
        SnapshotCoding.applicationSupportDirectory(named: "Downloads", fileManager: .default)
    }

    private var pendingURL: URL {
        rootDirectory.appendingPathComponent("pending-downloads.json")
    }

    /// Reconnect to the background session on launch and flush anything that finished while no
    /// handler was attached. Safe to call repeatedly.
    func attachAndFlush() {
        _ = session
        flushBuffers()
    }

    /// Begin a transfer. `destination` is the absolute media path; its relative form is stored in
    /// the job so finalisation survives the app's data container moving between launches.
    @MainActor
    func start(job: DownloadJob, from url: URL, headers: [String: String], allowsCellular: Bool) {
        lock.lock()
        jobs[job.id] = job
        staged[job.id] = nil
        lastReport[job.id] = nil
        lock.unlock()
        persistJobs()

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.allowsCellularAccess = allowsCellular
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let finalizedRequest = request

        // Cancel any prior task for this item first, then start — rebuilding mid-download
        // otherwise left multiple URLSession tasks with the same id (and duplicate catalog rows).
        let jobID = job.id
        session.getAllTasks { [weak self] tasks in
            guard let self else { return }
            for task in tasks where task.taskDescription == jobID {
                task.cancel()
            }
            let task = self.session.downloadTask(with: finalizedRequest)
            task.taskDescription = jobID
            task.resume()
        }
    }

    /// Stop an active transfer and forget its job.
    func cancel(jobID: String) {
        lock.lock()
        jobs[jobID] = nil
        staged[jobID] = nil
        lastReport[jobID] = nil
        lock.unlock()
        persistJobs()
        session.getAllTasks { tasks in
            for task in tasks where task.taskDescription == jobID {
                task.cancel()
            }
        }
    }

    /// Job ids the service still considers in flight — used by the store to rebuild its progress
    /// rows after a relaunch.
    func activeJobs() -> [DownloadJob] {
        loadPendingIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return Array(jobs.values)
    }

    // MARK: - Persistence

    private func loadPendingIfNeeded() {
        lock.lock()
        let alreadyLoaded = didLoadPending
        didLoadPending = true
        lock.unlock()
        guard !alreadyLoaded else { return }
        guard let data = try? Data(contentsOf: pendingURL),
              let decoded = try? JSONDecoder().decode([DownloadJob].self, from: data) else {
            return
        }
        lock.lock()
        for job in decoded where jobs[job.id] == nil {
            jobs[job.id] = job
        }
        lock.unlock()
    }

    private func persistJobs() {
        lock.lock()
        let snapshot = Array(jobs.values)
        lock.unlock()
        do {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            if snapshot.isEmpty {
                try? FileManager.default.removeItem(at: pendingURL)
            } else {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: pendingURL, options: .atomic)
            }
        } catch {
            return
        }
    }

    private func job(for id: String?) -> DownloadJob? {
        guard let id else { return nil }
        loadPendingIfNeeded()
        lock.lock(); defer { lock.unlock() }
        return jobs[id]
    }

    private func clearJob(_ id: String) {
        lock.lock()
        jobs[id] = nil
        staged[id] = nil
        lastReport[id] = nil
        lock.unlock()
        persistJobs()
    }

    // MARK: - Delivery

    private func deliverFinished(_ job: DownloadJob, _ file: DownloadedFile) {
        lock.lock()
        let handler = onFinished
        if handler == nil { bufferedFinished.append((job, file)) }
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler(job, file) }
    }

    private func deliverFailed(_ job: DownloadJob, _ error: Error) {
        lock.lock()
        let handler = onFailed
        if handler == nil { bufferedFailed.append((job, error)) }
        lock.unlock()
        guard let handler else { return }
        Task { @MainActor in handler(job, error) }
    }

    private func flushBuffers() {
        // Only drain a buffer when its handler is attached. Clearing with no handler drops a
        // finished transfer: the file is on disk, the job is gone, and the catalog never learns.
        lock.lock()
        let finishedHandler = onFinished
        let failedHandler = onFailed
        let finished = finishedHandler == nil ? [] : bufferedFinished
        let failed = failedHandler == nil ? [] : bufferedFailed
        if finishedHandler != nil { bufferedFinished.removeAll() }
        if failedHandler != nil { bufferedFailed.removeAll() }
        lock.unlock()
        if let finishedHandler {
            for (job, file) in finished {
                Task { @MainActor in finishedHandler(job, file) }
            }
        }
        if let failedHandler {
            for (job, error) in failed {
                Task { @MainActor in failedHandler(job, error) }
            }
        }
    }
}

extension BackgroundDownloadService: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData _: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let jobID = downloadTask.taskDescription, let job = job(for: jobID) else { return }
        let now = Date()
        lock.lock()
        let due = now.timeIntervalSince(lastReport[jobID] ?? .distantPast) >= 0.2
        if due { lastReport[jobID] = now }
        let handler = onProgress
        lock.unlock()
        guard due, let handler else { return }
        let expected = DownloadByteCount.resolvedExpected(
            httpExpected: totalBytesExpectedToWrite,
            knownSize: job.knownSize
        )
        Task { @MainActor in handler(jobID, totalBytesWritten, expected) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let jobID = downloadTask.taskDescription, let job = job(for: jobID) else { return }
        let destination = rootDirectory.appending(path: job.destinationRelativePath)
        do {
            let parent = destination.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            // The temp file is deleted when this callback returns — move it (don't copy) so a
            // multi‑GB title doesn't need twice the free space.
            do {
                try FileManager.default.moveItem(at: location, to: destination)
            } catch {
                try FileManager.default.copyItem(at: location, to: destination)
                try? FileManager.default.removeItem(at: location)
            }
            let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            lock.lock()
            staged[jobID] = DownloadedFile(url: destination, byteSize: size)
            lock.unlock()
        } catch {
            // The move failed; didCompleteWithError will surface it.
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let jobID = task.taskDescription, let job = job(for: jobID) else { return }
        lock.lock()
        let stagedFile = staged[jobID]
        lock.unlock()

        if let error {
            if let url = stagedFile?.url { try? FileManager.default.removeItem(at: url) }
            clearJob(jobID)
            if DownloadFailure.isCancellation(error) { return }
            deliverFailed(job, error)
            return
        }

        guard let response = task.response, DownloadHTTP.isSuccessfulFileResponse(response),
              let stagedFile else {
            let status = (task.response as? HTTPURLResponse)?.statusCode ?? 0
            let body = (stagedFile?.url).flatMap { try? Data(contentsOf: $0) }
            if let url = stagedFile?.url { try? FileManager.default.removeItem(at: url) }
            clearJob(jobID)
            deliverFailed(job, DownloadHTTP.failure(statusCode: status, body: body))
            return
        }

        let ext = DownloadHTTP.pathExtension(from: response, fallback: stagedFile.url.pathExtension)
        var saved = stagedFile.url
        if ext != stagedFile.url.pathExtension {
            let renamed = stagedFile.url.deletingPathExtension().appendingPathExtension(ext)
            try? FileManager.default.removeItem(at: renamed)
            if (try? FileManager.default.moveItem(at: stagedFile.url, to: renamed)) != nil {
                saved = renamed
            }
        }
        clearJob(jobID)
        deliverFinished(job, DownloadedFile(url: saved, byteSize: stagedFile.byteSize))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock()
        let box = backgroundCompletion
        backgroundCompletion = nil
        lock.unlock()
        guard let box else { return }
        DispatchQueue.main.async { box.value() }
    }
}
