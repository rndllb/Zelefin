import SwiftUI

struct NetworkSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var localURLText = ""
    @State private var manualSSID = ""

    var body: some View {
        Form {
            Section {
                labeledURL("Remote URL", session.session?.serverURL)
                labeledURL("Active URL", session.activeServerURL)
                LabeledContent("Wi-Fi") {
                    Text(session.currentSSID ?? unavailableWiFi)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Using") {
                    Text(session.activeRoute.title)
                        .foregroundStyle(AccentPreferences.current)
                }
            } header: {
                Text("This Connection")
            }

            Section {
                Toggle("Auto-switch on home Wi-Fi", isOn: autoSwitchBinding)
                    .tint(AccentPreferences.current)
                TextField(localURLPlaceholder, text: $localURLText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Home Network")
            } footer: {
                Text("When you join a saved home network, Zelefin uses the local URL instead of the remote one.")
            }

            homeWiFiSection

            AccessGatewaySection()
        }
        .zelefinSettingsChrome(title: "Network")
        .task {
            localURLText = session.homeNetworkProfile.localURLString
            await session.requestHomeNetworkAccess()
        }
        .onChange(of: localURLText) { _, value in
            updateProfile { $0.localURLString = value }
        }
    }

    @ViewBuilder
    private var homeWiFiSection: some View {
        Section {
            if profile.homeSSIDs.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No networks configured")
                    Text("Add a network so auto-switch can use the local URL.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(profile.homeSSIDs, id: \.self) { ssid in
                    Text(ssid)
                }
                .onDelete { offsets in
                    updateProfile { profile in
                        profile.homeSSIDs.remove(atOffsets: offsets)
                    }
                }
            }

            if let current = session.currentSSID, !HomeNetworkResolver.isHome(current, in: profile.homeSSIDs) {
                Button {
                    addSSID(current)
                } label: {
                    Text("Add \"\(current)\"")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if session.currentSSID == nil {
                TextField("Network name", text: $manualSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add Network") {
                    addSSID(manualSSID)
                    manualSSID = ""
                }
                .disabled(manualSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text("Home Wi-Fi")
        } footer: {
            Text("Add the networks that should use the local URL.")
        }
    }

    private var profile: HomeNetworkProfile { session.homeNetworkProfile }

    private var localURLPlaceholder: String {
        session.usesSilo ? "http://192.168.1.100" : "http://192.168.1.100:8096"
    }

    private var unavailableWiFi: String {
        "Unavailable"
    }

    private var autoSwitchBinding: Binding<Bool> {
        Binding(
            get: { profile.autoSwitch },
            set: { value in
                updateProfile { $0.autoSwitch = value }
            }
        )
    }

    private func labeledURL(_ title: String, _ url: URL?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(url?.absoluteString ?? "—")
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func addSSID(_ name: String) {
        updateProfile { profile in
            profile.homeSSIDs = HomeNetworkResolver.adding(name, to: profile.homeSSIDs)
        }
    }

    private func updateProfile(_ mutate: (inout HomeNetworkProfile) -> Void) {
        var next = profile
        mutate(&next)
        session.saveHomeNetwork(next)
    }
}
