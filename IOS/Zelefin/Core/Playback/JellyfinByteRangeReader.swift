import Foundation

/// Seekable byte source that only ever asks for absolute ranges (`bytes=START-END`).
/// Reverse proxies often ignore suffix ranges (`bytes=-N`) and answer 200 instead of 206.
/// Absolute ranges still return 206 on those origins.
///
/// `cancel()` only unblocks an in-flight read. The engine may cancel between probe and
/// playback, then keep using the same reader; a sticky cancelled flag would kill the session.
final class JellyfinByteRangeReader: DirectPlayByteSource, @unchecked Sendable {
    private let url: URL
    private let headers: [String: String]
    private let totalSize: Int64
    private let timeout: TimeInterval
    /// Tight per-request budget for the first read after a seek. Kept under FFmpeg's ~8s
    /// Matroska reposition window so a stalled connection fails fast instead of freezing the scrub.
    private static let seekFillTimeout: TimeInterval = 6
    private let baseChunkSize: Int
    private let maxChunkSize: Int
    private let session: ByteRangeSession
    private let lock = NSLock()
    private let generationLock = NSLock()
    private var position: Int64 = 0
    private var bufferStart: Int64 = -1
    private var buffer: [UInt8] = []
    private var lastFetchEnd: Int64 = -1
    private var currentChunkSize: Int
    private var fetchGeneration = 0
    private var isClosed = false
    private var tailStart: Int64 = -1
    private var tail: [UInt8] = []

    var discImageProbeEnabled: Bool { false }

    init?(url: URL, headers: [String: String], knownSize: Int64? = nil, timeout: TimeInterval = 30) {
        let session = ByteRangeSession(timeout: timeout)
        let probed: Int64?
        if let knownSize, knownSize > 0 {
            probed = nil
        } else {
            probed = session.probeSize(url: url, headers: headers)
        }
        guard let size = HTTPRangeSupport.preferredSize(known: knownSize, probed: probed) else {
            session.close()
            return nil
        }
        self.url = url
        self.headers = headers
        self.timeout = timeout
        // 256 KB matches the AVIO callback window. A 1 MB random GET can occupy the
        // whole 8s Matroska seek budget, after which the next cue/cluster read aborts.
        self.baseChunkSize = 262_144
        self.maxChunkSize = 8_388_608
        self.currentChunkSize = baseChunkSize
        self.totalSize = size
        self.session = session
        prefetchTail()
    }

    private init(url: URL, headers: [String: String], totalSize: Int64, timeout: TimeInterval) {
        self.url = url
        self.headers = headers
        self.totalSize = totalSize
        self.timeout = timeout
        self.baseChunkSize = 262_144
        self.maxChunkSize = 8_388_608
        self.currentChunkSize = baseChunkSize
        self.session = ByteRangeSession(timeout: timeout)
        prefetchTail()
    }

    func read(_ outBuffer: UnsafeMutablePointer<UInt8>?, size n: Int32) -> Int32 {
        guard let out = outBuffer, n > 0 else { return -1 }
        lock.lock()
        if position >= totalSize {
            lock.unlock()
            return 0
        }
        if let copied = copyFromCachedLocked(into: out, requested: n) {
            lock.unlock()
            return copied
        }

        let seekFill = HTTPRangeSupport.isSeekFill(position: position, lastFetchEnd: lastFetchEnd)
        currentChunkSize = HTTPRangeSupport.nextChunkSize(
            position: position,
            lastFetchEnd: lastFetchEnd,
            current: currentChunkSize,
            base: baseChunkSize,
            maxChunk: maxChunkSize
        )
        let fetchPos = position
        let want = Int(min(Int64(currentChunkSize), totalSize - position))
        generationLock.lock()
        let generation = fetchGeneration
        generationLock.unlock()
        // Do not hold `lock` across HTTP: FFmpeg seek needs it, and the engine
        // aborts reposition after 8s if the cursor cannot move.
        lock.unlock()

        guard want > 0 else { return 0 }
        lock.lock()
        let closed = isClosed
        lock.unlock()
        guard !closed else { return -1 }
        let data = fetch(offset: fetchPos, length: want, seekFill: seekFill)

        lock.lock()
        defer { lock.unlock() }
        generationLock.lock()
        let stale = fetchGeneration != generation
        generationLock.unlock()
        if stale { return -1 }

        if let data, !data.isEmpty {
            let fetchedEnd = fetchPos + Int64(data.count)
            if position >= fetchPos, position < fetchedEnd {
                bufferStart = fetchPos
                buffer = [UInt8](data)
                lastFetchEnd = fetchedEnd
            }
        }

        // Seek moved the cursor. This call still belongs to the old FFmpeg read.
        if position != fetchPos { return -1 }
        guard let data, !data.isEmpty else { return -1 }
        return copyFromCachedLocked(into: out, requested: n) ?? -1
    }

