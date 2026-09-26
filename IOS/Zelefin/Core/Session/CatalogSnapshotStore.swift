import Foundation

/// On-disk copy of a library catalog (Movies, Shows, or Collections) so opening the tab paints
/// the full grid instantly on a cold launch instead of waiting on a large `/Items` page.
struct CatalogSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 2

    var version: Int
    var userID: String
    var serverHost: String
    var libraryKind: LibraryKind
    var savedAt: Date
    var items: [MediaItem]
}

protocol CatalogSnapshotStoring: Sendable {
    func load(userID: String, serverURL: URL, kind: LibraryKind) -> CatalogSnapshot?
    func save(_ snapshot: CatalogSnapshot)
    func removeAll(userID: String, serverURL: URL)
}

struct FileCatalogSnapshotStore: CatalogSnapshotStoring {
    private let directory: URL

    init(directory: URL? = nil) {
        self.directory = directory ?? SnapshotCoding.cachesDirectory(named: "CatalogSnapshots")
    }

    func load(userID: String, serverURL: URL, kind: LibraryKind) -> CatalogSnapshot? {
        let fileManager = FileManager.default
        let url = fileURL(userID: userID, serverURLHost: SnapshotCoding.host(from: serverURL), kind: kind)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let snapshot = try SnapshotCoding.decoder.decode(CatalogSnapshot.self, from: data)
            guard snapshot.version == CatalogSnapshot.currentVersion,
                  snapshot.userID == userID,
                  snapshot.libraryKind == kind
            else {
                try? fileManager.removeItem(at: url)
                return nil
            }
            return snapshot
        } catch {
            try? fileManager.removeItem(at: url)
            return nil
        }
    }

    func save(_ snapshot: CatalogSnapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try SnapshotCoding.encoder.encode(snapshot)
            let url = fileURL(userID: snapshot.userID, serverURLHost: snapshot.serverHost, kind: snapshot.libraryKind)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }
    }

    func removeAll(userID: String, serverURL: URL) {
        let host = SnapshotCoding.host(from: serverURL)
        for kind in LibraryKind.allCases {
            let url = fileURL(userID: userID, serverURLHost: host, kind: kind)
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func fileURL(userID: String, serverURLHost: String, kind: LibraryKind) -> URL {
        directory.appendingPathComponent(
            SnapshotCoding.fileName(joining: [serverURLHost, userID, kind.rawValue]),
            isDirectory: false
        )
    }
}
