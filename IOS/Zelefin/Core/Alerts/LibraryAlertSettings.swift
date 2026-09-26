import Foundation

enum LibraryAlertSettings {
    static let enabledKey = "zelefin.alerts.enabled"

    static var isEnabled: Bool {
        get { bool(for: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    private static func bool(for key: String, default fallback: Bool = true) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
}
