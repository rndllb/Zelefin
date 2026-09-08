import Foundation

#if os(iOS)
import CoreLocation
import NetworkExtension
#endif

enum WiFiSSID {
    static func current() async -> String? {
        #if os(iOS)
        await HotspotSSID.fetch()
        #else
        nil
        #endif
    }

    static func requestAccess() async {
        #if os(iOS)
        await LocationSSIDAccess.shared.request()
        #endif
    }
}

#if os(iOS)
@MainActor
final class LocationSSIDAccess: NSObject, CLLocationManagerDelegate {
    static let shared = LocationSSIDAccess()
    private let manager = CLLocationManager()
    private var pending: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func request() async {
        switch manager.authorizationStatus {
        case .notDetermined:
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pending = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            pending?.resume()
            pending = nil
        }
    }
}

enum HotspotSSID {
    static func fetch() async -> String? {
        await withCheckedContinuation { continuation in
            NEHotspotNetwork.fetchCurrent { network in
                let name = network?.ssid.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                continuation.resume(returning: name.isEmpty ? nil : name)
            }
        }
    }
}
#endif
