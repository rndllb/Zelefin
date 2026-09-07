import Foundation

enum SnapshotCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func host(from serverURL: URL) -> String {
        serverURL.host ?? serverURL.absoluteString
    }

    static func fileName(joining parts: [String]) -> String {
        parts.joined(separator: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            + ".json"
    }

    static func cachesDirectory(
        named folder: String,
        fileManager: FileManager = .default
    ) -> URL {
        directory(.cachesDirectory, named: folder, fileManager: fileManager)
    }

    static func applicationSupportDirectory(
        named folder: String,
        fileManager: FileManager = .default
    ) -> URL {
        directory(.applicationSupportDirectory, named: folder, fileManager: fileManager)
    }

    private static func directory(
        _ search: FileManager.SearchPathDirectory,
        named folder: String,
        fileManager: FileManager
    ) -> URL {
        let urls = fileManager.urls(for: search, in: .userDomainMask)
        let base = urls.first ?? fileManager.temporaryDirectory
        return base
            .appendingPathComponent("Zelefin", isDirectory: true)
            .appendingPathComponent(folder, isDirectory: true)
    }
}