    func seek(offset: Int64, whence: Int32) -> Int64 {
        if HTTPRangeSupport.reportsSize(whence) { return totalSize }
        lock.lock()
        defer { lock.unlock() }
        let target: Int64
        switch HTTPRangeSupport.seekWhence(whence) {
        case SEEK_SET: target = offset
        case SEEK_CUR: target = position + offset
        case SEEK_END: target = totalSize + offset
        default: return -1
        }
        guard target >= 0 else { return -1 }
        position = target
        if bufferStart >= 0 {
            let end = bufferStart + Int64(buffer.count)
            if target < bufferStart || target >= end {
                buffer = []
                bufferStart = -1
            }
        }
        return target
    }

    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
        session.close()
    }

    func cancel() {
        generationLock.lock()
        fetchGeneration += 1
        generationLock.unlock()
        session.cancelInFlight()
    }

    func makeIndependentReader() -> DirectPlayByteSource? {
        JellyfinByteRangeReader(url: url, headers: headers, totalSize: totalSize, timeout: timeout)
    }

    private func copyFromCachedLocked(into out: UnsafeMutablePointer<UInt8>, requested n: Int32) -> Int32? {
        if let copied = copyWindowLocked(start: bufferStart, bytes: buffer, into: out, requested: n) {
            return copied
        }
        return copyWindowLocked(start: tailStart, bytes: tail, into: out, requested: n)
    }

    private func copyWindowLocked(
        start: Int64,
        bytes: [UInt8],
        into out: UnsafeMutablePointer<UInt8>,
        requested n: Int32
    ) -> Int32? {
        guard start >= 0,
              position >= start,
              position < start + Int64(bytes.count) else {
            return nil
        }
        let bufOffset = Int(position - start)
        let available = bytes.count - bufOffset
        let toCopy = min(Int(n), available, Int(max(0, totalSize - position)))
        guard toCopy > 0 else { return 0 }
        let copied: Bool = bytes.withUnsafeBufferPointer { src in
            guard let base = src.baseAddress else { return false }
            out.update(from: base.advanced(by: bufOffset), count: toCopy)
            return true
        }
        guard copied else { return nil }
        position += Int64(toCopy)
        return Int32(toCopy)
    }

    /// Matroska Cues usually sit at EOF. Caching the tail makes the first scrub a memory hit
    /// instead of a WAN range GET inside the engine's 8s seek budget.
    private func prefetchTail() {
        let length = Int(min(Int64(4_194_304), totalSize))
        guard length > 0 else { return }
        let start = totalSize - Int64(length)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.installTail(start: start, length: length)
        }
    }

    private func installTail(start: Int64, length: Int) {
        guard !isClosed else { return }
        guard let data = session.rangeGet(url: url, headers: headers, offset: start, length: length),
              !data.isEmpty else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed else { return }
        tailStart = start
        tail = [UInt8](data)
    }

    private func fetch(offset: Int64, length: Int, seekFill: Bool) -> Data? {
        generationLock.lock()
        let generation = fetchGeneration
        generationLock.unlock()
        let requestTimeout = HTTPRangeSupport.readTimeout(
            seekFill: seekFill,
            sequentialTimeout: timeout,
            seekFillTimeout: Self.seekFillTimeout
        )
        // One attempt on a seek fill so a stalled range fails inside FFmpeg's ~8s reposition
        // window and the engine can re-drive it, rather than stacking blocking retries.
        let attempts = seekFill ? 1 : 2
        for _ in 0..<attempts {
            generationLock.lock()
            let stale = fetchGeneration != generation
            generationLock.unlock()
            if stale { return nil }
            if let data = session.rangeGet(
                url: url,
                headers: headers,
                offset: offset,
                length: length,
                timeout: requestTimeout
            ), !data.isEmpty {
                return data
            }
        }
        return nil
    }
}

