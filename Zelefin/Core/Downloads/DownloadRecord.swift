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

enum DownloadEligibility {
    static func playableItem(from item: MediaItem, episodes: [MediaItem] = []) -> MediaItem? {
        switch item.kind {
        case .movie, .episode:
            return item
        case .series:
            let hero = MediaItem.heroPlaybackItem(title: item, episodes: episodes)
            return hero.kind == .episode ? hero : nil
        case .season, .collection, .genre, .unknown:
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
        case .movie, .season, .collection, .genre, .unknown:
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
            if record.item.kind == .episode, let seriesID = record.item.seriesID, !seriesID.isEmpty {
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
}
