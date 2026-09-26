import Foundation
import Get
import JellyfinAPI

/// A pending Quick Connect request waiting for approval on another device.
struct QuickConnectHandshake: Equatable, Sendable {
    /// The user-facing code to enter on another device.
    let code: String
    /// The secret used to poll and complete sign-in.
    let secret: String

    /// The code grouped for display, e.g. `"148  293"`.
    var groupedCode: String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 6 else { return trimmed }
        let midpoint = trimmed.index(trimmed.startIndex, offsetBy: 3)
        return "\(trimmed[..<midpoint])  \(trimmed[midpoint...])"
    }
}

/// Talks to Jellyfin's Quick Connect endpoints.
enum QuickConnectClient {
    /// Returns whether Quick Connect is turned on for `client`'s server.
    static func isEnabled(on client: JellyfinClient) async throws -> Bool {
        do {
            let data = try await client.send(Paths.getQuickConnectEnabled).value
            return enabledFlag(from: data) ?? true
        } catch let APIError.unacceptableStatusCode(status) where status == 401 || status == 403 {
            return false
        } catch let APIError.unacceptableStatusCode(status) where status == 404 {
            return true
        }
    }

    /// Starts a Quick Connect request.
    static func start(on client: JellyfinClient) async throws -> QuickConnectHandshake {
        do {
            let result = try await client.send(Paths.initiateQuickConnect).value
            guard let code = result.code, !code.isEmpty, let secret = result.secret, !secret.isEmpty else {
                throw ZelefinError.quickConnectUnavailable
            }
            return QuickConnectHandshake(code: code, secret: secret)
        } catch let APIError.unacceptableStatusCode(status) where status == 401 || status == 403 {
            throw ZelefinError.quickConnectDisabled
        }
    }

    /// Waits until `handshake` is authorized; returns the secret for sign-in.
    static func waitUntilAuthorized(
        _ handshake: QuickConnectHandshake,
        on client: JellyfinClient,
        pollInterval: Duration = .seconds(2),
        maximumPolls: Int = 150
    ) async throws -> String {
        for _ in 0 ..< maximumPolls {
            try Task.checkCancellation()
            if let secret = try await authorizedSecret(for: handshake, on: client) {
                return secret
            }
            try await Task.sleep(for: pollInterval)
        }
        throw ZelefinError.quickConnectExpired
    }

    /// Returns the boolean encoded in a Quick Connect enabled response body.
    static func enabledFlag(from data: Data) -> Bool? {
        if let flag = try? JSONDecoder().decode(Bool.self, from: data) {
            return flag
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch text {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }

    private static func authorizedSecret(
        for handshake: QuickConnectHandshake,
        on client: JellyfinClient
    ) async throws -> String? {
        do {
            let result = try await client.send(Paths.getQuickConnectState(secret: handshake.secret)).value
            guard result.isAuthenticated == true else { return nil }
            let secret = result.secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return secret.isEmpty ? handshake.secret : secret
        } catch let APIError.unacceptableStatusCode(status) where status == 404 || status == 401 {
            throw ZelefinError.quickConnectExpired
        }
    }
}
