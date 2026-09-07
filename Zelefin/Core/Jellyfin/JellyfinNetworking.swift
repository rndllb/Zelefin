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
            configuration.httpMaximumConnectionsPerHost = 8
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

    static func data(
        from url: URL,
        ignoreCache: Bool = false,
        serviceType: URLRequest.NetworkServiceType = .default,
        timeout: TimeInterval? = nil
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        if ignoreCache {
            request.cachePolicy = .reloadIgnoringLocalCacheData
        }
        request.networkServiceType = serviceType
        if let timeout {
            request.timeoutInterval = timeout
        }
        return try await data(for: request)
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        AccessGateway.apply(&request)
        return try await imageSession.data(for: request)
    }

    static func apiData(for request: URLRequest) async throws -> (Data, URLResponse) {
        var request = request
        AccessGateway.apply(&request)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try await apiSession.data(for: request)
    }

    private static let apiSession: URLSession = {
        URLSession(configuration: sessionConfiguration(cacheImages: false))
    }()
}

/// Jellyfin's image controller always wraps the request body in `FromBase64Transform`.
/// Raw JPEG bytes are rejected; the dashboard sends base64 with an image Content-Type.
enum JellyfinImagePayload {
    static func requestBody(imageJPEG jpeg: Data) -> Data {
        jpeg.base64EncodedData()
    }
}
