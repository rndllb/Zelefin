import CryptoKit
import Foundation
import os
import UIKit

/// On-screen posters fetch from Jellyfin immediately. Off-screen posters warm in the
/// background at lower priority so the whole library fills without scrolling.
actor ArtworkNetworkGate {
    static let shared = ArtworkNetworkGate()
    static let maxPrefetch = 2

    private var prefetchRunning = 0

    func withPrefetch<T: Sendable>(_ work: @Sendable () async -> T) async -> T? {
        guard await beginPrefetch() else { return nil }
        defer { prefetchRunning = max(0, prefetchRunning - 1) }
        return await work()
    }

    private func beginPrefetch() async -> Bool {
        while !Task.isCancelled {
            if tryStartPrefetch() { return true }
            try? await Task.sleep(for: .milliseconds(40))
        }
        return false
    }

    private func tryStartPrefetch() -> Bool {
        guard prefetchRunning < Self.maxPrefetch else { return false }
        prefetchRunning += 1
        return true
    }
}

/// Two-tier artwork cache: an in-memory `NSCache` fronting a persistent on-disk store in
/// `Caches/`. Visible posters are decoded and returned as soon as Jellyfin responds; the
/// disk write happens afterward so caching never delays the grid. Local file URLs
/// (downloaded media) are decoded directly and never disk-cached.
final class ArtworkCache: @unchecked Sendable {
    static let shared = ArtworkCache()

