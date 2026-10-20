import SwiftUI

struct NetworkSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var localURLText = ""
    @State private var manualSSID = ""

    var body: some View {
        Form {
            Section {
                LabeledContent("Remote URL", value: session.session?.serverURL.absoluteString ?? "—")
                LabeledContent("Active URL", value: session.activeServerURL?.absoluteString ?? "—")
                LabeledContent("Wi-Fi", value: session.currentSSID ?? unavailableWiFi)
                LabeledContent("Using", value: session.activeRoute.title)
            } header: {
                Text("This Connection")
            }
            .zelefinRowBackground()

            Section {
                Toggle("Auto-switch on home Wi-Fi", isOn: autoSwitchBinding)
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
            .zelefinRowBackground()

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
                Text("No networks configured")
            } else {
                ForEach(profile.homeSSIDs, id: \.self) { ssid in
                    HStack {
                        Text(ssid)
                        Spacer(minLength: 8)
                        Button("Remove", role: .destructive) {
                            updateProfile { profile in
                                profile.homeSSIDs.removeAll { $0 == ssid }
                            }
                        }
                    }
                }
            }

            if let current = session.currentSSID, !HomeNetworkResolver.isHome(current, in: profile.homeSSIDs) {
                Button("Add “\(current)”") {
                    addSSID(current)
                }
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
        .zelefinRowBackground()
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
