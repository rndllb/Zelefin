import Foundation

struct ActivityLogItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String?
    let date: Date?
    let type: String?

    var subtitle: String {
        let parts = [type, detail].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }
        return parts.joined(separator: " · ")
    }
}

struct ServerBackup: Identifiable, Hashable, Sendable {
    let id: String
    let path: String
    let dateCreated: Date?
    let serverVersion: String?

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum RemoteArtworkKind: String, CaseIterable, Identifiable, Sendable {
    case poster
    case thumbnail
    case logo
    case backdrop

    var id: String { rawValue }

    var title: String {
        switch self {
        case .poster: "Poster"
        case .thumbnail: "Thumbnail"
        case .logo: "Logo"
        case .backdrop: "Backdrop"
        }
    }

    var systemImage: String {
        switch self {
        case .poster: "rectangle.portrait.fill"
        case .thumbnail: "rectangle.fill"
        case .logo: "signature"
        case .backdrop: "pano.fill"
        }
    }

    var emptyTitle: String {
        "No \(title.lowercased())s"
    }

    var jellyfinTypeName: String {
        switch self {
        case .poster: "Primary"
        case .thumbnail: "Thumb"
        case .logo: "Logo"
        case .backdrop: "Backdrop"
        }
    }

    var previewAspectRatio: Double {
        switch self {
        case .poster: 2 / 3
        case .thumbnail, .backdrop: 16 / 9
        case .logo: 8 / 3
        }
    }

    var gridMinimum: Double {
        self == .poster ? 110 : 160
    }
}

struct RemoteImageChoice: Identifiable, Hashable, Sendable {
    let id: String
    let imageURL: URL
    let thumbnailURL: URL?
    let provider: String
    let typeName: String
    let width: Int?
    let height: Int?

    var previewURL: URL { thumbnailURL ?? imageURL }

    var sizeLabel: String? {
        guard let width, let height else { return nil }
        return "\(width)×\(height)"
    }
}

struct SyncPlayGroupInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let participants: [String]
    let stateLabel: String

    var subtitle: String {
        let people = participants.isEmpty ? "No one else yet" : participants.joined(separator: ", ")
        return "\(stateLabel) · \(people)"
    }
}

struct ServerBranding: Equatable, Sendable {
    var loginDisclaimer: String
    var customCSS: String
    var splashscreenEnabled: Bool
}

struct PlaylistEntry: Identifiable, Hashable, Sendable {
    let id: String
    let entryID: String?
    let item: MediaItem
}

enum DisplayPreferencesSync {
    static let preferenceID = "zelefin"
    static let tabOrderKey = "tabOrder"
    static let mergeContinueKey = "mergeContinueNextUp"
    static let homeRowOrderKey = "homeRowOrder"
    static let homeRowHiddenKey = "homeRowHidden"
    static let featuredHeroContentKey = "featuredHeroContent"
    static let libraryOrderKey = "libraryOrder"
    static let libraryHiddenKey = "libraryHidden"
    static let libraryPageHiddenKey = "libraryPageHidden"

    static func apply(_ prefs: [String: String]) {
        if let order = prefs[tabOrderKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !order.isEmpty {
            UserDefaults.standard.set(order, forKey: AppTab.orderStorageKey)
        }
        if let merge = prefs[mergeContinueKey] {
            let enabled = merge == "true" || merge == "1"
            UserDefaults.standard.set(enabled, forKey: HomeLayoutPreferences.mergeContinueAndNextUpKey)
        }
        if let order = prefs[homeRowOrderKey]?.trimmingCharacters(in: .whitespacesAndNewlines), !order.isEmpty {
            UserDefaults.standard.set(HomeRowKind.raw(from: HomeRowKind.ordered(from: order)), forKey: HomeRowKind.orderStorageKey)
        }
        if let hidden = prefs[homeRowHiddenKey] {
            UserDefaults.standard.set(
                HomeRowKind.hiddenRaw(from: HomeRowKind.hidden(from: hidden)),
                forKey: HomeRowKind.hiddenStorageKey
            )
        }
        if let hero = prefs[featuredHeroContentKey],
           let content = FeaturedHeroContent(rawValue: hero) {
            UserDefaults.standard.set(content.rawValue, forKey: FeaturedHeroContent.storageKey)
        }
        if let order = prefs[libraryOrderKey]?.trimmingCharacters(in: .whitespacesAndNewlines) {
            UserDefaults.standard.set(order, forKey: LibraryLayoutPreferences.orderKey)
        }
        if let hidden = prefs[libraryHiddenKey] {
            UserDefaults.standard.set(
                LibraryLayoutPreferences.hiddenRaw(from: LibraryLayoutPreferences.hiddenIDs(from: hidden)),
                forKey: LibraryLayoutPreferences.hiddenKey
            )
        }
        if let pageHidden = prefs[libraryPageHiddenKey] {
            UserDefaults.standard.set(
                LibraryLayoutPreferences.pageHiddenRaw(from: LibraryLayoutPreferences.hiddenBlocks(from: pageHidden)),
                forKey: LibraryLayoutPreferences.pageHiddenKey
            )
        }
    }

    static func customPrefs() -> [String: String] {
        [
            tabOrderKey: UserDefaults.standard.string(forKey: AppTab.orderStorageKey) ?? AppTab.defaultOrderRaw,
            mergeContinueKey: HomeLayoutPreferences.mergeContinueAndNextUp ? "true" : "false",
            homeRowOrderKey: UserDefaults.standard.string(forKey: HomeRowKind.orderStorageKey) ?? HomeRowKind.defaultOrderRaw,
            homeRowHiddenKey: UserDefaults.standard.string(forKey: HomeRowKind.hiddenStorageKey) ?? "",
            featuredHeroContentKey: FeaturedHeroContent.current.rawValue,
            libraryOrderKey: UserDefaults.standard.string(forKey: LibraryLayoutPreferences.orderKey) ?? "",
            libraryHiddenKey: UserDefaults.standard.string(forKey: LibraryLayoutPreferences.hiddenKey) ?? "",
            libraryPageHiddenKey: UserDefaults.standard.string(forKey: LibraryLayoutPreferences.pageHiddenKey) ?? ""
        ]
    }
}