    private let memory = NSCache<NSURL, UIImage>()
    private let directory: URL
    private let fileManager: FileManager
    private let io = DispatchQueue(label: "app.zelefin.artwork-cache", qos: .utility, attributes: .concurrent)
    private let visibleIO = DispatchQueue(label: "app.zelefin.artwork-cache.visible", qos: .userInitiated, attributes: .concurrent)
    private let inflight = OSAllocatedUnfairLock<[String: Task<RemoteArtwork, Never>]>(uncheckedState: [:])

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.directory = directory ?? SnapshotCoding.cachesDirectory(named: "Artwork", fileManager: fileManager)
        try? fileManager.createDirectory(at: self.directory, withIntermediateDirectories: true)
        memory.countLimit = 500
        memory.totalCostLimit = 96 * 1_024 * 1_024
    }

    // MARK: Memory (synchronous, for view bodies)

    func image(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    func store(_ image: UIImage, for url: URL) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        memory.setObject(image, forKey: url as NSURL, cost: Int(pixels * 4))
    }

    // MARK: Load: Jellyfin immediately (show) → disk write. Disk is only a parallel shortcut.

    func load(from url: URL, persist: Bool = true) async -> UIImage? {
        if let cached = image(for: url) { return cached }

        if url.isFileURL {
            guard let image = await readFile(url) else { return nil }
            store(image, for: url)
            return image
        }

        if persist, hasMissingMarker(for: url), !CachePreferences.autoRefreshMissingImages {
            return nil
        }

        let diskReady = persist && hasCachedData(for: url)
        return await withTaskGroup(of: (Bool, UIImage?).self) { group in
            group.addTask { (false, await self.imageFromNetwork(url, persist: persist)) }
            if diskReady {
                group.addTask { (true, await self.readDisk(for: url, qos: .userInitiated)) }
            }
            var found: UIImage?
            for await (fromDisk, image) in group {
                guard let image else { continue }
                found = image
                if fromDisk { self.cancelVisibleFetch(for: url) }
                group.cancelAll()
                break
            }
            if let found {
                store(found, for: url)
            }
            return found
        }
    }

    private func imageFromNetwork(_ url: URL, persist: Bool) async -> UIImage? {
        let outcome = await fetchCoalesced(url, serviceType: .responsiveData, timeout: nil)
        switch outcome {
        case let .bytes(data):
            guard let image = UIImage(data: data) else {
                if persist { markMissing(url) }
                return nil
            }
            store(image, for: url)
            if persist { writeDisk(data, for: url) }
            return image
        case .absent:
            if persist { markMissing(url) }
            return nil
        case .failed:
            return nil
        }
    }

    /// Whether the remote image already has a persisted copy — a cheap file-exists check the
    /// prefetcher uses to skip work it has already done.
    func hasCachedData(for url: URL) -> Bool {
        guard !url.isFileURL else { return true }
        return fileManager.fileExists(atPath: diskURL(for: url).path)
    }

    func isSettled(for url: URL) -> Bool {
        if hasCachedData(for: url) { return true }
        if CachePreferences.autoRefreshMissingImages { return false }
        return hasMissingMarker(for: url)
    }

    func usage() -> ArtworkCacheUsage {
        CacheInventory.artworkUsage(at: directory, fileManager: fileManager)
    }

    func remove(_ kind: ArtworkImageKind) {
        CacheInventory.removeArtwork(kind, from: directory, fileManager: fileManager)
        memory.removeAllObjects()
    }

    func removeAll() {
        CacheInventory.removeArtwork(nil, from: directory, fileManager: fileManager)
        memory.removeAllObjects()
    }

    /// Drops memory, disk, and in-flight fetches for these URLs so a replaced
    /// Jellyfin image is not served from the previous bytes.
    func remove(urls: [URL]) {
        for url in urls {
            memory.removeObject(forKey: url as NSURL)
            cancelVisibleFetch(for: url)
            let preferred = preferredDiskURL(for: url)
            let legacy = legacyDiskURL(for: url)
            try? fileManager.removeItem(at: preferred)
            try? fileManager.removeItem(at: legacy)
            try? fileManager.removeItem(at: missingURL(for: url))
            try? fileManager.removeItem(at: legacy.appendingPathExtension("missing"))
        }
    }

    func settledCount(in urls: [URL]) -> Int {
        urls.reduce(0) { $0 + (isSettled(for: $1) ? 1 : 0) }
    }

    func cachedCount(in urls: [URL]) -> Int {
        settledCount(in: urls)
    }

    func markMissing(_ url: URL) {
        let file = missingURL(for: url)
        try? Data().write(to: file, options: .atomic)
    }

    /// Persist a remote image without putting it on screen. Missing or invalid artwork is
    /// recorded so a 404 cannot pin the indexing bar one short of complete.
    @discardableResult
    func prefetch(_ url: URL) async -> Bool {
        guard !url.isFileURL else { return true }
        if isSettled(for: url) { return true }
        return await ArtworkNetworkGate.shared.withPrefetch {
            switch await self.fetchCoalesced(url, serviceType: .background, timeout: 12) {
            case let .bytes(data) where Self.isLikelyImage(data):
                self.writeDisk(data, for: url)
                return true
            case .bytes, .absent:
                self.markMissing(url)
                return true
            case .failed:
                return true
            }
        } ?? false
    }

    /// JPEG / PNG / RIFF (WebP) magic — enough to persist a prefetch without a full decode.
    static func isLikelyImage(_ data: Data) -> Bool {
        guard data.count >= 12 else { return false }
        if data[0] == 0xFF, data[1] == 0xD8 { return true }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) { return true }
        return false
    }

    // MARK: Disk

    /// Key strips `api_key` and cache-busting `v` so a re-auth (new token) still hits the cache.
    static func diskKey(for url: URL) -> String {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let query = (components?.queryItems ?? [])
            .filter { $0.name != "api_key" && $0.name != "v" }
            .sorted { $0.name < $1.name }
            .map { "\($0.name)=\($0.value ?? "")" }
            .joined(separator: "&")
        let canonical = (components?.path ?? url.path) + "?" + query
        let digest = SHA256.hash(data: Data(canonical.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func preferredDiskURL(for url: URL) -> URL {
        let kind = ArtworkImageKind.classify(url)
        return directory.appendingPathComponent(
            "\(kind.rawValue)-\(Self.diskKey(for: url))",
            isDirectory: false
        )
    }

    private func legacyDiskURL(for url: URL) -> URL {
        directory.appendingPathComponent(Self.diskKey(for: url), isDirectory: false)
    }

    private func existingDiskURL(for url: URL) -> URL? {
        let preferred = preferredDiskURL(for: url)
        if fileManager.fileExists(atPath: preferred.path) { return preferred }
        let legacy = legacyDiskURL(for: url)
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        return nil
    }

    private func diskURL(for url: URL) -> URL {
        existingDiskURL(for: url) ?? preferredDiskURL(for: url)
    }

    private func missingURL(for url: URL) -> URL {
        preferredDiskURL(for: url).appendingPathExtension("missing")
    }

    private func hasMissingMarker(for url: URL) -> Bool {
        fileManager.fileExists(atPath: missingURL(for: url).path)
            || fileManager.fileExists(atPath: legacyDiskURL(for: url).appendingPathExtension("missing").path)
    }

    private func readDisk(for url: URL, qos: DispatchQoS.QoSClass = .utility) async -> UIImage? {
        let file = diskURL(for: url)
        let queue = qos == .userInitiated ? visibleIO : io
        return await withCheckedContinuation { continuation in
            queue.async {
                guard let data = try? Data(contentsOf: file), let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func writeDisk(_ data: Data, for url: URL) {
        let file = preferredDiskURL(for: url)
        let legacy = legacyDiskURL(for: url)
        let missing = missingURL(for: url)
        let legacyMissing = legacy.appendingPathExtension("missing")
        io.async(flags: .barrier) {
            try? data.write(to: file, options: .atomic)
            try? self.fileManager.removeItem(at: missing)
            try? self.fileManager.removeItem(at: legacy)
            try? self.fileManager.removeItem(at: legacyMissing)
        }
    }

    private func readFile(_ url: URL) async -> UIImage? {
        await withCheckedContinuation { continuation in
            io.async {
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    private func fetchCoalesced(
        _ url: URL,
        serviceType: URLRequest.NetworkServiceType,
        timeout: TimeInterval?
    ) async -> RemoteArtwork {
        let key = Self.diskKey(for: url)
        let visibleKey = key
        let prefetchKey = key + "#prefetch"
        let isPrefetch = serviceType == .background

        let task = inflight.withLock { state -> Task<RemoteArtwork, Never> in
            if isPrefetch, let visible = state[visibleKey] {
                return visible
            }
            let lookup = isPrefetch ? prefetchKey : visibleKey
            if let existing = state[lookup] {
                return existing
            }
            let created = Task<RemoteArtwork, Never> {
                let outcome = await self.fetch(
                    url,
                    serviceType: serviceType,
                    timeout: timeout,
                    ignoreCache: !isPrefetch
                )
                self.inflight.withLock { _ = $0.removeValue(forKey: lookup) }
                return outcome
            }
            state[lookup] = created
            return created
        }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            if !isPrefetch { task.cancel() }
        }
    }

    private func cancelVisibleFetch(for url: URL) {
        let key = Self.diskKey(for: url)
        inflight.withLock { state in
            state[key]?.cancel()
            _ = state.removeValue(forKey: key)
        }
    }

    private func fetch(
        _ url: URL,
        serviceType: URLRequest.NetworkServiceType,
        timeout: TimeInterval?,
        ignoreCache: Bool
    ) async -> RemoteArtwork {
        var attempt = 0
        while true {
            guard !Task.isCancelled else { return .failed }
            do {
                let (data, response) = try await JellyfinNetworking.data(
                    from: url,
                    ignoreCache: ignoreCache,
                    serviceType: serviceType,
                    timeout: timeout
                )
                guard let http = response as? HTTPURLResponse else { return .failed }
                if (200 ..< 300).contains(http.statusCode) {
                    return data.isEmpty ? .absent : .bytes(data)
                }
                if http.statusCode == 404 || http.statusCode == 204 || http.statusCode == 400 {
                    return .absent
                }
                return .failed
            } catch {
                // URLSession reuses a kept-alive HTTP/2 connection; after the server drops it while
                // idle, the first request fails with "connection lost" (-1005). One retry opens a fresh
                // connection instead of leaving the poster permanently blank.
                guard attempt == 0, !Task.isCancelled, Self.isTransientConnectionError(error) else {
                    return .failed
                }
                attempt += 1
            }
        }
    }

    private static func isTransientConnectionError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .timedOut:
            return true
        default:
            return false
        }
    }
}

private enum RemoteArtwork: Sendable {
    case bytes(Data)
    case absent
    case failed
}
