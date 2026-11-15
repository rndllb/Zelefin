import Foundation

struct DownloadedItem: Identifiable, Hashable, Sendable, Codable {
    var id: String { item.id }
    var item: MediaItem
    var relativeMediaPath: String
    var relativeArtworkPath: String?
    var relativeShowArtworkPath: String?
    var container: String
    var videoCodec: String?
    var videoRange: VideoRange
    var audioFormat: AudioFormat
    var byteSize: Int64
    var userID: String
    var serverHost: String
    var downloadedAt: Date
    /// For backends that track downloads server-side, the managed row id
    /// to delete when this download is removed. `nil` for direct downloads.
    var serverDownloadID: String? = nil
}

struct DownloadCatalog: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var records: [DownloadedItem]
}

struct DownloadProgress: Equatable, Identifiable, Sendable {
    var item: MediaItem?
    var fraction: Double
    var bytesWritten: Int64 = 0
    var bytesExpected: Int64 = 0
    var seriesID: String?
    var userID: String
    var serverHost: String

    var id: String { item?.id ?? "" }

    var isDeterminate: Bool { bytesExpected > 0 }

    var percentLabel: String? {
        DownloadByteCount.percentLabel(written: bytesWritten, expected: bytesExpected)
    }

    var sizeLabel: String {
        DownloadByteCount.sizeLabel(written: bytesWritten, expected: bytesExpected)
    }

    var bannerTitle: String {
        let subject: String?
        if let item, item.kind == .episode {
            if let episodeIndex = item.episodeIndex {
                subject = "Episode \(episodeIndex)"
            } else {
                subject = item.name
            }
        } else {
            subject = nil
        }
        if let subject {
            if let percentLabel {
                return "Downloading \(subject) · \(percentLabel)"
            }
            return "Downloading \(subject)"
        }
        if let percentLabel {
            return "Downloading \(percentLabel)"
        }
        return "Downloading"
    }
}

enum DownloadByteCount {
    static func resolvedExpected(httpExpected: Int64, knownSize: Int64) -> Int64 {
        if httpExpected > 0 { return httpExpected }
        if knownSize > 0 { return knownSize }
        return 0
    }

    static func fraction(written: Int64, expected: Int64) -> Double {
        guard expected > 0, written >= 0 else { return 0 }
        return min(1, Double(written) / Double(expected))
    }

    static func percentLabel(written: Int64, expected: Int64) -> String? {
        guard expected > 0 else { return nil }
        return "\(Int((fraction(written: written, expected: expected) * 100).rounded()))%"
    }

    static func sizeLabel(written: Int64, expected: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        if expected > 0 {
            return "\(formatter.string(fromByteCount: written)) of \(formatter.string(fromByteCount: expected))"
        }
        if written > 0 {
            return formatter.string(fromByteCount: written)
        }
        return "Starting…"
    }
}

enum DownloadCoverMark: Equatable, Sendable {
    case none
    case downloading(Double)
    case downloaded

    var accessibilityCaption: String? {
        switch self {
        case .none:
            nil
        case .downloading(let fraction):
            fraction > 0 ? "Downloading \(Int((fraction * 100).rounded())) percent" : "Downloading"
        case .downloaded:
            "Downloaded"
        }
    }
}

enum DownloadControlState: Equatable, Sendable {
    case unavailable
    case idle
    case downloading(Double)
    case downloaded
}

enum DownloadFailure {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if (error as? URLError)?.code == .cancelled { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

struct DownloadRemovalPrompt: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var message: String

    static func make(item: MediaItem) -> DownloadRemovalPrompt {
        DownloadRemovalPrompt(
            id: item.id,
            title: "Delete Download?",
            message: "Are you sure you want to delete the downloaded file for \(label(for: item))? You can download it again later."
        )
    }

    static func make(row: DownloadLibraryRow) -> DownloadRemovalPrompt {
        if row.kind == .series, row.episodeCount > 1 {
            return DownloadRemovalPrompt(
                id: row.id,
                title: "Delete Download?",
                message: "Are you sure you want to delete \(row.episodeCount) downloaded episodes of \(row.title.name)? You can download them again later."
            )
        }
        return make(item: row.records.first?.item ?? row.title)
    }

    private static func label(for item: MediaItem) -> String {
        if item.kind == .episode, let show = item.seriesName, !show.isEmpty {
            return "\(show) — \(item.name)"
        }
        return item.name
    }
}

enum DownloadControlCopy {
    static func title(for state: DownloadControlState) -> String {
        switch state {
        case .unavailable, .idle:
            "Download"
        case .downloading(let fraction):
            fraction > 0 ? "Pause Download · \(Int((fraction * 100).rounded()))%" : "Cancel Download"
        case .downloaded:
            "Remove Download"
        }
    }

