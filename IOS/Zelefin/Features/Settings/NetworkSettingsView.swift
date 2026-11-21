import SwiftUI

struct NetworkSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var localURLText = ""
    @State private var manualSSID = ""

    var body: some View {
        Form {
            Section {
                LabeledContent(AppLanguage.string("ui.remote_url", default: "Remote URL"), value: session.session?.serverURL.absoluteString ?? "—")
                LabeledContent(AppLanguage.string("ui.active_url", default: "Active URL"), value: session.activeServerURL?.absoluteString ?? "—")
                LabeledContent(AppLanguage.string("ui.wi_fi", default: "Wi-Fi"), value: session.currentSSID ?? unavailableWiFi)
                LabeledContent(AppLanguage.string("ui.using", default: "Using"), value: session.activeRoute.title)
            } header: {
                Text(AppLanguage.string("ui.this_connection", default: "This Connection"))
            }
            .zelefinRowBackground()

            Section {
                Toggle(AppLanguage.string("ui.auto_switch_on_home_wi_fi", default: "Auto-switch on home Wi-Fi"), isOn: autoSwitchBinding)
                TextField(localURLPlaceholder, text: $localURLText)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text(AppLanguage.string("ui.home_network", default: "Home Network"))
            } footer: {
                Text(AppLanguage.string("When you join a saved home network, Zelefin uses the local URL instead of the remote one.", default: "When you join a saved home network, Zelefin uses the local URL instead of the remote one."))
            }
            .zelefinRowBackground()

            homeWiFiSection

            AccessGatewaySection()
        }
        .zelefinSettingsChrome(title: AppLanguage.string("settings.network", default: "Network"))
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
                Text(AppLanguage.string("ui.no_networks_configured", default: "No networks configured"))
            } else {
                ForEach(profile.homeSSIDs, id: \.self) { ssid in
                    HStack {
                        Text(ssid)
                        Spacer(minLength: 8)
                        Button(AppLanguage.string("common.remove", default: "Remove"), role: .destructive) {
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
                TextField(AppLanguage.string("ui.network_name", default: "Network name"), text: $manualSSID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(AppLanguage.string("ui.add_network", default: "Add Network")) {
                    addSSID(manualSSID)
                    manualSSID = ""
                }
                .disabled(manualSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        } header: {
            Text(AppLanguage.string("ui.home_wi_fi", default: "Home Wi-Fi"))
        } footer: {
            Text(AppLanguage.string("Add the networks that should use the local URL.", default: "Add the networks that should use the local URL."))
        }
        .zelefinRowBackground()
    }

    private var profile: HomeNetworkProfile { session.homeNetworkProfile }

    private var localURLPlaceholder: String {
        "http://192.168.1.100:8096"
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
