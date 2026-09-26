import Foundation

/// Media server this install is signed into. Existing keychain blobs without a
/// value decode as Jellyfin so upgrades keep working.
enum MediaBackend: String, Codable, Sendable, Equatable {
    case jellyfin
    case silo

    var usesJellyfinSessions: Bool { self == .jellyfin }
    var usesHouseholdProfiles: Bool { self == .silo }
}
