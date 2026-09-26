import Foundation

/// Whether the Silo server permits managed offline downloads, and which quality
/// presets it offers. Contract: `GET /api/v1/downloads/capability`.
struct SiloDownloadCapability: Decodable, Sendable {
    var enabled: Bool
    var downloadAllowed: Bool
    var qualityPresets: [String]

    /// Downloads are usable only when the feature is on and this user is allowed.
    var isUsable: Bool { enabled && downloadAllowed }

    /// The quality to request when the user hasn't chosen one. Prefers the
    /// original file, falling back to whatever the server offers first.
    var preferredQuality: String {
        qualityPresets.first(where: { $0.caseInsensitiveCompare("original") == .orderedSame })
            ?? qualityPresets.first
            ?? "original"
    }

    enum CodingKeys: String, CodingKey {
        case enabled
        case downloadAllowed = "download_allowed"
        case qualityPresets = "quality_presets"
        case formats
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        downloadAllowed = (try? container.decodeIfPresent(Bool.self, forKey: .downloadAllowed)) ?? false
        qualityPresets = (try? container.decodeIfPresent([String].self, forKey: .qualityPresets))
            ?? (try? container.decodeIfPresent([String].self, forKey: .formats))
            ?? ["original"]
    }
}

/// Registers a managed download. Contract: `POST /api/v1/downloads`.
struct SiloCreateDownloadRequest: Encodable, Sendable {
    let contentID: String
    let fileID: Int?
    let quality: String

    enum CodingKeys: String, CodingKey {
        case contentID = "content_id"
        case fileID = "file_id"
        case quality
    }
}

/// One managed-download row. The server owns `status`: `preparing` → `ready`
/// (downloadable at `/api/v1/downloads/{id}/file`) and `revoked` if dropped.
struct SiloDownloadRow: Decodable, Sendable {
    var id: String
    var contentID: String?
    var fileSize: Int?
    var status: String
    var quality: String?

    var isReady: Bool { status.caseInsensitiveCompare("ready") == .orderedSame }
    var isRevoked: Bool { status.caseInsensitiveCompare("revoked") == .orderedSame }

    enum CodingKeys: String, CodingKey {
        case id, status, quality
        case contentID = "content_id"
        case fileSize = "file_size"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        contentID = container.decodeNonEmptyString(.contentID)
        fileSize = container.decodeFlexibleInt(.fileSize)
        status = container.decodeNonEmptyString(.status) ?? "preparing"
        quality = container.decodeNonEmptyString(.quality)
    }
}

struct SiloDownloadsResponse: Decodable, Sendable {
    var downloads: [SiloDownloadRow]?
    var items: [SiloDownloadRow]?

    var entries: [SiloDownloadRow] { downloads ?? items ?? [] }
}
