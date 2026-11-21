import Foundation
import SwiftUI

/// Per-app UI language override. Empty / `system` follows the device.
enum AppLanguage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case system
    case english = "en"
    case chineseSimplified = "zh-Hans"
    case hindi = "hi"
    case spanish = "es"
    case arabic = "ar"
    case french = "fr"
    case portugueseBrazil = "pt-BR"
    case russian = "ru"
    case german = "de"
    case japanese = "ja"
    case indonesian = "id"

    static let storageKey = "zelefin.appLanguage"

    var id: String { rawValue }

    /// BCP-47 tag used for `Locale` / catalogs. Nil means follow the system.
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        default: rawValue
        }
    }

    /// Name shown in the language’s own script (for the picker).
    var nativeName: String {
        switch self {
        case .system: AppLanguage.string("settings.language.system", default: "System")
        case .english: "English"
        case .chineseSimplified: "中文（简体）"
        case .hindi: "हिन्दी"
        case .spanish: "Español"
        case .arabic: "العربية"
        case .french: "Français"
        case .portugueseBrazil: "Português (Brasil)"
        case .russian: "Русский"
        case .german: "Deutsch"
        case .japanese: "日本語"
        case .indonesian: "Bahasa Indonesia"
        }
    }

    /// English label for accessibility / debugging.
    var englishName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .chineseSimplified: "Chinese (Simplified)"
        case .hindi: "Hindi"
        case .spanish: "Spanish"
        case .arabic: "Arabic"
        case .french: "French"
        case .portugueseBrazil: "Portuguese (Brazil)"
        case .russian: "Russian"
        case .german: "German"
        case .japanese: "Japanese"
        case .indonesian: "Indonesian"
        }
    }

    static func stored(from raw: String) -> AppLanguage {
        AppLanguage(rawValue: raw) ?? .system
    }

    /// Locale used when resolving String Catalogs.
    static var catalogLocale: Locale {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue
        return stored(from: raw).locale
    }

    var locale: Locale {
        if let localeIdentifier {
            return Locale(identifier: localeIdentifier)
        }
        return .autoupdatingCurrent
    }

    var isRightToLeft: Bool {
        switch self {
        case .arabic: true
        case .system:
            Locale.autoupdatingCurrent.language.characterDirection == .rightToLeft
        default: false
        }
    }

    /// Resolves a String Catalog key for the current Interface language.
    /// `String(localized:locale:)` only formats interpolations; the language comes from the bundle.
    /// Load the matching `.lproj` so a change applies without relaunching.
    static func string(
        _ key: StaticString,
        default defaultValue: String.LocalizationValue
    ) -> String {
        let keyString = String(cString: key.utf8Start)
        let fallback = String(localized: defaultValue)
        let resolved = localizationBundle.localizedString(forKey: keyString, value: fallback, table: "Localizable")
        if resolved.isEmpty || resolved == keyString {
            return fallback
        }
        return resolved
    }

    /// Looks up a template (`%@`, `%1$@`) and fills it for the current Interface language.
    static func format(
        _ key: StaticString,
        default defaultValue: String.LocalizationValue,
        _ args: CVarArg...
    ) -> String {
        String(format: string(key, default: defaultValue), arguments: args)
    }

    private static var localizationBundle: Bundle {
        let language = stored(from: UserDefaults.standard.string(forKey: storageKey) ?? AppLanguage.system.rawValue)
        guard let code = language.localeIdentifier else { return .main }
        let candidates = [code, code.replacingOccurrences(of: "-", with: "_")]
        for name in candidates {
            if let path = Bundle.main.path(forResource: name, ofType: "lproj"),
               let bundle = Bundle(path: path) {
                return bundle
            }
        }
        return .main
    }
}

private struct AppLanguageEnvironmentKey: EnvironmentKey {
    static let defaultValue: AppLanguage = .system
}

extension EnvironmentValues {
    var appLanguage: AppLanguage {
        get { self[AppLanguageEnvironmentKey.self] }
        set { self[AppLanguageEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Applies the user’s Interface → App Language choice without rebuilding the whole tree
    /// (an `.id` on the root was popping Settings and crashing the picker).
    func appLanguage(_ language: AppLanguage) -> some View {
        environment(\.locale, language.locale)
            .environment(\.appLanguage, language)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
