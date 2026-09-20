import Foundation
import JellyfinAPI

enum ZelefinPluginCatalog {
    static let repositoryName = "Zelefin"
    static let repositoryURL = "https://raw.githubusercontent.com/rndllb/Zelefin-Plugin/main/manifest.json"
    static let packageName = "Zelefin"
    static let assemblyGuid = "b18e5910-21dd-49fe-a150-bb21ec3755e8"

    static func insertingCatalog(into existing: [RepositoryInfo]) -> [RepositoryInfo] {
        if existing.contains(where: { urlsMatch($0.url, repositoryURL) }) {
            return existing
        }
        return existing + [
            RepositoryInfo(isEnabled: true, name: repositoryName, url: repositoryURL)
        ]
    }

    static func urlsMatch(_ lhs: String?, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }

    private static func normalize(_ raw: String?) -> String {
        (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}

struct ZelefinPluginInstaller: Sendable {
    let client: JellyfinClient

    func install() async throws {
        try await ensureRepository()
        _ = try await client.send(
            Paths.installPackage(
                name: ZelefinPluginCatalog.packageName,
                parameters: .init(
                    assemblyGuid: ZelefinPluginCatalog.assemblyGuid,
                    repositoryURL: ZelefinPluginCatalog.repositoryURL
                )
            )
        )
    }

    func restartServer() async throws {
        _ = try await client.send(Paths.restartApplication)
    }

    private func ensureRepository() async throws {
        let current = try await client.send(Paths.getRepositories).value
        let next = ZelefinPluginCatalog.insertingCatalog(into: current)
        if next.count == current.count { return }
        _ = try await client.send(Paths.setRepositories(next))
    }
}
