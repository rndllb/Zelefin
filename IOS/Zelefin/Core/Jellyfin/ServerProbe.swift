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

    /// Silo's Jellyfin-compatible API calls itself "Jellyfin Server", but its branding always
    /// carries Silo's fixed login disclaimer.
    func isSiloServer(at url: URL) async -> Bool {
        guard let disclaimer = await branding(at: url)?.loginDisclaimer else { return false }
        return Self.isSiloDisclaimer(disclaimer)
    }

    static func isSiloDisclaimer(_ disclaimer: String) -> Bool {
        disclaimer.range(of: "silo", options: .caseInsensitive) != nil
    }

    /// Checks whether `url` answers as a Jellyfin server.
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
