import Foundation
import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case shows
    case liveTV
    case collections
    case library
    case favorites

    static let orderStorageKey = "zelefin.tab-order"
    static let showsTitlesStorageKey = "zelefin.tab-bar-shows-titles"
    static let dockLibrariesStorageKey = "zelefin.dock-library-ids"
    static let customizationStorageKey = "zelefin.tab-customization"
    static let hiddenDefaultsAppliedKey = "zelefin.tab-hidden-defaults-v1"
    static let favoritesHiddenDefaultKey = "zelefin.tab-hidden-defaults-favorites"
    static let liveTVHiddenDefaultKey = "zelefin.tab-hidden-defaults-livetv"
    static let defaultOrderRaw = "home,movies,shows,liveTV,collections,library,favorites"
    static let hiddenByDefault: Set<AppTab> = [.liveTV, .collections, .favorites]

    static let startTabStorageKey = "zelefin.start-tab"
    /// The always-available content pages a user can pick as the app's launch destination.
    static let startPageChoices: [AppTab] = [.home, .movies, .shows, .library]

    /// The stored start page, or `.home` when the value is missing or not a valid start page.
    static func startTab(from raw: String) -> AppTab {
        guard let tab = AppTab(rawValue: raw), startPageChoices.contains(tab) else { return .home }
        return tab
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shows: "Shows"
        case .liveTV: "Live TV"
        case .collections: "Collections"
        case .library: "Library"
        case .favorites: "Favorites"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .movies: "film"
        case .shows: "tv"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .collections: "square.grid.2x2.fill"
        case .library: "rectangle.stack.fill"
        case .favorites: "heart.fill"
        }
    }

    /// Iconsax asset for tabs that have one. The rest stay on `systemImage`.
    var iconAsset: String? {
        switch self {
        case .home: "IconsaxHome"
        case .movies: "IconsaxMovies"
        case .shows: "IconsaxShows"
        case .liveTV: "IconsaxLiveTV"
        case .collections: "IconsaxCollections"
        case .library: "IconsaxLibrary"
        default: nil
        }
    }

    var customizationID: String { "app.zelefin.tab.\(rawValue)" }

    var canHide: Bool {
        self != .home
    }

    static func ordered(from raw: String) -> [AppTab] {
        var seen = Set<AppTab>()
        var order: [AppTab] = []
        for token in raw.split(separator: ",") {
            guard let tab = AppTab(rawValue: String(token)), seen.insert(tab).inserted else { continue }
            order.append(tab)
        }
        for tab in allCases where seen.insert(tab).inserted {
            order.append(tab)
        }
        return order
    }

    static func raw(from order: [AppTab]) -> String {
        var seen = Set<AppTab>()
        return order.compactMap { tab in
            seen.insert(tab).inserted ? tab.rawValue : nil
        }.joined(separator: ",")
    }
}

extension AppTab {
    static func defaultCustomization() -> TabViewCustomization {
        var customization = TabViewCustomization()
        applyHiddenDefaults(to: &customization)
        return customization
    }

    static func applyHiddenDefaults(to customization: inout TabViewCustomization) {
        hide(hiddenByDefault, in: &customization)
    }

    static func hide(_ tabs: Set<AppTab>, in customization: inout TabViewCustomization) {
        for tab in tabs where tab.canHide {
            customization[sidebarVisibility: tab.customizationID] = .hidden
        }
    }
}

/// The dock, Mac sidebar, and Interface settings icon for a library. YouTube and recordings libraries get
/// their own; the rest share Library's. A library with "Anime" in its name can use one of the anime icons instead.
enum LibraryIcon {
    static let youTube = "IconsaxYouTube"
    static let recording = "IconsaxRecording"
    static let library = "IconsaxLibrary"
    static let anime = "AnimeLibrary"
    static let choicesStorageKey = "zelefin.library-icons"

    struct Choice: Identifiable, Hashable {
        let asset: String
        let title: String
        var id: String { asset }
    }

    /// PlainIcon's Anime characters pack (CC BY 4.0).
    static let animeChoices: [Choice] = [
        Choice(asset: "AnimeBoySmiling", title: "Boy Smiling"),
        Choice(asset: "AnimeBoyWithBigEyes", title: "Boy with Big Eyes"),
        Choice(asset: "AnimeBoyWithHeadphones", title: "Boy with Headphones"),
        Choice(asset: "AnimeBoyWithHood", title: "Boy with Hood"),
        Choice(asset: "AnimeBoyWithShirt", title: "Boy with Shirt"),
        Choice(asset: "AnimeBoyWithShirtAndBigEyes", title: "Boy with Shirt and Big Eyes"),
        Choice(asset: "AnimeBoyWithShortTrousers", title: "Boy with Short Trousers"),
        Choice(asset: "AnimeBoyWithSummerClothes", title: "Boy with Summer Clothes"),
        Choice(asset: "AnimeBoyWithTShirt", title: "Boy with T-Shirt"),
        Choice(asset: "AnimeBoyWithTShirt2", title: "Boy with T-Shirt 2"),
        Choice(asset: "AnimeBoyWithTie", title: "Boy with Tie"),
        Choice(asset: "AnimeBoyWithTie2", title: "Boy with Tie 2"),
        Choice(asset: "AnimeBoyWithWildHair", title: "Boy with Wild Hair"),
        Choice(asset: "AnimeCharacter", title: "Character"),
        Choice(asset: "AnimeCharacterWithHairUp", title: "Character with Hair Up"),
        Choice(asset: "AnimeFeminineCharacterSmiling", title: "Character Smiling"),
        Choice(asset: "AnimeFeminineCharacterWithSkirt", title: "Character with Skirt"),
        Choice(asset: "AnimeGirlWithLongHair", title: "Girl with Long Hair"),
        Choice(asset: "AnimeGirlWithLongHair2", title: "Girl with Long Hair 2"),
        Choice(asset: "AnimeGirlWithPonytail", title: "Girl with Ponytail"),
        Choice(asset: "AnimeGirlWithSkirt", title: "Girl with Skirt"),
        Choice(asset: "AnimeGirlWithTwoPonyTails", title: "Girl with Two Ponytails"),
    ]

