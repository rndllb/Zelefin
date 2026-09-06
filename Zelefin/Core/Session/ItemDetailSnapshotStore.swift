import Foundation

/// On-disk copy of a title’s detail page so a later visit can paint immediately.
struct ItemDetailSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let maxCachedTitles = 48

    var version: Int
    var userID: String
    var serverHost: String
    var itemID: String
    var savedAt: Date
    var item: MediaItem
    var trailers: [TitleTrailer]
    var related: [MediaItem]
    var credits: [CreditPerson]
    var collections: [ItemCollectionMembership]
    var seasons: [MediaItem]
    var episodes: [MediaItem]
    var selectedSeasonID: String?
}

protocol ItemDetailSnapshotStoring {
    func load(userID: String, serverURL: URL, itemID: String) throws -> ItemDetailSnapshot?
    func save(_ snapshot: ItemDetailSnapshot) throws
}

struct FileItemDetailSnapshotStore: ItemDetailSnapshotStoring {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            self.directory = SnapshotCoding.cachesDirectory(named: "ItemDetailSnapshots", fileManager: fileManager)
        }
    }

    func load(userID: String, serverURL: URL, itemID: String) throws -> ItemDetailSnapshot? {
        let url = fileURL(userID: userID, serverHost: SnapshotCoding.host(from: serverURL), itemID: itemID)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try SnapshotCoding.decoder.decode(ItemDetailSnapshot.self, from: data)
            guard snapshot.version == ItemDetailSnapshot.currentVersion else {
                try removeFile(at: url)
                return nil
            }
            guard snapshot.userID == userID, snapshot.itemID == itemID else { return nil }
            return snapshot
        } catch {
            try? removeFile(at: url)
            return nil
        }
    }

    func save(_ snapshot: ItemDetailSnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try SnapshotCoding.encoder.encode(snapshot)
        let url = fileURL(userID: snapshot.userID, serverHost: snapshot.serverHost, itemID: snapshot.itemID)
        try data.write(to: url, options: .atomic)
        try pruneIfNeeded()
    }

    private func pruneIfNeeded() throws {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        guard files.count > ItemDetailSnapshot.maxCachedTitles else { return }

        let ranked = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left < right
        }
        let extra = files.count - ItemDetailSnapshot.maxCachedTitles
        for url in ranked.prefix(extra) {
            try? removeFile(at: url)
        }
    }

    private func fileURL(userID: String, serverHost: String, itemID: String) -> URL {
        directory.appendingPathComponent(
            SnapshotCoding.fileName(joining: [serverHost, userID, itemID]),
            isDirectory: false
        )
    }

    private func removeFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }
}
