import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadStore {
    private let fileManager: FileManager
    private let rootDirectory: URL
    private(set) var records: [DownloadedItem] = []
    private(set) var progress: [String: DownloadProgress] = [:]
    private var tasks: [String: Task<Void, Error>] = [:]

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.rootDirectory = directory
        } else {
            self.rootDirectory = SnapshotCoding.applicationSupportDirectory(
                named: "Downloads",
                fileManager: fileManager
            )
        }
        records = (try? loadCatalog()) ?? []
    }

    func scoped(_ account: SavedSession?) -> [DownloadedItem] {
        guard let account else { return [] }
        let host = SnapshotCoding.host(from: account.serverURL)
        return records.filter { $0.userID == account.userID && $0.serverHost == host }
    }

    func libraryRows(for account: SavedSession?) -> [DownloadLibraryRow] {
        DownloadLibraryLayout.rows(from: scoped(account))
    }

    func coverMark(for item: MediaItem, account: SavedSession?) -> DownloadCoverMark {
        DownloadCoverLogic.mark(for: item, records: scoped(account), progress: scopedProgress(account))
    }

    func transfer(for item: MediaItem, account: SavedSession?) -> DownloadProgress? {
        DownloadCoverLogic.activeProgress(for: item, progress: scopedProgress(account))
    }

    func activeTransfers(for account: SavedSession?) -> [DownloadProgress] {
        scopedProgress(account)
            .values
            .sorted { lhs, rhs in
                (lhs.item?.name ?? "") < (rhs.item?.name ?? "")
            }
    }

    func control(
        for item: MediaItem,
        episodes: [MediaItem] = [],
        account: SavedSession?
    ) -> DownloadControlState {
        DownloadCoverLogic.control(
            for: item,
            episodes: episodes,
            records: scoped(account),
            progress: scopedProgress(account)
        )
    }

    func posterURL(for item: MediaItem, account: SavedSession?, remote: URL?) -> URL? {
        localArtworkURL(for: item, account: account) ?? remote
    }

    func localArtworkURL(for item: MediaItem, account: SavedSession?) -> URL? {
        let matches = DownloadCoverLogic.matchingRecords(for: item, in: scoped(account))
        if item.kind == .series {
            if let show = matches.compactMap(\.relativeShowArtworkPath).first {
                return existingFile(storedFile(show))
            }
        }
        guard let path = matches.compactMap(\.relativeArtworkPath).first else { return nil }
        return existingFile(storedFile(path))
    }

    func playableItem(
        for item: MediaItem,
        allowRelated: Bool = false,
        account: SavedSession?
    ) -> MediaItem? {
        record(for: item, allowRelated: allowRelated, account: account)?.item
    }

    func playbackPlan(
        for item: MediaItem,
        allowRelated: Bool = false,
        account: SavedSession?
    ) -> PlaybackPlan? {
        guard let record = record(for: item, allowRelated: allowRelated, account: account) else {
            return nil
        }
        guard let url = existingMediaURL(for: record) else {
            remove(id: record.item.id, account: account)
            return nil
        }
        let playable = record.item.id == item.id ? item : record.item
        return PlaybackPlan(
            item: playable,
            streamURL: url,
            playSessionID: nil,
            mediaSourceID: nil,
            method: .directPlay,
            container: record.container,
            videoCodec: record.videoCodec,
            videoRange: record.videoRange,
            audioFormat: record.audioFormat,
            startTime: playable.playbackPosition,
            byteSize: record.byteSize,
            extraHTTPHeaders: [:],
            audioTracks: [],
            subtitleTracks: []
        )
    }

    private func record(
        for item: MediaItem,
        allowRelated: Bool,
        account: SavedSession?
    ) -> DownloadedItem? {
        let records = scoped(account)
        if allowRelated {
            return DownloadPlaybackSelection.relatedRecord(for: item, in: records)
        }
        return DownloadPlaybackSelection.record(for: item, in: records)
    }

    func pauseTransfer(for item: MediaItem, account: SavedSession?) {
        cancelTransfer(for: item, account: account)
    }

    func downloadMany(
        items: [MediaItem],
        library: (any LibraryServing)?,
        account: SavedSession?
    ) async throws {
        for item in items {
            try await toggle(item: item, library: library, account: account)
        }
    }

    func cancelTransfer(for item: MediaItem, account: SavedSession?) {
        let scoped = scopedProgress(account)
        guard let active = DownloadCoverLogic.activeProgress(for: item, progress: scoped) else {
            return
        }
        let id = scoped.first(where: { $0.value == active })?.key ?? active.item?.id ?? item.id
        guard !id.isEmpty else { return }
        tasks[id]?.cancel()
        tasks[id] = nil
        progress[id] = nil
    }

    func toggle(
        item: MediaItem,
        episodes: [MediaItem] = [],
        library: (any LibraryServing)?,
        account: SavedSession?
    ) async throws {
        guard let target = DownloadEligibility.playableItem(from: item, episodes: episodes) else {
            return
        }
        if let existing = scoped(account).first(where: { $0.item.id == target.id }) {
            if let serverDownloadID = existing.serverDownloadID, let library {
                await library.deleteServerDownload(id: serverDownloadID)
            }
            remove(id: target.id, account: account)
            return
        }
        if let running = tasks[target.id] {
            running.cancel()
            tasks[target.id] = nil
            progress[target.id] = nil
            return
        }
        guard let library, let account else {
            throw ZelefinError.missingUser
        }
        if PlaybackPreferences.downloadWifiOnly {
            let monitor = NWPathMonitor()
            let path = await withCheckedContinuation { continuation in
                monitor.pathUpdateHandler = { path in
                    continuation.resume(returning: path)
                    monitor.cancel()
                }
                monitor.start(queue: DispatchQueue.global())
            }
            if path.usesInterfaceType(.wifi) == false {
                throw ZelefinError.server("Connect to Wi-Fi to download, or turn off Wi-Fi only in Playback settings.")
            }
        }

        let host = SnapshotCoding.host(from: account.serverURL)
        progress[target.id] = DownloadProgress(
            item: target,
            fraction: 0,
            bytesWritten: 0,
            bytesExpected: 0,
            seriesID: target.seriesID,
            userID: account.userID,
            serverHost: host
        )
        let work = Task {
            try await performDownload(target: target, library: library, account: account)
        }
        tasks[target.id] = work
        do {
            try await work.value
            tasks[target.id] = nil
            progress[target.id] = nil
        } catch {
            tasks[target.id] = nil
            progress[target.id] = nil
            if DownloadFailure.isCancellation(error) {
                return
            }
            throw error
        }
    }

    func removeDownloaded(item: MediaItem, episodes: [MediaItem] = [], account: SavedSession?) {
        guard let target = DownloadEligibility.playableItem(from: item, episodes: episodes) else {
            return
        }
        remove(id: target.id, account: account)
    }

    func remove(id: String, account: SavedSession?) {
        tasks[id]?.cancel()
        tasks[id] = nil
        progress[id] = nil
        guard let record = scoped(account).first(where: { $0.item.id == id }) else { return }
        removeFiles(for: record)
        records.removeAll { $0.item.id == id && $0.userID == record.userID && $0.serverHost == record.serverHost }
        persist()
    }

    func remove(row: DownloadLibraryRow, account: SavedSession?) {
        for record in row.records {
            remove(id: record.item.id, account: account)
        }
    }

    private func performDownload(
        target: MediaItem,
        library: any LibraryServing,
        account: SavedSession
    ) async throws {
        let plan = try await library.playbackPlan(for: target)
        try Task.checkCancellation()
        // Backends resolve the download differently: Jellyfin hands back a direct
        // original-file URL, while Silo registers a managed download, waits for the
        // server to prepare it, and returns the ready file URL plus its row id.
        let asset = try await library.prepareDownloadAsset(for: target, plan: plan)
        try Task.checkCancellation()
        let downloadURL = asset.url
        let folder = itemDirectory(account: account, itemID: target.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)

        let mediaURL = folder.appendingPathComponent("media.\(plan.container)")
        let headers = asset.headers
        let itemID = target.id
        let host = SnapshotCoding.host(from: account.serverURL)
        let knownSize = plan.byteSize ?? 0
        if knownSize > 0, var current = progress[itemID] {
            current.bytesExpected = knownSize
            progress[itemID] = current
        }
        let bytes = try await DownloadTransfer.download(
            from: downloadURL,
            headers: headers,
            to: mediaURL,
            knownSize: knownSize,
            progress: { written, expected in
                guard var current = self.progress[itemID] else { return }
                current.bytesWritten = written
                current.bytesExpected = expected
                current.fraction = DownloadByteCount.fraction(written: written, expected: expected)
                self.progress[itemID] = current
            }
        )
        try Task.checkCancellation()

        let artworkPath = await saveArtwork(
            from: library.primaryURL(for: target, maxHeight: 900),
            headers: headers,
            to: folder.appendingPathComponent("poster.jpg")
        )
        var showArtworkPath: String?
        if target.kind == .episode {
            showArtworkPath = await saveArtwork(
                from: library.primaryURL(for: target.seriesShowcasePreview(), maxHeight: 900),
                headers: headers,
                to: folder.appendingPathComponent("show.jpg")
            )
        }

        let record = DownloadedItem(
            item: target,
            relativeMediaPath: relativePath(mediaURL),
            relativeArtworkPath: artworkPath,
            relativeShowArtworkPath: showArtworkPath,
            container: plan.container,
            videoCodec: plan.videoCodec,
            videoRange: plan.videoRange,
            audioFormat: plan.audioFormat,
            byteSize: bytes > 0 ? bytes : (plan.byteSize ?? 0),
            userID: account.userID,
            serverHost: host,
            downloadedAt: Date(),
            serverDownloadID: asset.serverDownloadID
        )

        records.removeAll {
            $0.item.id == record.item.id && $0.userID == record.userID && $0.serverHost == record.serverHost
        }
        records.append(record)
        persist()

        if let serverDownloadID = asset.serverDownloadID {
            await library.finalizeServerDownload(id: serverDownloadID)
        }
    }

    private func saveArtwork(from url: URL?, headers: [String: String], to destination: URL) async -> String? {
        guard let url else { return nil }
        do {
            let data = try await DownloadTransfer.data(from: url, headers: headers)
            guard !data.isEmpty else { return nil }
            try data.write(to: destination, options: .atomic)
            return relativePath(destination)
        } catch {
            return nil
        }
    }

    private func scopedProgress(_ account: SavedSession?) -> [String: DownloadProgress] {
        guard let account else { return [:] }
        let host = SnapshotCoding.host(from: account.serverURL)
        return progress.filter { _, value in
            value.userID == account.userID && value.serverHost == host
        }
    }

    private func itemDirectory(account: SavedSession, itemID: String) -> URL {
        rootDirectory
            .appendingPathComponent("files", isDirectory: true)
            .appendingPathComponent(Self.sanitized(SnapshotCoding.host(from: account.serverURL)), isDirectory: true)
            .appendingPathComponent(Self.sanitized(account.userID), isDirectory: true)
            .appendingPathComponent(Self.sanitized(itemID), isDirectory: true)
    }

    private func relativePath(_ url: URL) -> String {
        let root = rootDirectory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(root) else { return url.lastPathComponent }
        return String(path.dropFirst(root.count).drop(while: { $0 == "/" }))
    }

    private func storedFile(_ relativePath: String) -> URL {
        rootDirectory.appending(path: relativePath)
    }

    private func existingMediaURL(for record: DownloadedItem) -> URL? {
        existingFile(storedFile(record.relativeMediaPath))
    }

    private func existingFile(_ url: URL) -> URL? {
        fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private func removeFiles(for record: DownloadedItem) {
        let media = storedFile(record.relativeMediaPath)
        try? fileManager.removeItem(at: media.deletingLastPathComponent())
    }

    private func catalogURL() -> URL {
        rootDirectory.appendingPathComponent("catalog.json")
    }

    private func loadCatalog() throws -> [DownloadedItem] {
        let url = catalogURL()
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        let catalog = try SnapshotCoding.decoder.decode(DownloadCatalog.self, from: data)
        guard catalog.version == DownloadCatalog.currentVersion else { return [] }
        return catalog.records.filter { record in
            fileManager.fileExists(atPath: storedFile(record.relativeMediaPath).path)
        }
    }

    private func persist() {
        do {
            try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
            excludeFromBackup(rootDirectory)
            let catalog = DownloadCatalog(version: DownloadCatalog.currentVersion, records: records)
            let data = try SnapshotCoding.encoder.encode(catalog)
            try data.write(to: catalogURL(), options: .atomic)
        } catch {
            return
        }
    }

    private func excludeFromBackup(_ url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        try? mutable.setResourceValues(values)
    }

    private static func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
    }
}