    static func canChoose(_ library: MediaLibrary) -> Bool {
        library.name.localizedCaseInsensitiveContains("anime")
    }

    /// The picked icon, or nil when the library keeps its default.
    static func chosen(for library: MediaLibrary, raw: String) -> String? {
        guard canChoose(library), let asset = choices(from: raw)[library.id],
              animeChoices.contains(where: { $0.asset == asset }) else { return nil }
        return asset
    }

    static func asset(for library: MediaLibrary, raw: String) -> String {
        chosen(for: library, raw: raw) ?? defaultAsset(for: library)
    }

    static func defaultAsset(for library: MediaLibrary) -> String {
        if canChoose(library) { return anime }
        if MediaLibrary.nameLooksLikeRecordings(library.name) { return recording }
        return switch library.libraryKind {
        case .youTube: youTube
        case .movies: AppTab.movies.iconAsset ?? Self.library
        case .shows: AppTab.shows.iconAsset ?? Self.library
        case .liveTV: AppTab.liveTV.iconAsset ?? Self.library
        default: Self.library
        }
    }

    /// `libraryID=asset` pairs separated by commas.
    static func choices(from raw: String) -> [String: String] {
        var choices: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                choices[parts[0]] = parts[1]
            }
        }
        return choices
    }

    static func raw(from choices: [String: String]) -> String {
        choices.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
    }
}

extension UIUserInterfaceIdiom {
    /// iPad and the Mac share the large-screen layout; the Mac build runs as `.mac`
    /// ("Optimize Interface for Mac").
    var isLargeScreen: Bool { self == .pad || self == .mac }
}

enum PhoneDockLimit {
    /// Five slots in one bar. Search always takes the last one.
    static let capacity = 5

    @MainActor
    static var applies: Bool {
        !UIDevice.current.userInterfaceIdiom.isLargeScreen
    }

    @MainActor
    static func canEnableAnother(enabledTabs: Int, enabledLibraries: Int) -> Bool {
        guard applies else { return true }
        return enabledTabs + enabledLibraries + 1 < capacity
    }

    @MainActor
    static func content<Tab>(tabs: [Tab], libraries: [MediaLibrary]) -> (tabs: [Tab], libraries: [MediaLibrary]) {
        guard applies else { return (tabs, libraries) }
        var room = capacity - 1
        var keptTabs: [Tab] = []
        for tab in tabs {
            guard room > 0 else { break }
            keptTabs.append(tab)
            room -= 1
        }
        var keptLibraries: [MediaLibrary] = []
        for library in libraries {
            guard room > 0 else { break }
            keptLibraries.append(library)
            room -= 1
        }
        return (keptTabs, keptLibraries)
    }
}

enum DockLibraryPreferences {
    /// A custom library such as Anime can sit in the dock. Movies, Shows, Live TV, and Collections already have their own tabs.
    static func canPin(_ library: MediaLibrary) -> Bool {
        switch library.libraryKind {
        case .other, .youTube, .homeVideos, .photos:
            true
        default:
            false
        }
    }

    static func ids(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init).filter { !$0.isEmpty })
    }

    static func raw(from ids: Set<String>) -> String {
        ids.sorted().joined(separator: ",")
    }
}

enum TabBarIconMetrics {
    /// The tab bar lays out from the image size, so a SwiftUI frame on the label does not change it.
    static let side: CGFloat = 28
    @MainActor private static var cache: [String: UIImage] = [:]

    @MainActor
    static func image(named name: String) -> UIImage? {
        if let cached = cache[name] { return cached }
        guard let source = UIImage(named: name) else { return nil }
        let canvas = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: canvas).image { _ in
            source.withTintColor(.black, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: .zero, size: canvas))
        }
        let overflow = (side - 24) / 2
        let image = rendered
            .withAlignmentRectInsets(UIEdgeInsets(top: overflow, left: overflow, bottom: overflow, right: overflow))
            .withRenderingMode(.alwaysTemplate)
        cache[name] = image
        return image
    }

    /// The selected-state asset. Icons drawn without a filled version, such as the anime ones, keep their outline.
    @MainActor
    static func selectedName(for base: String) -> String {
        let filled = "\(base)Filled"
        return UIImage(named: filled) == nil ? base : filled
    }
}

struct TabBarIcon: View {
    var assetName: String?
    var systemImage: String
    var isSelected = false
    var side: CGFloat = TabBarIconMetrics.side

    var body: some View {
        Group {
            if let assetName {
                // Template so the tab's tint (accent) applies to every icon, Search included,
                // whether selected or not — not a flat white Search icon when unselected.
                Image(isSelected ? TabBarIconMetrics.selectedName(for: assetName) : assetName)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: systemImage)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }
}
