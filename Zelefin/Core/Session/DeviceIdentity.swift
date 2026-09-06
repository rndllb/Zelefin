import Foundation

enum DeviceIdentity {
    static let clientName = "Zelefin"
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"

    static var deviceName: String {
        #if os(tvOS)
        "Apple TV"
        #else
        "iPhone"
        #endif
    }

    static func deviceID() -> String {
        let key = "zelefin.device-id"
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }

        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: key)
        return created
    }
}
