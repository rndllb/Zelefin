import Foundation
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case shows
    case liveTV
    case collections
    case library
    case favorites

    static let orderStorageKey = "zelefin.tab-order"
    static let customizationStorageKey = "zelefin.tab-customization"
    static let hiddenDefaultsAppliedKey = "zelefin.tab-hidden-defaults-v1"
    static let favoritesHiddenDefaultKey = "zelefin.tab-hidden-defaults-favorites"
    static let liveTVHiddenDefaultKey = "zelefin.tab-hidden-defaults-livetv"
    static let defaultOrderRaw = "home,movies,shows,liveTV,collections,library,favorites"
    static let hiddenByDefault: Set<AppTab> = [.liveTV, .collections, .favorites]

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
