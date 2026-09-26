import SwiftUI

struct NetworkSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var localURLText = ""
    @State private var manualSSID = ""

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsInfoRow(label: "Remote URL", value: session.session?.serverURL.absoluteString ?? "—")
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Active URL", value: session.activeServerURL?.absoluteString ?? "—")
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Wi-Fi", value: session.currentSSID ?? unavailableWiFi)
                    SettingsCardDivider()
                    SettingsInfoRow(label: "Using", value: session.activeRoute.title)
                }
                .settingsLoginCard()
                .settingsCardRow()
            } header: {
                Text("This Connection")
            }

            Section {
                VStack(alignment: .leading, spacing: 0) {
                    Toggle("Auto-switch on home Wi-Fi", isOn: autoSwitchBinding)
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.semibold))
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Local URL", systemImage: "house.fill") {
                        TextField(localURLPlaceholder, text: $localURLText)
                            .textContentType(.URL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .settingsLoginCard()
                .settingsCardRow()
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
            VStack(alignment: .leading, spacing: 0) {
                if profile.homeSSIDs.isEmpty {
                    SettingsStackedRow(
                        title: "No networks configured",
                        subtitle: "Add a network so auto-switch can use the local URL."
                    )
                } else {
                    ForEach(Array(profile.homeSSIDs.enumerated()), id: \.element) { index, ssid in
                        if index > 0 { SettingsCardDivider() }
                        HStack {
                            Text(ssid)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(LoginPalette.primaryText)
                            Spacer(minLength: 8)
                            Button("Remove", role: .destructive) {
                                updateProfile { profile in
                                    profile.homeSSIDs.removeAll { $0 == ssid }
                                }
                            }
                            .font(.caption.weight(.bold))
                        }
                    }
                }

                if let current = session.currentSSID, !HomeNetworkResolver.isHome(current, in: profile.homeSSIDs) {
                    SettingsPrimaryButton(title: "Add \"\(current)\"") {
                        addSSID(current)
                    }
                    .padding(.top, 16)
                } else if session.currentSSID == nil {
                    SettingsCardDivider()
                    SettingsLabeledField(label: "Network name", systemImage: "wifi") {
                        TextField("Network name", text: $manualSSID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    SettingsPrimaryButton(
                        title: "Add Network",
                        enabled: !manualSSID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) {
                        addSSID(manualSSID)
                        manualSSID = ""
                    }
                    .padding(.top, 16)
                }
            }
            .settingsLoginCard()
            .settingsCardRow()
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
