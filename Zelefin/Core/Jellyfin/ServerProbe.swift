import Foundation
import JellyfinAPI

struct ServerProbe: Sendable {
    func normalizedURL(from raw: String) throws -> URL {
        try ServerURL.normalize(raw)
    }

    func publicInfo(at url: URL) async throws -> PublicSystemInfo {
        let client = JellyfinNetworking.client(url: url)
        return try await client.send(Paths.getPublicSystemInfo).value
    }

    /// Checks whether `url` answers as a Jellyfin server.
    ///
    /// Sends the public system-info request, including any configured access-gateway headers.
    func checkReachability(at url: URL) async -> ServerReachability {
        do {
            let info = try await publicInfo(at: url)
            let trimmedName = info.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return .reachable(
                serverName: trimmedName.isEmpty ? "Jellyfin" : trimmedName,
                version: info.version ?? "?"
            )
        } catch {
            return ServerReachability(error: error)
        }
    }
}
