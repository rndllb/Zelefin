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

    func branding(at url: URL) async -> ServerBranding? {
        let client = JellyfinNetworking.client(url: url)
        guard let dto = try? await client.send(Paths.getBrandingOptions).value else { return nil }
        return ServerBranding(
            loginDisclaimer: dto.loginDisclaimer ?? "",
            customCSS: dto.customCss ?? "",
            splashscreenEnabled: dto.isSplashscreenEnabled ?? false
        )
    }

    /// Checks whether `url` answers as a Silo or Jellyfin server.
    ///
    /// Silo `/api/v1/health` is tried first so a host that also exposes Jellyfin
    /// compatibility on another port is still recognized as Silo.
    func checkReachability(at url: URL) async -> ServerReachability {
        if let health = try? await siloHealth(at: url), health.isReady {
            return .reachable(
                serverName: health.displayName,
                version: health.version ?? "Silo"
            )
        }
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

    func siloHealth(at url: URL) async throws -> SiloHealth {
        let client = SiloAPIClient(baseURL: url)
        return try await client.health()
    }

    func detectBackend(at url: URL) async -> MediaBackend? {
        if let health = try? await siloHealth(at: url), health.isReady {
            return .silo
        }
        if (try? await publicInfo(at: url)) != nil {
            return .jellyfin
        }
        return nil
    }
}