    static func symbol(for state: DownloadControlState) -> String {
        switch state {
        case .unavailable, .idle:
            "arrow.down.to.line"
        case .downloading:
            "stop.circle"
        case .downloaded:
            "checkmark.circle.fill"
        }
    }
}

enum DownloadEligibility {
    static func playableItem(from item: MediaItem, episodes: [MediaItem] = []) -> MediaItem? {
        switch item.kind {
        case .movie, .episode:
            return item
        case .series:
            let hero = MediaItem.heroPlaybackItem(title: item, episodes: episodes)
            return hero.kind == .episode ? hero : nil
        case .season, .collection, .genre, .playlist, .liveTV, .book, .photo, .unknown:
            return nil
        }
    }

    static func canDownload(_ item: MediaItem, episodes: [MediaItem] = []) -> Bool {
        playableItem(from: item, episodes: episodes) != nil
    }
}

enum DownloadCoverLogic {
    static func matchingRecords(for item: MediaItem, in records: [DownloadedItem]) -> [DownloadedItem] {
        records.filter { record in
            covers(item, record: record)
        }
    }

    static func covers(_ item: MediaItem, record: DownloadedItem) -> Bool {
        if record.item.id == item.id {
            return true
        }
        guard item.kind == .series else { return false }
        return record.item.seriesID == item.id
    }

    static func mark(
        for item: MediaItem,
        records: [DownloadedItem],
        progress: [String: DownloadProgress]
    ) -> DownloadCoverMark {
        if let active = activeProgress(for: item, progress: progress) {
            return .downloading(active.fraction)
        }
        if matchingRecords(for: item, in: records).isEmpty {
            return .none
        }
        return .downloaded
    }

    static func control(
        for item: MediaItem,
        episodes: [MediaItem] = [],
        records: [DownloadedItem],
        progress: [String: DownloadProgress]
    ) -> DownloadControlState {
        guard let target = DownloadEligibility.playableItem(from: item, episodes: episodes) else {
            return .unavailable
        }
        if let active = progress[target.id] {
            return .downloading(active.fraction)
        }
        if records.contains(where: { $0.item.id == target.id }) {
            return .downloaded
        }
        return .idle
    }

    static func activeProgress(
        for item: MediaItem,
        progress: [String: DownloadProgress]
    ) -> DownloadProgress? {
        if let direct = progress[item.id] {
            return direct
        }
        guard item.kind == .series else { return nil }
        return progress.values.first { $0.seriesID == item.id }
    }
}

struct DownloadLibraryRow: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case movie
        case series
    }

    var id: String
    var kind: Kind
    var title: MediaItem
    var records: [DownloadedItem]

    var episodeCount: Int { records.count }
}

enum DownloadPlaybackSelection {
    static func record(for item: MediaItem, in records: [DownloadedItem]) -> DownloadedItem? {
        records.first { $0.item.id == item.id }
    }

    /// Show-level Play can start a downloaded episode when the hero title is not on disk.
    static func relatedRecord(for item: MediaItem, in records: [DownloadedItem]) -> DownloadedItem? {
        if let exact = record(for: item, in: records) {
            return exact
        }
        let seriesID: String?
        switch item.kind {
        case .series:
            seriesID = item.id
        case .episode:
            seriesID = item.seriesID
        case .movie, .season, .collection, .genre, .playlist, .liveTV, .book, .photo, .unknown:
            return nil
        }
        guard let seriesID, !seriesID.isEmpty else { return nil }
        let episodes = records.filter { record in
            record.item.seriesID == seriesID || record.item.id == seriesID
        }
        if let resumable = episodes.first(where: { !$0.item.isWatched && $0.item.playbackPosition > 5 }) {
            return resumable
        }
        if let upcoming = episodes.first(where: { !$0.item.isWatched }) {
            return upcoming
        }
        return episodes.max { $0.downloadedAt < $1.downloadedAt }
    }
}

/// A show's downloaded episodes bucketed by season, for the downloads-only detail page.
struct DownloadSeasonGroup: Identifiable, Equatable, Sendable {
    var id: String
    var seasonIndex: Int?
    var title: String
    var episodes: [DownloadedItem]

    var episodeCount: Int { episodes.count }
    var byteSize: Int64 { episodes.reduce(0) { $0 + $1.byteSize } }
}

enum DownloadSeasonLayout {
    static func title(for seasonIndex: Int?) -> String {
        guard let seasonIndex else { return "Episodes" }
        if seasonIndex == 0 { return "Specials" }
        return "Season \(seasonIndex)"
    }

    /// Real seasons sort ascending, Specials (season 0) after them, an unknown season last.
    private static func sortKey(_ seasonIndex: Int?) -> Int {
        guard let seasonIndex else { return .max }
        if seasonIndex == 0 { return .max - 1 }
        return seasonIndex
    }

