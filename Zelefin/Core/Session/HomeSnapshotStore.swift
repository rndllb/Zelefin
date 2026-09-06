import Foundation

/// On-disk copy of Home and the user’s library list so a cold launch can paint immediately.
struct HomeSnapshot: Codable, Equatable, Sendable {
    static let currentVersion = 5

    var version: Int
    var userID: String
    var serverHost: String
    var savedAt: Date
    var home: HomeLayout
    var libraries: [MediaLibrary]
}

protocol HomeSnapshotStoring {
    func load(userID: String, serverURL: URL) throws -> HomeSnapshot?
    func save(_ snapshot: HomeSnapshot) throws
    func remove(userID: String, serverURL: URL)
}

struct FileHomeSnapshotStore: HomeSnapshotStoring {
    private let fileManager: FileManager
    private let directory: URL

    init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        if let directory {
            self.directory = directory
        } else {
            self.directory = Self.defaultDirectory(fileManager: fileManager)
        }
    }

    func load(userID: String, serverURL: URL) throws -> HomeSnapshot? {
        let url = fileURL(userID: userID, serverURL: serverURL)
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            let snapshot = try Self.decoder.decode(HomeSnapshot.self, from: data)
            guard snapshot.version == HomeSnapshot.currentVersion else {
                try removeFile(at: url)
                return nil
            }
            guard snapshot.userID == userID else { return nil }
            return snapshot
        } catch {
            try? removeFile(at: url)
            return nil
        }
    }

    func save(_ snapshot: HomeSnapshot) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(snapshot)
        let url = fileURL(userID: snapshot.userID, serverURLHost: snapshot.serverHost)
        try data.write(to: url, options: .atomic)
    }

    func remove(userID: String, serverURL: URL) {
        let url = fileURL(userID: userID, serverURL: serverURL)
        try? removeFile(at: url)
    }

    private func fileURL(userID: String, serverURL: URL) -> URL {
        fileURL(userID: userID, serverURLHost: Self.host(from: serverURL))
    }

    private func fileURL(userID: String, serverURLHost: String) -> URL {
        let fileName = "\(serverURLHost)-\(userID).json"
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    private func removeFile(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        let base = caches.first ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Zelefin", isDirectory: true)
            .appendingPathComponent("HomeSnapshots", isDirectory: true)
    }

    private static func host(from serverURL: URL) -> String {
        serverURL.host ?? serverURL.absoluteString
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension HomeSnapshot {
    static func host(from serverURL: URL) -> String {
        serverURL.host ?? serverURL.absoluteString
    }
}
