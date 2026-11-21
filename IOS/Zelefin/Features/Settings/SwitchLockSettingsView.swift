import SwiftUI

/// Device-local PIN / biometrics rows for the Profile Account section.
struct AccountPINControls: View {
    @Environment(SessionStore.self) private var session
    @Binding var status: String?
    @Binding var statusIsError: Bool

    @State private var pinEditor: AccountPINEditor?
    @State private var pinError: String?
    @State private var hasPIN = false
    @State private var unlockWithBiometrics = false

    var body: some View {
        Group {
            if hasPIN {
                LabeledContent(AppLanguage.string("ui.account_pin", default: "Account PIN"), value: "On")
                if AccountSwitchPIN.canUseBiometrics {
                    Toggle("Unlock with \(AccountSwitchPIN.biometricsName)", isOn: $unlockWithBiometrics)
                        .onChange(of: unlockWithBiometrics) { _, enabled in
                            guard let id = session.session?.accountID else { return }
                            AccountSwitchPIN.setBiometricsEnabled(enabled, for: id)
                        }
                }
                Button(AppLanguage.string("ui.change_pin", default: "Change PIN")) {
                    Task {
                        guard let current = session.session else { return }
                        guard await AccountSwitchUnlock.unlockIfNeeded(account: current) else { return }
                        pinError = nil
                        pinEditor = .change
                    }
                }
                Button(AppLanguage.string("ui.remove_pin", default: "Remove PIN"), role: .destructive) {
                    Task { await removePIN() }
                }
            } else {
                Button(AppLanguage.string("ui.create_account_pin", default: "Create Account PIN")) {
                    pinError = nil
                    pinEditor = .create
                }
            }
            if let pinError {
                Text(pinError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .task { refreshPINState() }
        .sheet(item: $pinEditor) { editor in
            AccountPINEditorSheet(
                mode: editor,
                onSave: { pin in
                    try savePIN(pin)
                },
                onCancel: { pinEditor = nil }
            )
        }
    }

    private func refreshPINState() {
        guard let id = session.session?.accountID else {
            hasPIN = false
            unlockWithBiometrics = false
            return
        }
        hasPIN = AccountSwitchPIN.hasPIN(for: id)
        unlockWithBiometrics = AccountSwitchPIN.biometricsEnabled(for: id)
    }

    private func savePIN(_ pin: String) throws {
        guard let id = session.session?.accountID else {
            throw ZelefinError.server("Sign in to create an account PIN.")
        }
        try AccountSwitchPIN.setPIN(pin, for: id)
        pinEditor = nil
        pinError = nil
        refreshPINState()
        statusIsError = false
        status = "Account PIN saved on this device."
    }

    private func removePIN() async {
        guard let current = session.session else { return }
        guard await AccountSwitchUnlock.unlockIfNeeded(account: current) else { return }
        AccountSwitchPIN.remove(for: current.accountID)
        refreshPINState()
        statusIsError = false
        status = "Account PIN removed."
    }
}

private enum AccountPINEditor: String, Identifiable {
    case create
    case change

    var id: String { rawValue }

    var title: String {
        switch self {
        case .create: "Create Account PIN"
        case .change: "Change Account PIN"
        }
    }
}

private struct AccountPINEditorSheet: View {
    let mode: AccountPINEditor
    var onSave: (String) throws -> Void
    var onCancel: () -> Void

    @State private var pin = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField(AppLanguage.string("connect.pin", default: "PIN"), text: $pin)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    SecureField(AppLanguage.string("ui.confirm_pin", default: "Confirm PIN"), text: $confirm)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text(AppLanguage.string("Use 4 to 6 digits. This PIN stays on this device and is asked before someone can sign into this account.", default: "Use 4 to 6 digits. This PIN stays on this device and is asked before someone can sign into this account."))
                }
                .zelefinRowBackground()
            }
            .zelefinSettingsChrome(title: mode.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppLanguage.string("common.cancel", default: "Cancel"), action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.string("common.save", default: "Save")) { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        AccountSwitchPIN.isValidPIN(pin) && pin == confirm
    }

    private func save() {
        guard pin == confirm else {
            errorMessage = "The PINs do not match."
            return
        }
        do {
            try onSave(pin)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
