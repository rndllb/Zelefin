import JellyfinAPI
import SwiftUI

/// Live snapshot of the signed-in server: name, product, version, OS, and addresses.
struct ServerInfoView: View {
    @Environment(SessionStore.self) private var session
    @State private var snapshot = ServerInfoSnapshot.empty
    @State private var isLoading = false
    @State private var loadError: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Server name", value: display(snapshot.serverName))
                LabeledContent("Product", value: display(snapshot.product))
                LabeledContent("Version", value: display(snapshot.version))
                LabeledContent("Operating system", value: display(snapshot.operatingSystem))
                LabeledContent("Active URL", value: display(snapshot.activeURL))
                LabeledContent("Local address", value: display(snapshot.localAddress))
            } footer: {
                Text("Pulled from this device’s connection and the server’s public system info. Some servers hide OS or local address.")
            }
            .zelefinRowBackground()

            if let loadError {
                Section {
                    SettingsStatusText(text: loadError, isError: true)
                }
                .zelefinRowBackground()
            }
        }
        .zelefinSettingsChrome(title: "Server Info")
        .overlay {
            if isLoading, snapshot == .empty {
                ProgressView()
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func display(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        loadError = nil

        var next = ServerInfoSnapshot(
            serverName: session.serverName ?? session.session?.serverName,
            product: productLabel(productName: nil),
            version: session.session?.serverVersion,
            operatingSystem: nil,
            activeURL: session.activeServerURL?.absoluteString,
            localAddress: nil
        )

        guard let baseURL = session.activeServerURL ?? session.session?.serverURL else {
            snapshot = next
            loadError = "Not signed in to a server."
            return
        }

        if session.isEmbyServer {
            if let info = try? await EmbyAPI.publicInfo(at: baseURL) {
                next.serverName = nonEmpty(info.serverName) ?? next.serverName
                next.version = nonEmpty(info.version) ?? next.version
                next.product = productLabel(productName: info.productName)
            }
        } else {
            let probe = ServerProbe()
            if let info = try? await probe.publicInfo(at: baseURL) {
                next.serverName = nonEmpty(info.serverName) ?? next.serverName
                next.version = nonEmpty(info.version) ?? next.version
                next.product = productLabel(productName: info.productName)
                next.operatingSystem = nonEmpty(info.operatingSystem)
                next.localAddress = nonEmpty(info.localAddress)
            }

            if let client = session.client, !session.isSiloServer {
                if let system = try? await client.send(Paths.getSystemInfo).value {
                    next.serverName = nonEmpty(system.serverName) ?? next.serverName
                    next.version = nonEmpty(system.version) ?? next.version
                    next.product = productLabel(productName: system.productName)
                    next.operatingSystem =
                        nonEmpty(system.operatingSystemDisplayName)
                        ?? nonEmpty(system.operatingSystem)
                        ?? next.operatingSystem
                    next.localAddress = nonEmpty(system.localAddress) ?? next.localAddress
                }
            }
        }

        snapshot = next
    }

    private func productLabel(productName: String?) -> String {
        if let productName = nonEmpty(productName) {
            return productName
        }
        if session.isSiloServer { return "Silo" }
        if session.isEmbyServer { return "Emby" }
        return "Jellyfin"
    }

    private func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ServerInfoSnapshot: Equatable {
    var serverName: String?
    var product: String?
    var version: String?
    var operatingSystem: String?
    var activeURL: String?
    var localAddress: String?

    static let empty = ServerInfoSnapshot(
        serverName: nil,
        product: nil,
        version: nil,
        operatingSystem: nil,
        activeURL: nil,
        localAddress: nil
    )
}