    static func groups(from records: [DownloadedItem]) -> [DownloadSeasonGroup] {
        var order: [Int?] = []
        var buckets: [Int?: [DownloadedItem]] = [:]
        for record in records {
            let key = record.item.seasonIndex
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(record)
        }
        return order
            .sorted { sortKey($0) < sortKey($1) }
            .compactMap { key -> DownloadSeasonGroup? in
                guard let episodes = buckets[key], !episodes.isEmpty else { return nil }
                let sorted = episodes.sorted { lhs, rhs in
                    let left = lhs.item.episodeIndex ?? .max
                    let right = rhs.item.episodeIndex ?? .max
                    if left == right {
                        return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
                    }
                    return left < right
                }
                return DownloadSeasonGroup(
                    id: key.map(String.init) ?? "unknown",
                    seasonIndex: key,
                    title: title(for: key),
                    episodes: sorted
                )
            }
    }
}

enum DownloadLibraryLayout {
    static func rows(from records: [DownloadedItem]) -> [DownloadLibraryRow] {
        let sorted = records.sorted { lhs, rhs in
            if lhs.downloadedAt == rhs.downloadedAt {
                return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
            }
            return lhs.downloadedAt > rhs.downloadedAt
        }

        var movies: [DownloadLibraryRow] = []
        var seriesOrder: [String] = []
        var seriesBuckets: [String: [DownloadedItem]] = [:]

        for record in sorted {
            if let seriesID = seriesGroupingID(for: record.item) {
                if seriesBuckets[seriesID] == nil {
                    seriesOrder.append(seriesID)
                }
                seriesBuckets[seriesID, default: []].append(record)
                continue
            }
            movies.append(
                DownloadLibraryRow(
                    id: record.item.id,
                    kind: .movie,
                    title: record.item,
                    records: [record]
                )
            )
        }

        let shows = seriesOrder.compactMap { seriesID -> DownloadLibraryRow? in
            guard let episodes = seriesBuckets[seriesID], let first = episodes.first else {
                return nil
            }
            return DownloadLibraryRow(
                id: seriesID,
                kind: .series,
                title: first.item.seriesShowcasePreview(),
                records: episodes
            )
        }

        return (movies + shows).sorted { lhs, rhs in
            let left = lhs.records.map(\.downloadedAt).max() ?? .distantPast
            let right = rhs.records.map(\.downloadedAt).max() ?? .distantPast
            if left == right {
                return lhs.title.name.localizedCaseInsensitiveCompare(rhs.title.name) == .orderedAscending
            }
            return left > right
        }
    }

    /// Episodes that belong to a show collapse under one series poster on the Downloaded page.
    static func seriesGroupingID(for item: MediaItem) -> String? {
        guard item.kind == .episode, let seriesID = item.seriesID, !seriesID.isEmpty else { return nil }
        return seriesID
    }

    /// Poster to show for an in-flight transfer: the show for an episode, otherwise the title itself.
    static func posterItem(for transfer: DownloadProgress) -> MediaItem? {
        guard let item = transfer.item else { return nil }
        if seriesGroupingID(for: item) != nil {
            return item.seriesShowcasePreview()
        }
        return item
    }
}

/// One cell on the Downloaded grid: either an in-flight transfer or a finished row.
enum DownloadLibraryEntry: Identifiable, Equatable {
    case active(DownloadProgress, title: MediaItem)
    case stored(DownloadLibraryRow)

    var id: String {
        switch self {
        case .active(let progress, _): "active-\(progress.id)"
        case .stored(let row): "row-\(row.id)"
        }
    }

    var title: MediaItem {
        switch self {
        case .active(_, let title): title
        case .stored(let row): row.title
        }
    }

    /// Active episode downloads collapse under one series poster; finished rows for that show are
    /// hidden while any of its episodes are still transferring (same as Android).
    static func grid(active: [DownloadProgress], rows: [DownloadLibraryRow]) -> [DownloadLibraryEntry] {
        var seenShowIDs = Set<String>()
        var entries: [DownloadLibraryEntry] = []
        for transfer in active {
            guard let poster = DownloadLibraryLayout.posterItem(for: transfer) else { continue }
            if seenShowIDs.contains(poster.id) { continue }
            seenShowIDs.insert(poster.id)
            entries.append(.active(transfer, title: poster))
        }
        for row in rows {
            let blocked = active.contains { transfer in
                guard let item = transfer.item else { return false }
                if item.id == row.id { return true }
                if let seriesID = DownloadLibraryLayout.seriesGroupingID(for: item) {
                    return seriesID == row.id || item.seriesShowcasePreview().id == row.id
                }
                return false
            }
            if blocked { continue }
            entries.append(.stored(row))
        }
        return entries
    }
}
