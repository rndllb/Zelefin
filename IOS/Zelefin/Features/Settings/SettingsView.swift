import SafariServices
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ProfileView()
                } label: {
                    SettingsPersonRow(
                        name: accountDisplayName,
                        subtitle: session.usesSilo ? "Silo account" : "Jellyfin account",
                        avatarURL: session.avatarURL,
                        showsChevron: false
                    )
                }
                .accessibilityLabel("\(accountDisplayName), Account info")
            }

            Section {
                NavigationLink {
                    UserPreferencesView()
                } label: {
                    Label("User Preferences", systemImage: "slider.horizontal.3")
                }
                if session.canAdministerSilo || (session.isAdministrator && !session.usesSilo) {
                    NavigationLink {
                        AdministrationSettingsView()
                    } label: {
                        Label("Administration", systemImage: "lock.shield")
                    }
                }
            }

            Section("Zelefin") {
                NavigationLink {
                    PluginSettingsView()
                } label: {
                    Label("Plugins", systemImage: "puzzlepiece.extension")
                }
                NavigationLink {
                    MetadataSettingsView()
                } label: {
                    Label("Metadata", systemImage: "text.book.closed")
                }
                NavigationLink {
                    TabCustomizationView()
                } label: {
                    Label("Interface", systemImage: "rectangle.3.group")
                }
                NavigationLink {
                    SettingsAboutView()
                } label: {
                    HStack {
                        Label("About", systemImage: "info.circle")
                        Spacer()
                        Text(DeviceIdentity.versionAndBuild)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .zelefinSettingsChrome(title: "Settings")
        .task {
            await session.detectIntroSkipper()
        }
    }

    private var accountDisplayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }
}

struct UserPreferencesView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        List {
            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
                if !session.usesSilo {
                    NavigationLink {
                        SessionsView()
                    } label: {
                        Label("Sessions", systemImage: "play.tv")
                    }
                    NavigationLink {
                        SyncPlayView()
                    } label: {
                        Label("SyncPlay", systemImage: "person.2.wave.2")
                    }
                }
                NavigationLink {
                    PlaybackSettingsView()
                } label: {
                    Label("Playback", systemImage: "play.rectangle.on.rectangle")
                }
                NavigationLink {
                    SubtitleAppearanceSettingsView()
                } label: {
                    Label("Subtitles", systemImage: "captions.bubble")
                }
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "paintpalette")
                }
            }
            Section("This Device") {
                NavigationLink {
                    NetworkSettingsView()
                } label: {
                    Label("Network", systemImage: "network")
                }
                NavigationLink {
                    CacheSettingsView()
                } label: {
                    Label("Cache", systemImage: "internaldrive")
                }
            }
        }
        .zelefinSettingsChrome(title: "User Preferences")
    }
}

struct AdministrationSettingsView: View {
    @Environment(SessionStore.self) private var session
    @State private var showsLibraryScanConfirm = false
    @State private var libraryScanMessage: String?

    var body: some View {
        List {
            Section {
                if session.canAdministerSilo {
                    NavigationLink {
                        SiloUsersView()
                    } label: {
                        Label("Accounts", systemImage: "person.2")
                    }
                    NavigationLink {
                        SiloInvitationsView()
                    } label: {
                        Label("Invitations", systemImage: "envelope.badge")
                    }
                    NavigationLink {
                        SiloSessionsView()
                    } label: {
                        Label("Sessions", systemImage: "play.tv")
                    }
                    NavigationLink {
                        SiloDevicesView()
                    } label: {
                        Label("Devices", systemImage: "iphone")
                    }
                    NavigationLink {
                        SiloLibrariesAdminView()
                    } label: {
                        Label("Libraries", systemImage: "rectangle.stack")
                    }
                    NavigationLink {
                        SiloNodesView()
                    } label: {
                        Label("Nodes", systemImage: "server.rack")
                    }
                    NavigationLink {
                        SiloTasksView()
                    } label: {
                        Label("Scheduled Tasks", systemImage: "clock.arrow.2.circlepath")
                    }
                    NavigationLink {
                        SiloAuditLogView()
                    } label: {
                        Label("Activity Log", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        SiloOperationalLogView()
                    } label: {
                        Label("Server Logs", systemImage: "scroll")
                    }
                    scanLibrariesRow
                } else {
                    NavigationLink {
                        UserManagementView()
                    } label: {
                        Label("Users", systemImage: "person.2")
                    }
                    NavigationLink {
                        ScheduledTasksView()
                    } label: {
                        Label("Scheduled Tasks", systemImage: "clock.arrow.2.circlepath")
                    }
                    NavigationLink {
                        ActivityLogView()
                    } label: {
                        Label("Activity Log", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        ServerBackupsView()
                    } label: {
                        Label("Backups", systemImage: "externaldrive.badge.timemachine")
                    }
                    NavigationLink {
                        ServerBrandingView()
                    } label: {
                        Label("Branding", systemImage: "paintbrush")
                    }
                    scanLibrariesRow
                }
            }
        }
        .zelefinSettingsChrome(title: "Administration")
        .confirmationDialog(
            "Scan every library?",
            isPresented: $showsLibraryScanConfirm,
            titleVisibility: .visible
        ) {
            Button("Scan Libraries") {
                Task { await scanLibraries() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                session.usesSilo
                    ? "Silo will refresh metadata for every library. This can take a while on a large server."
                    : "Jellyfin will look for new files and refresh metadata. This can take a while on a large server."
            )
        }
    }

    private var scanLibrariesRow: some View {
        Button {
            showsLibraryScanConfirm = true
        } label: {
            HStack {
                Label("Scan Libraries", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if let libraryScanMessage {
                    Text(libraryScanMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scanLibraries() async {
        do {
            try await session.library?.scanLibraries()
            libraryScanMessage = "Scan started"
        } catch {
            libraryScanMessage = error.localizedDescription
        }
    }
}

enum ZelefinSite {
    static let privacy = URL(string: "https://zelefin.app/privacy")!
    static let terms = URL(string: "https://zelefin.app/terms")!
}

struct SettingsAboutView: View {
    @State private var legalPage: LegalPage?

    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    ConnectBrandMark(size: 120)
                    Text("Zelefin")
                        .font(.title2.weight(.semibold))
                    SettingsChip(
                        leading: "Version \(DeviceIdentity.version)",
                        trailing: "Build \(DeviceIdentity.build)"
                    )
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            } footer: {
                Text("A native Jellyfin and Silo client for iPhone and iPad. Tab icons are from Iconsax.")
            }

            Section {
                Button("Privacy Policy") { legalPage = .privacy }
                Button("Terms of Use") { legalPage = .terms }
            }
        }
        .zelefinSettingsChrome(title: "About")
        .sheet(item: $legalPage) { page in
            SettingsSafariView(url: page.url)
        }
    }
}

private enum LegalPage: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }

    var url: URL {
        switch self {
        case .privacy: ZelefinSite.privacy
        case .terms: ZelefinSite.terms
        }
    }
}

private struct SettingsSafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

extension View {
    func zelefinSettingsCanvas() -> some View {
        self
            .preferredColorScheme(.dark)
            .zelefinAccentTint()
    }

    func zelefinSettingsChrome(title: String) -> some View {
        self
            .zelefinSettingsCanvas()
            .listStyle(.insetGrouped)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarTitleDisplayMode(.inline)
    }
}
