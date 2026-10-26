import Foundation
import Get

/// The outcome of asking a URL whether it is a Jellyfin server.
enum ServerReachability: Equatable, Sendable {
    /// Public system info answered with server metadata.
    case reachable(serverName: String, version: String)
    /// The host answered, but public info required authentication.
    case reachableRequiringAuthentication
    /// The host answered, but an access gateway is blocking Jellyfin.
    case blockedByAccessGateway
    /// The request failed before Jellyfin could be identified.
    case failed(description: String)

    /// A Boolean value that's true when the host looks like a reachable Jellyfin server.
    var isReachable: Bool {
        switch self {
        case .reachable, .reachableRequiringAuthentication:
            true
        case .blockedByAccessGateway, .failed:
            false
        }
    }

    /// Copy suitable for the login screen.
    var message: String {
        switch self {
        case .reachable(let serverName, let version):
            "Reached \(serverName) (\(version))"
        case .reachableRequiringAuthentication:
            "Reached the server, but it requires auth at the public-info endpoint."
        case .blockedByAccessGateway:
            ZelefinError.accessGateway.errorDescription
                ?? "This URL is behind an access gateway. Add tokens under Advanced."
        case .failed(let description):
            description
        }
    }

    /// Creates a result that represents `error` from a public-info request.
    init(error: Error) {
        if let zelefinError = error as? ZelefinError {
            switch zelefinError {
            case .accessGateway:
                self = .blockedByAccessGateway
            default:
                self = .failed(description: zelefinError.localizedDescription)
            }
            return
        }

        if case APIError.unacceptableStatusCode(let statusCode) = error {
            switch statusCode {
            case 401, 403:
                self = .reachableRequiringAuthentication
            default:
                self = .failed(
                    description: "Server reached, but it doesn't look like a Jellyfin server (HTTP \(statusCode))."
                )
            }
            return
        }

        if error is DecodingError {
            self = .failed(description: "Server reached, but it doesn't look like a Jellyfin server.")
            return
        }

        if let urlError = Self.urlError(from: error) {
            self = .failed(description: Self.explanation(for: urlError))
            return
        }

        self = .failed(description: error.localizedDescription)
    }

    /// Returns a short explanation of `error` suitable for a login screen.
    static func explanation(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            switch error.networkUnavailableReason {
            case .cellular:
                "Cellular data is off for Zelefin. Turn it on in Settings > Zelefin > Cellular Data."
            case .constrained:
                "Low Data Mode is blocking Zelefin. Turn it off for this network, or use Wi-Fi."
            case .expensive:
                "This network is blocked for Zelefin. Try Wi-Fi."
            default:
                "No internet connection."
            }
        case .timedOut:
            "The request timed out."
        case .cannotFindHost:
            "Couldn’t find that host. Check the URL."
        case .cannotConnectToHost:
            "Couldn’t connect to the host."
        case .networkConnectionLost:
            "The network connection was lost."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid, .clientCertificateRejected:
            "TLS/certificate error. Check HTTPS and the certificate."
        case .badURL, .unsupportedURL:
            "Invalid server URL."
        case .appTransportSecurityRequiresSecureConnection:
            "App Transport Security blocked this HTTP URL. Use HTTPS."
        default:
            error.localizedDescription
        }
    }

    /// Sign-in copy for `error`, with network failures explained.
    static func signInMessage(for error: Error) -> String {
        if !(error is ZelefinError), let urlError = urlError(from: error) {
            return explanation(for: urlError)
        }
        return error.localizedDescription
    }

    private static func urlError(from error: Error) -> URLError? {
        if let urlError = error as? URLError {
            return urlError
        }

        var current: Error? = error
        while let nsError = current as NSError? {
            if let urlError = current as? URLError {
                return urlError
            }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        }
        return nil
    }
}
