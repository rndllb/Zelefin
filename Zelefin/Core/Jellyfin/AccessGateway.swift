import Foundation
import Get

enum AccessGateway {
    private static let clientIDAccount = "access-gateway-client-id"
    private static let clientSecretAccount = "access-gateway-client-secret"
    private static let secrets = SecretStore()

    static var clientID: String {
        get { secrets.load(account: clientIDAccount) ?? "" }
        set { save(newValue, account: clientIDAccount) }
    }

    static var clientSecret: String {
        get { secrets.load(account: clientSecretAccount) ?? "" }
        set { save(newValue, account: clientSecretAccount) }
    }

    static var isConfigured: Bool {
        !trimmedID.isEmpty && !trimmedSecret.isEmpty
    }

    static var httpHeaders: [String: String] {
        headers(clientID: trimmedID, clientSecret: trimmedSecret)
    }

    static func headers(clientID: String, clientSecret: String) -> [String: String] {
        let id = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !secret.isEmpty else { return [:] }
        return [
            "CF-Access-Client-Id": id,
            "CF-Access-Client-Secret": secret,
            "P-Access-Token-Id": id,
            "P-Access-Token": secret
        ]
    }

    static func apply(_ request: inout URLRequest) {
        for (name, value) in httpHeaders {
            request.setValue(value, forHTTPHeaderField: name)
        }
    }

    static func isChallenge(response: HTTPURLResponse, data: Data) -> Bool {
        let status = response.statusCode
        let location = response.value(forHTTPHeaderField: "Location") ?? ""
        let contentType = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        let body = String(data: data.prefix(1_200), encoding: .utf8) ?? ""
        let looksHTML = contentType.localizedCaseInsensitiveContains("text/html")
            || body.localizedCaseInsensitiveContains("<html")
            || body.localizedCaseInsensitiveContains("<!doctype html")
        let locationLooksAccess = location.localizedCaseInsensitiveContains("cloudflareaccess.com")
            || location.localizedCaseInsensitiveContains("cdn-cgi/access")
        let bodyLooksAccess = body.localizedCaseInsensitiveContains("cloudflareaccess")
            || body.localizedCaseInsensitiveContains("cf-access")
            || body.localizedCaseInsensitiveContains("pangolin")
        let cfRayBlocked = response.value(forHTTPHeaderField: "CF-Ray") != nil && looksHTML

        if locationLooksAccess || bodyLooksAccess || cfRayBlocked {
            return true
        }
        if looksHTML, [301, 302, 303, 307, 308, 401, 403].contains(status) {
            return true
        }
        return looksHTML && (200 ..< 300).contains(status)
    }

    private static var trimmedID: String {
        clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static var trimmedSecret: String {
        clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func save(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            secrets.delete(account: account)
        } else {
            secrets.save(trimmed, account: account)
        }
    }
}

final class JellyfinGatewayDelegate: APIClientDelegate, @unchecked Sendable {
    func client(_ client: APIClient, willSendRequest request: inout URLRequest) async throws {
        AccessGateway.apply(&request)
    }

    func client(_ client: APIClient, validateResponse response: HTTPURLResponse, data: Data, task: URLSessionTask) throws {
        if AccessGateway.isChallenge(response: response, data: data) {
            throw ZelefinError.accessGateway
        }
        guard (200 ..< 300).contains(response.statusCode) else {
            throw APIError.unacceptableStatusCode(response.statusCode)
        }
    }

    func client(_ client: APIClient, shouldRetry task: URLSessionTask, error: Error, attempts: Int) async throws -> Bool {
        guard attempts < 2 else { return false }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    func client(_ client: APIClient, makeURLForRequest request: Request<some Any>) throws -> URL? {
        guard let path = request.url else { return nil }
        guard let base = client.configuration.baseURL else { return nil }

        let resolved: URL
        if path.scheme != nil {
            resolved = ServerURL.rewriteIfNeeded(path, publicBase: base)
        } else if let joined = ServerURL.resolve(base: base, path: path.absoluteString) {
            resolved = joined
        } else {
            return nil
        }

        // Get skips its own query encoding whenever this returns a URL.
        return ServerURL.appending(request.query ?? [], to: resolved)
    }
}
