import Foundation
import JellyfinAPI

enum JellyfinNetworking {
    private static let gatewayDelegate = JellyfinGatewayDelegate()

    static let imageSession: URLSession = {
        URLSession(configuration: sessionConfiguration(cacheImages: true))
    }()

    static func sessionConfiguration(cacheImages: Bool = false) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = .shared
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = cacheImages ? 60 : 300
        if cacheImages {
            configuration.requestCachePolicy = .returnCacheDataElseLoad
            configuration.urlCache = URLCache(
                memoryCapacity: 80 * 1_024 * 1_024,
                diskCapacity: 200 * 1_024 * 1_024
            )
        } else {
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
        }
        return configuration
    }

    static func client(
        url: URL,
        accessToken: String? = nil,
        deviceID: String = DeviceIdentity.deviceID()
    ) -> JellyfinClient {
        JellyfinClient(
            configuration: .init(
                url: url,
                accessToken: accessToken,
                client: DeviceIdentity.clientName,
                deviceName: DeviceIdentity.deviceName,
                deviceID: deviceID,
                version: DeviceIdentity.version
            ),
            delegate: gatewayDelegate,
            sessionConfiguration: sessionConfiguration()
        )
    }

    static func data(from url: URL) async throws -> (Data, URLResponse) {
        try await data(for: URLRequest(url: url))
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        AccessGateway.apply(&request)
        return try await imageSession.data(for: request)
    }
}
