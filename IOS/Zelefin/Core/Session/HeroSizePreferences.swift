import CoreGraphics
import Foundation

/// How tall the Featured and title-page backdrop run. Compact leaves more of a landscape image on screen.
enum HeroSizePreferences: String, CaseIterable, Identifiable, Sendable {
    case compact
    case tall

    static let storageKey = "zelefin.hero-size"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: "Compact"
        case .tall: "Tall"
        }
    }

    static var current: HeroSizePreferences {
        HeroSizePreferences(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .compact
    }

    /// Fraction of the available height used by the hero, with a floor so small phones still fill.
    var heightFactor: CGFloat {
        switch self {
        case .compact: 0.58
        case .tall: 0.82
        }
    }

    var minimumHeight: CGFloat {
        switch self {
        case .compact: 480
        case .tall: 680
        }
    }

    func height(for size: CGSize) -> CGFloat {
        max(minimumHeight, size.height * heightFactor)
    }
}
