import SwiftUI

/// Saved logins on this device: switch accounts and add another person.
struct DeviceAccountsView: View {
    @Environment(SessionStore.self) private var session
    @State private var localAvatar: UIImage?

    var body: some View {
        Form {
            Section {
                if let current = session.session {
                    accountRow(current, isCurrent: true)
                }
                ForEach(session.otherAccounts) { account in
                    Button {
                        Task { await switchToAccount(account) }
                    } label: {
                        accountRow(account, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    AddAccountView()
                } label: {
                    Label(addUserTitle, systemImage: "person.badge.plus")
                }
            } footer: {
                Text(footer)
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: title)
    }

    private var title: String {
        session.isSiloServer ? "Accounts" : "Users"
    }

    private var addUserTitle: String {
        session.isSiloServer ? "Add Account" : "Add User"
    }

    private var footer: String {
        if session.hasSiloLink {
            return "Household profiles switch under Profile. Saved users stay on this device."
        }
        if session.isSiloServer {
            return "Add another household profile by signing in as username#profile. Saved users stay on this device."
        }
        let server = session.session?.displayServer ?? session.serverName ?? "this server"
        return "Add another person on \(server). Saved users stay on this device."
    }

    private func accountRow(_ account: SavedSession, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            SettingsPersonRow(
                name: account.userName,
                subtitle: isCurrent ? "Signed in" : accountSubtitle(account),
                avatarURL: session.avatarURL(for: account),
                localImage: isCurrent ? localAvatar : nil,
                showsChevron: false
            )
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } else {
                SettingsChevron()
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCurrent ? "\(account.userName), signed in" : "Switch to \(account.userName)")
        .accessibilityAddTraits(isCurrent ? [.isStaticText] : [.isButton])
    }

    private func accountSubtitle(_ account: SavedSession) -> String {
        let currentHost = session.session?.serverURL.host?.lowercased()
        let accountHost = account.serverURL.host?.lowercased()
        if currentHost != nil, currentHost == accountHost {
            return "On this device"
        }
        return account.displayServer
    }

    private func switchToAccount(_ account: SavedSession) async {
        guard await AccountSwitchUnlock.unlockIfNeeded(account: account) else { return }
        await session.switchTo(account)
    }
}
