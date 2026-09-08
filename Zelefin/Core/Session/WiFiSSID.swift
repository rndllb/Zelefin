import Foundation

import CoreLocation
import NetworkExtension

enum WiFiSSID {
    static func current() async -> String? {
        await HotspotSSID.fetch()
    }

    static func requestAccess() async {
        await LocationSSIDAccess.shared.request()
    }
}

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