/// One persistent `URLSession` so cue seeks and sequential reads reuse connections.
private final class ByteRangeSession: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let timeout: TimeInterval
    private var session: URLSession!
    private let lock = NSLock()
    private var inflight: [Int: RangeExchange] = [:]
    /// `URLSession.dataTask` raises an uncaught ObjC exception after `invalidateAndCancel`.
    /// Pause can overlap a demuxer read with session teardown, so that call must not happen.
    private var closed = false

    init(timeout: TimeInterval) {
        self.timeout = timeout
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "identity"]
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = max(timeout, 120)
        configuration.httpMaximumConnectionsPerHost = 4
        let queue = OperationQueue()
        queue.name = "zelefin.byte-range"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
    }

    func probeSize(url: URL, headers: [String: String]) -> Int64? {
        if let total = size(from: exchange(
            url: url,
            headers: headers,
            method: "GET",
            range: HTTPRangeSupport.rangeHeader(offset: 0, length: 1),
            acceptedStatuses: [206, 416],
            maxBytes: 1,
            timeout: timeout
        )) {
            return total
        }
        if let total = size(from: exchange(
            url: url,
            headers: headers,
            method: "GET",
            range: HTTPRangeSupport.rangeHeader(offset: 0, length: 2),
            acceptedStatuses: [206, 416],
            maxBytes: 2,
            timeout: timeout
        )) {
            return total
        }
        return nil
    }

    func rangeGet(
        url: URL,
        headers: [String: String],
        offset: Int64,
        length: Int,
        timeout: TimeInterval? = nil
    ) -> Data? {
        let response = exchange(
            url: url,
            headers: headers,
            method: "GET",
            range: HTTPRangeSupport.rangeHeader(offset: offset, length: length),
            acceptedStatuses: [206],
            maxBytes: length,
            timeout: timeout ?? self.timeout
        )
        guard response.status == 206, !response.body.isEmpty else { return nil }
        return response.body
    }

    func cancelInFlight() {
        // Cancel the requests we started. `getAllTasks` is async and can fire after
        // the next range GET has begun, which aborts the seek fill and surfaces as
        // FFmpeg `Read error` / "reposition did not complete within 8s".
        lock.lock()
        let tasks = inflight.values.compactMap(\.task)
        lock.unlock()
        for task in tasks {
            task.cancel()
        }
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
        session.invalidateAndCancel()
    }

    private func size(from response: RangeExchange.Snapshot) -> Int64? {
        if let contentRange = response.contentRange,
           let total = HTTPRangeSupport.parseContentRangeTotal(contentRange),
           total > 0 {
            return total
        }
        return nil
    }

    private func exchange(
        url: URL,
        headers: [String: String],
        method: String,
        range: String?,
        acceptedStatuses: Set<Int>,
        maxBytes: Int,
        timeout: TimeInterval
    ) -> RangeExchange.Snapshot {
        autoreleasepool {
            let exchange = RangeExchange(maxBytes: maxBytes, acceptedStatuses: acceptedStatuses)
            var request = URLRequest(url: url, timeoutInterval: timeout)
            request.httpMethod = method
            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            if let range {
                request.setValue(range, forHTTPHeaderField: "Range")
            }
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
            lock.lock()
            if closed {
                lock.unlock()
                exchange.finish()
                return exchange.snapshot
            }
            let task = session.dataTask(with: request)
            inflight[task.taskIdentifier] = exchange
            lock.unlock()
            exchange.task = task
            task.resume()
            let finished = exchange.wait(timeout: timeout + 5)
            if !finished {
                task.cancel()
            }
            lock.lock()
            inflight[task.taskIdentifier] = nil
            lock.unlock()
            return exchange.snapshot
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        let exchange = inflight[dataTask.taskIdentifier]
        lock.unlock()
        guard let exchange else {
            completionHandler(.cancel)
            return
        }
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            exchange.finish()
            return
        }
        let allowed = exchange.accept(http)
        if allowed {
            completionHandler(.allow)
        } else {
            completionHandler(.cancel)
            exchange.finish()
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        let exchange = inflight[dataTask.taskIdentifier]
        lock.unlock()
        exchange?.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let exchange = inflight[task.taskIdentifier]
        lock.unlock()
        exchange?.finish()
    }
}

/// One ranged (or HEAD) request. Cancels a non-partial GET so a Range-blind origin never streams the file.
private final class RangeExchange: @unchecked Sendable {
    private let maxBytes: Int
    private let acceptedStatuses: Set<Int>
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var status = 0
    private var contentRange: String?
    private var contentLength: Int64?
    private var body = Data()
    private var signalled = false
    weak var task: URLSessionTask?

    struct Snapshot {
        let status: Int
        let contentRange: String?
        let contentLength: Int64?
        let body: Data
    }

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(status: status, contentRange: contentRange, contentLength: contentLength, body: body)
    }

    init(maxBytes: Int, acceptedStatuses: Set<Int>) {
        self.maxBytes = max(1, maxBytes)
        self.acceptedStatuses = acceptedStatuses
    }

    func wait(timeout: TimeInterval) -> Bool {
        done.wait(timeout: .now() + timeout) == .success
    }

    func accept(_ http: HTTPURLResponse) -> Bool {
        lock.lock()
        status = http.statusCode
        contentRange = http.value(forHTTPHeaderField: "Content-Range")
        if let length = http.value(forHTTPHeaderField: "Content-Length") {
            contentLength = Int64(length)
        }
        let allowed = acceptedStatuses.contains(http.statusCode)
        lock.unlock()
        return allowed
    }

    func append(_ data: Data) {
        lock.lock()
        if body.count < maxBytes {
            let remaining = maxBytes - body.count
            body.append(data.prefix(remaining))
        }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        let already = signalled
        signalled = true
        lock.unlock()
        if !already {
            done.signal()
        }
    }
}
