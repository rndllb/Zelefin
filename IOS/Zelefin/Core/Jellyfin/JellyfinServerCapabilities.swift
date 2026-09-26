import Foundation

/// What this server generation can do, parsed from public system info.
///
/// Jellyfin 12 dropped the `10.` prefix (`10.11.x` → `12.x`). 12-only routes
/// fall back to older `GetItems` paths when the version is 10.x or unknown.
struct JellyfinServerCapabilities: Sendable, Equatable {
    enum Generation: Sendable, Equatable {
        case unknown
        case jellyfin10
        case jellyfin12Plus
    }

    let generation: Generation
    let rawVersion: String?

    init(version: String?) {
        rawVersion = version
        generation = Self.generation(from: version)
    }

    /// `true`/`false` when the version is known; `nil` means probe the endpoint.
    var itemCollectionsAvailability: Bool? {
        switch generation {
        case .jellyfin12Plus: true
        case .jellyfin10: false
        case .unknown: nil
        }
    }

    /// Jellyfin 12 marks PlaybackInfo query params obsolete; send the DTO body only.
    var prefersPlaybackInfoBody: Bool {
        generation == .jellyfin12Plus
    }

    static func generation(from raw: String?) -> Generation {
        guard let major = majorVersion(from: raw) else { return .unknown }
        if major >= 12 { return .jellyfin12Plus }
        if major >= 10 { return .jellyfin10 }
        return .unknown
    }

    static func majorVersion(from raw: String?) -> Int? {
        guard let raw else { return nil }
        let token = raw.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let token else { return nil }
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}
