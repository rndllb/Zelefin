import Foundation

enum ZelefinError: LocalizedError, Sendable {
    case invalidServerURL
    case missingItemID
    case missingUser
    case missingStreamURL
    case byteRangeUnsupported
    case playbackEngineUnavailable
    case emptyPlaybackSources
    case downloadFailed
    case bitrateTestFailed
    case offlineFileUnreadable
    case accessGateway
    case seerrUnauthorized
    case quickConnectDisabled
    case quickConnectExpired
    case quickConnectUnavailable
    case siloNativeAddress
    case server(String)
    case keychain(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            "Enter a server address that starts with http:// or https://"
        case .missingItemID:
            "This title is missing an identifier."
        case .missingUser:
            "Sign in again to continue."
        case .missingStreamURL:
            "Zelefin could not build a playback URL."
        case .byteRangeUnsupported:
            "The server did not honor HTTP byte ranges, so Direct Play cannot start."
        case .playbackEngineUnavailable:
            "Zelefin could not start the Direct Play engine."
        case .emptyPlaybackSources:
            "The server did not return a playable stream."
        case .downloadFailed:
            "Zelefin could not download this title. Check the connection and try again."
        case .bitrateTestFailed:
            "Zelefin could not download the demo file from this server. Check the connection and try again."
        case .offlineFileUnreadable:
            "Zelefin could not open the downloaded file."
        case .accessGateway:
            "This server is behind an access gateway such as Cloudflare Zero Trust or Pangolin. Add the gateway client ID and token, then try again."
        case .seerrUnauthorized:
            "\(PluginSettings.requestService.name) session expired. Sign in again."
        case .quickConnectDisabled:
            "Quick Connect is turned off on this server."
        case .quickConnectExpired:
            "This Quick Connect code expired. Try again."
        case .quickConnectUnavailable:
            "Jellyfin did not return a Quick Connect code."
        case .siloNativeAddress:
            "This is Silo's main address. Sign in with your Silo username and password, or use Quick Connect on Silo's Jellyfin-compatible address."
        case let .server(message), let .keychain(message):
            message
        }
    }
}
