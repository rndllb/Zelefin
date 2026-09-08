import Foundation
#if os(iOS)
import SwiftUI
#endif

enum AppTab: String, CaseIterable, Identifiable, Hashable, Sendable {
    case home
    case movies
    case shows
    case collections
    case library

    static let orderStorageKey = "zelefin.tab-order"
    static let customizationStorageKey = "zelefin.tab-customization"
    static let hiddenDefaultsAppliedKey = "zelefin.tab-hidden-defaults-v1"
    static let defaultOrderRaw = "home,movies,shows,collections,library"
    static let hiddenByDefault: Set<AppTab> = [.collections]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .movies: "Movies"
        case .shows: "Shows"
        case .collections: "Collections"
        case .library: "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house.fill"
        case .movies: "film"
        case .shows: "tv"
        case .collections: "square.grid.2x2.fill"
        case .library: "rectangle.stack.fill"
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

#if os(iOS)
extension AppTab {
    static func defaultCustomization() -> TabViewCustomization {
        var customization = TabViewCustomization()
        applyHiddenDefaults(to: &customization)
        return customization
    }

    static func applyHiddenDefaults(to customization: inout TabViewCustomization) {
        for tab in hiddenByDefault where tab.canHide {
            customization[sidebarVisibility: tab.customizationID] = .hidden
        }
    }
}
#endif
