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

    /// The version picked on a title's page, which a download of that title fetches. Nil keeps the
    /// server's first version.
    var chosenVersion: @MainActor (String) -> String? = { _ in nil }

    /// Supplies the signed-in library so a finished background download can tell the server it
    /// completed. Nil (e.g. during a background relaunch with no UI) simply skips that cleanup.
    var libraryProvider: @MainActor () -> (any LibraryServing)? = { nil }

    /// The background transfer engine. Only the production (default-directory) store drives it, so a
    /// test store with its own directory never touches the shared session.
    private let usesBackgroundService: Bool

    private var backgroundService: BackgroundDownloadService? {
        usesBackgroundService ? .shared : nil
    }

    /// Stop an in-flight transfer and clear its Live Activity.
    private func cancelJob(_ jobID: String) {
        backgroundService?.cancel(jobID: jobID)
        DownloadActivityPresenter.stop(id: jobID)
    }

    init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directory {
            self.rootDirectory = directory
            self.usesBackgroundService = false
        } else {
            self.rootDirectory = SnapshotCoding.applicationSupportDirectory(
                named: "Downloads",
                fileManager: fileManager
            )
            self.usesBackgroundService = true
        }
        records = (try? loadCatalog()) ?? []
        if usesBackgroundService {
            configureBackgroundService()
        }
    }

    private func configureBackgroundService() {
        let service = BackgroundDownloadService.shared
        service.onProgress = { [weak self] jobID, written, expected in
            guard let self, var current = self.progress[jobID] else { return }
            current.bytesWritten = written
            current.bytesExpected = expected
            current.fraction = DownloadByteCount.fraction(written: written, expected: expected)
            self.progress[jobID] = current
            DownloadActivityPresenter.update(
                id: jobID,
                fraction: expected > 0 ? current.fraction : nil,
                statusLine: DownloadByteCount.sizeLabel(written: written, expected: expected)
            )
        }
        service.onFinished = { [weak self] job, file in
            self?.finalizeDownload(job: job, file: file)
        }
        service.onFailed = { [weak self] job, error in
            self?.handleDownloadFailure(job: job, error: error)
        }
        // Reconnect to any transfer that was still running when the app was last suspended or
        // killed, and show it in the UI again.
        for job in service.activeJobs() where progress[job.id] == nil {
            progress[job.id] = DownloadProgress(
                item: job.item,
                fraction: 0,
                bytesWritten: 0,
                bytesExpected: job.knownSize,
                seriesID: job.item.seriesID,
                userID: job.userID,
                serverHost: job.serverHost
            )
        }
        service.attachAndFlush()
    }

    func scoped(_ account: SavedSession?) -> [DownloadedItem] {
        guard let account else { return [] }
        let host = SnapshotCoding.host(from: account.serverURL)
        return records.filter { $0.userID == account.userID && $0.serverHost == host }
    }

    func libraryRows(for account: SavedSession?) -> [DownloadLibraryRow] {
        DownloadLibraryLayout.rows(from: scoped(account))
    }

    /// The live row for a show/movie, re-derived from the store so the downloads detail page
    /// updates as episodes are added or removed.
    func libraryRow(id: String, account: SavedSession?) -> DownloadLibraryRow? {
        libraryRows(for: account).first { $0.id == id }
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
        // Prefer the show poster for series rows and for downloaded episodes on Home — episode
        // stills made every card look like a random frame from the middle of the season.
        if item.kind == .series || item.kind == .episode {
            if let show = matches.compactMap(\.relativeShowArtworkPath).first,
               let url = existingFile(storedFile(show)) {
                return url
            }
            if item.kind == .series { return nil }
        }
        guard let path = matches.compactMap(\.relativeArtworkPath).first else { return nil }
        return existingFile(storedFile(path))
    }

    /// Remote poster to use when local show art is missing. Downloaded episodes fall back to the
    /// series Primary so Home / grids don't keep the episode still.
    func preferredRemotePoster(
        for item: MediaItem,
        account: SavedSession?,
        library: (any LibraryServing)?,
        fallback: URL?
    ) -> URL? {
        if item.kind == .episode,
           !DownloadCoverLogic.matchingRecords(for: item, in: scoped(account)).isEmpty,
           let seriesURL = library?.primaryURL(for: item.seriesShowcasePreview()) {
            return seriesURL
        }
        return fallback
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
        cancelJob(id)
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
            cancelJob(target.id)
            return
        }
        // No prep task, but a background transfer is in flight: toggling again stops it.
        if progress[target.id] != nil {
            progress[target.id] = nil
            cancelJob(target.id)
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
            try await prepareAndEnqueue(target: target, library: library, account: account)
        }
        tasks[target.id] = work
        ZelefinLog.info("Downloads", "Downloading \"\(target.name)\"")
        do {
            // Only the preparation (playback plan, asset, artwork) is awaited here; the media
            // transfer runs in the background session and finishes via the service callbacks, so
            // the progress row stays up after this returns.
            try await work.value
            tasks[target.id] = nil
        } catch {
            tasks[target.id] = nil
            progress[target.id] = nil
            if DownloadFailure.isCancellation(error) {
                cancelJob(target.id)
                ZelefinLog.info("Downloads", "Stopped downloading \"\(target.name)\"")
                return
            }
            ZelefinLog.error("Downloads", "Downloading \"\(target.name)\" failed: \(error.localizedDescription)")
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
        cancelJob(id)
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

    /// Resolve the stream, save the artwork, then hand the media transfer to the background session.
    /// Everything that needs the network or the signed-in library happens here while the app is
    /// active; the transfer itself survives backgrounding, and its completion is finalised by the
    /// service callbacks below (which need no network).
    private func prepareAndEnqueue(
        target: MediaItem,
        library: any LibraryServing,
        account: SavedSession
    ) async throws {
        let version = chosenVersion(target.id)
        let plan = try await library.playbackPlan(
            for: target,
            allowDirectPlay: true,
            maxBitrate: nil,
            startTime: nil,
            mediaSourceID: version
        )
        try Task.checkCancellation()
        let asset = try await library.prepareDownloadAsset(for: target, plan: plan, mediaSourceID: version)
        try Task.checkCancellation()
        let folder = itemDirectory(account: account, itemID: target.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(folder)

        let mediaURL = folder.appendingPathComponent("media.\(plan.container)")
        let headers = asset.headers
        let host = SnapshotCoding.host(from: account.serverURL)
        let knownSize = plan.byteSize ?? 0
        if knownSize > 0, var current = progress[target.id] {
            current.bytesExpected = knownSize
            progress[target.id] = current
        }

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
        try Task.checkCancellation()

        let job = DownloadJob(
            id: target.id,
            item: target,
            destinationRelativePath: relativePath(mediaURL),
            container: plan.container,
            videoCodec: plan.videoCodec,
            videoRange: plan.videoRange,
            audioFormat: plan.audioFormat,
            knownSize: knownSize,
            userID: account.userID,
            serverHost: host,
            artworkRelativePath: artworkPath,
            showArtworkRelativePath: showArtworkPath,
            serverDownloadID: asset.serverDownloadID
        )
        if usesBackgroundService {
            // Prefer the show poster for an episode's Live Activity; fall back to the episode still.
            let showFile = folder.appendingPathComponent("show.jpg")
            let episodeFile = folder.appendingPathComponent("poster.jpg")
            let posterURL: URL? = {
                if target.kind == .episode, fileManager.fileExists(atPath: showFile.path) { return showFile }
                if fileManager.fileExists(atPath: episodeFile.path) { return episodeFile }
                return nil
            }()
            DownloadActivityPresenter.start(
                id: target.id,
                // One Live Activity per show — a season download must not open 20+ activities.
                groupID: target.kind == .episode ? (target.seriesID ?? target.id) : target.id,
                title: Self.activityTitle(for: target),
                subtitle: Self.activitySubtitle(for: target),
                posterFileURL: posterURL,
                fraction: knownSize > 0 ? 0 : nil,
                statusLine: "Starting…"
            )
        }
        backgroundService?.start(
            job: job,
            from: asset.url,
            headers: headers,
            allowsCellular: !PlaybackPreferences.downloadWifiOnly
        )
    }

    /// Writes the catalog record once the background transfer lands its file. Runs with no network,
    /// so it also works when iOS relaunched the app purely to deliver the finished download.
    private func finalizeDownload(job: DownloadJob, file: DownloadedFile) {
        let record = DownloadedItem(
            item: job.item,
            relativeMediaPath: relativePath(file.url),
            relativeArtworkPath: job.artworkRelativePath,
            relativeShowArtworkPath: job.showArtworkRelativePath,
            container: file.url.pathExtension.isEmpty ? job.container : file.url.pathExtension,
            videoCodec: job.videoCodec,
            videoRange: job.videoRange,
            audioFormat: job.audioFormat,
            byteSize: file.byteSize > 0 ? file.byteSize : job.knownSize,
            userID: job.userID,
            serverHost: job.serverHost,
            downloadedAt: Date(),
            serverDownloadID: job.serverDownloadID
        )
        records.removeAll {
            $0.item.id == record.item.id && $0.userID == record.userID && $0.serverHost == record.serverHost
        }
        records.append(record)
        records = Self.deduplicated(records)
        persist()
        progress[job.id] = nil
        tasks[job.id] = nil
        DownloadActivityPresenter.finish(id: job.id, success: true, statusLine: "Downloaded")
        ZelefinLog.info(
            "Downloads",
            "Downloaded \"\(job.item.name)\": \(record.container), \(ByteCountFormatter.string(fromByteCount: record.byteSize, countStyle: .file))"
        )
        if let serverDownloadID = job.serverDownloadID, let library = libraryProvider() {
            Task { await library.finalizeServerDownload(id: serverDownloadID) }
        }
    }

    private func handleDownloadFailure(job: DownloadJob, error: Error) {
        progress[job.id] = nil
        tasks[job.id] = nil
        DownloadActivityPresenter.finish(id: job.id, success: false, statusLine: "Download failed")
        let folder = rootDirectory.appending(path: job.destinationRelativePath).deletingLastPathComponent()
        try? fileManager.removeItem(at: folder)
        ZelefinLog.error(
            "Downloads",
            "Downloading \"\(job.item.name)\" failed: \(error.localizedDescription)"
        )
    }

    private static func activityTitle(for item: MediaItem) -> String {
        if item.kind == .episode, let show = item.seriesName, !show.isEmpty { return show }
        return item.name
    }

    private static func activitySubtitle(for item: MediaItem) -> String {
        if item.kind == .episode, let season = item.seasonIndex, let episode = item.episodeIndex {
            return "S\(season) · E\(episode)"
        }
        return ""
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
        let existing = catalog.records.filter { record in
            fileManager.fileExists(atPath: storedFile(record.relativeMediaPath).path)
        }
        // Rebuilds mid-transfer used to leave the same episode listed more than once.
        return Self.deduplicated(existing)
    }

    /// One catalog row per (item, account, host) — keep the newest download.
    private static func deduplicated(_ records: [DownloadedItem]) -> [DownloadedItem] {
        var best: [String: DownloadedItem] = [:]
        for record in records {
            let key = "\(record.userID)|\(record.serverHost)|\(record.item.id)"
            if let current = best[key], current.downloadedAt >= record.downloadedAt {
                continue
            }
            best[key] = record
        }
        return Array(best.values).sorted { $0.downloadedAt > $1.downloadedAt }
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
