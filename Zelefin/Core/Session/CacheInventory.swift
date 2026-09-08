import Foundation

enum ArtworkImageKind: String, CaseIterable, Sendable, Identifiable {
    case poster
    case backdrop
    case logo
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poster: "Posters"
        case .backdrop: "Backdrops"
        case .logo: "Logos"
        case .other: "Other"
        }
    }

    var filePrefix: String { "\(rawValue)-" }

    static func classify(_ url: URL) -> ArtworkImageKind {
        classify(path: url.path)
    }

    static func classify(path: String) -> ArtworkImageKind {
        if path.contains("/Users/") {
            return .other
        }
        if path.contains("/Images/Backdrop") {
            return .backdrop
        }
        if path.contains("/Images/Logo") {
            return .logo
        }
        if path.contains("/Images/Primary")
            || path.contains("/Images/Thumb")
            || path.contains("/Images/Banner")
        {
            return .poster
        }
        return .other
    }

    static func classify(fileName: String) -> ArtworkImageKind {
        let name = fileName.hasSuffix(".missing")
            ? String(fileName.dropLast(8))
            : fileName
        for kind in ArtworkImageKind.allCases where kind != .other {
            if name.hasPrefix(kind.filePrefix) {
                return kind
            }
        }
        return .other
    }
}

enum MetadataCacheFolder: String, CaseIterable, Sendable, Identifiable {
    case home = "HomeSnapshots"
    case catalog = "CatalogSnapshots"
    case itemDetail = "ItemDetailSnapshots"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .catalog: "Catalogs"
        case .itemDetail: "Title details"
        }
    }

    func directory(fileManager: FileManager = .default) -> URL {
        SnapshotCoding.cachesDirectory(named: rawValue, fileManager: fileManager)
    }
}

struct CacheBucket: Equatable, Sendable {
    var bytes: Int64
    var fileCount: Int

    static let empty = CacheBucket(bytes: 0, fileCount: 0)

    var isEmpty: Bool { bytes == 0 && fileCount == 0 }
}

struct ArtworkCacheUsage: Equatable, Sendable {
    var posters = CacheBucket.empty
    var backdrops = CacheBucket.empty
    var logos = CacheBucket.empty
    var other = CacheBucket.empty

    var total: CacheBucket {
        CacheBucket(
            bytes: posters.bytes + backdrops.bytes + logos.bytes + other.bytes,
            fileCount: posters.fileCount + backdrops.fileCount + logos.fileCount + other.fileCount
        )
    }

    func bucket(for kind: ArtworkImageKind) -> CacheBucket {
        switch kind {
        case .poster: posters
        case .backdrop: backdrops
        case .logo: logos
        case .other: other
        }
    }

    mutating func add(_ kind: ArtworkImageKind, bytes: Int64) {
        switch kind {
        case .poster: posters = posters.adding(bytes: bytes)
        case .backdrop: backdrops = backdrops.adding(bytes: bytes)
        case .logo: logos = logos.adding(bytes: bytes)
        case .other: other = other.adding(bytes: bytes)
        }
    }
}

struct MetadataCacheUsage: Equatable, Sendable {
    var home = CacheBucket.empty
    var catalog = CacheBucket.empty
    var itemDetail = CacheBucket.empty

    var total: CacheBucket {
        CacheBucket(
            bytes: home.bytes + catalog.bytes + itemDetail.bytes,
            fileCount: home.fileCount + catalog.fileCount + itemDetail.fileCount
        )
    }

    func bucket(for folder: MetadataCacheFolder) -> CacheBucket {
        switch folder {
        case .home: home
        case .catalog: catalog
        case .itemDetail: itemDetail
        }
    }
}

enum CacheInventory {
    static func artworkUsage(at directory: URL, fileManager: FileManager = .default) -> ArtworkCacheUsage {
        var usage = ArtworkCacheUsage()
        for file in files(in: directory, fileManager: fileManager) {
            guard !file.lastPathComponent.hasSuffix(".missing") else { continue }
            let bytes = byteCount(of: file, fileManager: fileManager)
            usage.add(ArtworkImageKind.classify(fileName: file.lastPathComponent), bytes: bytes)
        }
        return usage
    }

    static func metadataUsage(fileManager: FileManager = .default) -> MetadataCacheUsage {
        MetadataCacheUsage(
            home: folderUsage(MetadataCacheFolder.home.directory(fileManager: fileManager), fileManager: fileManager),
            catalog: folderUsage(MetadataCacheFolder.catalog.directory(fileManager: fileManager), fileManager: fileManager),
            itemDetail: folderUsage(MetadataCacheFolder.itemDetail.directory(fileManager: fileManager), fileManager: fileManager)
        )
    }

    static func folderUsage(_ directory: URL, fileManager: FileManager = .default) -> CacheBucket {
        files(in: directory, fileManager: fileManager).reduce(into: .empty) { usage, file in
            usage = usage.adding(bytes: byteCount(of: file, fileManager: fileManager))
        }
    }

    static func removeArtwork(_ kind: ArtworkImageKind?, from directory: URL, fileManager: FileManager = .default) {
        for file in files(in: directory, fileManager: fileManager) {
            let classified = ArtworkImageKind.classify(fileName: file.lastPathComponent)
            if let kind {
                guard classified == kind else { continue }
            }
            try? fileManager.removeItem(at: file)
        }
    }

    static func removeMetadata(_ folder: MetadataCacheFolder?, fileManager: FileManager = .default) {
        let folders = folder.map { [$0] } ?? Array(MetadataCacheFolder.allCases)
        for item in folders {
            removeContents(of: item.directory(fileManager: fileManager), fileManager: fileManager)
        }
    }

    static func removeContents(of directory: URL, fileManager: FileManager = .default) {
        for file in files(in: directory, fileManager: fileManager) {
            try? fileManager.removeItem(at: file)
        }
    }

    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: max(0, bytes))
    }

    private static func files(in directory: URL, fileManager: FileManager) -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        return (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func byteCount(of file: URL, fileManager: FileManager) -> Int64 {
        let values = try? file.resourceValues(forKeys: [.fileSizeKey])
        if let size = values?.fileSize {
            return Int64(size)
        }
        if let attributes = try? fileManager.attributesOfItem(atPath: file.path),
           let size = attributes[.size] as? NSNumber
        {
            return size.int64Value
        }
        return 0
    }
}

private extension CacheBucket {
    func adding(bytes: Int64) -> CacheBucket {
        CacheBucket(bytes: self.bytes + bytes, fileCount: fileCount + 1)
    }
}
