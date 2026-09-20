import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isSavingPassword = false
    @State private var isUpdatingPhoto = false
    @State private var localAvatar: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showsSiloAvatarPicker = false
    @State private var tokenVisible = false
    @State private var tokenCopied = false
    @State private var pinProfile: SiloHouseholdProfile?
    @State private var profilePIN = ""
    @State private var isSwitchingProfile = false
    @State private var switchingProfileID: String?
    @State private var householdError: String?
    @State private var showsAddProfile = false
    @State private var newProfileName = ""
    @State private var newProfilePIN = ""
    @State private var newProfileIsChild = false
    @FocusState private var passwordField: PasswordField?

    var body: some View {
        Form {
            Section {
                identityHero
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if session.usesSilo {
                Section {
                    householdStrip
                    if let householdError, !showsAddProfile {
                        Text(householdError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Who’s watching")
                } footer: {
                    Text("Continue Watching, recommendations, and watched flags follow the selected profile — not the account password.")
                }
            }

            Section {
                passwordCard
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 10, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } header: {
                Text("Password")
            } footer: {
                Text(passwordFooter)
            }

            Section {
                if let current = session.session {
                    accountRow(current, isCurrent: true)
                }
                ForEach(session.otherAccounts) { account in
                    Button {
                        Task { await session.switchTo(account) }
                    } label: {
                        accountRow(account, isCurrent: false)
                    }
                    .buttonStyle(.plain)
                }
                if plus.isUnlocked {
                    NavigationLink {
                        AddAccountView()
                    } label: {
                        Label(session.usesSilo ? "Add Account" : "Add User", systemImage: "person.badge.plus")
                    }
                } else {
                    Button {
                        plus.request(.extraAccounts)
                    } label: {
                        HStack {
                            Label(session.usesSilo ? "Add Account" : "Add User", systemImage: "person.badge.plus")
                            Spacer(minLength: 8)
                            Image(systemName: "lock.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text(session.usesSilo ? "Accounts" : "Users")
            } footer: {
                Text(session.usesSilo
                     ? "Saved logins stay on this device. People on a login are household profiles, not extra accounts."
                     : "Add another person on \(serverLabel). Saved users stay on this device.")
            }
        }
        .zelefinSettingsChrome(title: "Profile")
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
        .sheet(isPresented: $showsSiloAvatarPicker) {
            SiloAvatarPickerView()
        }
        .sheet(isPresented: $showsAddProfile) {
            addProfileSheet
        }
        .alert(
            "PIN for \(pinProfile?.name ?? "this profile")",
            isPresented: Binding(
                get: { pinProfile != nil },
                set: { if !$0 { pinProfile = nil; profilePIN = "" } }
            )
        ) {
            SecureField("PIN", text: $profilePIN)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                pinProfile = nil
                profilePIN = ""
            }
            Button("Switch") {
                guard let profile = pinProfile else { return }
                Task { await switchHouseholdProfile(profile, pin: profilePIN) }
            }
        } message: {
            Text("This profile is locked.")
        }
    }

    private var displayName: String {
        if session.usesSilo {
            let profile = session.session?.profileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !profile.isEmpty { return profile }
        }
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    private var serverLabel: String {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        return name.isEmpty ? "this server" : name
    }

    private enum PasswordField: Hashable {
        case current, newPassword, confirm
    }

    private var canChangePassword: Bool {
        !(session.usesSilo && !session.canChangeSiloPassword)
    }

    private var canUpdatePassword: Bool {
        canChangePassword
            && !currentPassword.isEmpty
            && !newPassword.isEmpty
            && newPassword == confirmPassword
    }

    private var passwordMismatch: Bool {
        !confirmPassword.isEmpty && newPassword != confirmPassword
    }

    private var passwordFooter: String {
        if !canChangePassword {
            return "Switch to the primary household profile to change this account password."
        }
        return "Updates the password for this login on \(serverLabel)."
    }

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if canChangePassword {
                passwordFieldRow(
                    label: "Current",
                    text: $currentPassword,
                    contentType: .password,
                    field: .current,
                    submit: .next
                )
                passwordDivider
                passwordFieldRow(
                    label: "New",
                    text: $newPassword,
                    contentType: .newPassword,
                    field: .newPassword,
                    submit: .next
                )
                passwordDivider
                passwordFieldRow(
                    label: "Confirm",
                    text: $confirmPassword,
                    contentType: .newPassword,
                    field: .confirm,
                    submit: .go
                )
                if passwordMismatch {
                    Text("The new passwords do not match.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(LoginPalette.failure)
                        .padding(.top, 12)
                }
                Button {
                    Task { await savePassword() }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isSavingPassword {
                            ProgressView()
                                .tint(LoginPalette.actionLabel)
                        } else {
                            Text("Update Password")
                                .font(.caption.weight(.bold))
                                .tracking(0.8)
                        }
                        Spacer(minLength: 0)
                    }
                    .modifier(LoginActionButtonStyle())
                }
                .buttonStyle(.plain)
                .disabled(!canUpdatePassword || isSavingPassword)
                .opacity(!canUpdatePassword || isSavingPassword ? 0.42 : 1)
                .padding(.top, 16)
                .accessibilityLabel("Update Password")
            } else {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "lock.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(LoginPalette.iconTint)
                        .frame(width: 22, alignment: .center)
                    Text("This household profile cannot change the account password.")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(LoginPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LoginCardBackground())
    }

    private var passwordDivider: some View {
        Rectangle()
            .fill(LoginPalette.divider)
            .frame(height: 1)
            .padding(.vertical, 12)
    }

    private func passwordFieldRow(
        label: String,
        text: Binding<String>,
        contentType: UITextContentType,
        field: PasswordField,
        submit: SubmitLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoginPalette.captionText)
                .tracking(0.6)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LoginPalette.iconTint)
                    .frame(width: 22, alignment: .center)
                    .accessibilityHidden(true)
                SecureField(label, text: text)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.fieldValue)
                    .textContentType(contentType)
                    .submitLabel(submit)
                    .focused($passwordField, equals: field)
                    .onSubmit { advancePasswordField(from: field) }
                    .accessibilityLabel(label)
            }
        }
    }

    private func advancePasswordField(from field: PasswordField) {
        switch field {
        case .current:
            passwordField = .newPassword
        case .newPassword:
            passwordField = .confirm
        case .confirm:
            guard canUpdatePassword, !isSavingPassword else { return }
            Task { await savePassword() }
        }
    }

    private var accessToken: String {
        session.session?.accessToken ?? ""
    }

    private var accessTokenCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Device token")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 10) {
                Group {
                    if tokenVisible {
                        Text(accessToken)
                            .textSelection(.enabled)
                    } else {
                        Text(maskedToken)
                    }
                }
                .font(.footnote.monospaced())
                .lineLimit(tokenVisible ? 6 : 1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tokenVisible ? "Access token" : "Hidden access token")
                Button {
                    tokenVisible.toggle()
                } label: {
                    Image(systemName: tokenVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(tokenVisible ? "Hide token" : "Show token")
                Button {
                    copyAccessToken()
                } label: {
                    Image(systemName: tokenCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .disabled(accessToken.isEmpty)
                .accessibilityLabel(tokenCopied ? "Copied" : "Copy token")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LoginCardBackground())
        .accessibilityHint("This token signs this device into \(serverLabel). Copy it only into apps you trust.")
    }

    private var maskedToken: String {
        guard !accessToken.isEmpty else { return "—" }
        return String(repeating: "•", count: min(28, max(12, accessToken.count)))
    }

    private var canRemovePhoto: Bool {
        if session.usesSilo {
            return localAvatar != nil || session.householdProfiles.contains(where: {
                $0.id == session.session?.profileID && $0.hasAvatar
            })
        }
        return session.session?.userImageTag != nil || localAvatar != nil
    }

    private func copyAccessToken() {
        guard !accessToken.isEmpty else { return }
        UIPasteboard.general.string = accessToken
        tokenCopied = true
        statusIsError = false
        status = "Access token copied."
    }

    private var identityHero: some View {
        VStack(spacing: 18) {
            if session.usesSilo {
                Button {
                    showsSiloAvatarPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        profileAvatar
                        CameraBadge()
                            .offset(x: -2, y: -2)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUpdatingPhoto)
                .accessibilityLabel("Change Profile Picture")
            } else {
                ZStack(alignment: .bottomTrailing) {
                    profileAvatar
                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
                        CameraBadge()
                    }
                    .disabled(isUpdatingPhoto)
                    .offset(x: -2, y: -2)
                    .accessibilityLabel("Change Profile Picture")
                }
            }

            VStack(spacing: 10) {
                Text(displayName)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                serverChip
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(displayName), \(serverKindLabel), \(serverLabel)")

            if canRemovePhoto, !session.usesSilo {
                Button("Remove Photo", role: .destructive) {
                    Task { await removePhoto() }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isUpdatingPhoto)
            }

            if session.session != nil, !accessToken.isEmpty {
                accessTokenCard
            }

            if let status {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var serverChip: some View {
        HStack(spacing: 6) {
            Image(systemName: session.usesSilo ? "square.stack.3d.forward.dottedline.fill" : "play.tv.fill")
                .font(.caption2.weight(.bold))
            Text(serverKindLabel)
                .font(.caption.weight(.bold))
            Text(serverLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .zelefinLiquidGlassCapsule(interactive: false)
    }

    private var serverKindLabel: String {
        session.usesSilo ? "Silo" : "Jellyfin"
    }

    private var profileAvatar: some View {
        ZStack {
            UserAvatarView(url: session.avatarURL, localImage: localAvatar, diameter: 132)
                .id(session.avatarRevision)
                .padding(6)
                .zelefinLiquidGlassCircle(interactive: false)
            if isUpdatingPhoto {
                Circle()
                    .fill(.black.opacity(0.48))
                    .frame(width: 144, height: 144)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 144, height: 144)
        .accessibilityHidden(true)
    }

    private var householdStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(session.householdProfiles) { profile in
                    let isCurrent = profile.id == session.session?.profileID
                    Button {
                        selectHouseholdProfile(profile)
                    } label: {
                        ZStack {
                            HouseholdProfileTile(
                                profile: profile,
                                isCurrent: isCurrent,
                                isSelected: switchingProfileID == profile.id,
                                size: 76
                            )
                            if switchingProfileID == profile.id {
                                Circle()
                                    .fill(.black.opacity(0.45))
                                    .frame(width: 76, height: 76)
                                    .offset(y: -16)
                                ProgressView()
                                    .tint(.white)
                                    .offset(y: -16)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isSwitchingProfile || isCurrent)
                    .accessibilityLabel(householdAccessibility(profile, isCurrent: isCurrent))
                    .accessibilityAddTraits(isCurrent ? [.isSelected] : [.isButton])
                }
                if session.canChangeSiloPassword {
                    Button {
                        householdError = nil
                        newProfileName = ""
                        newProfilePIN = ""
                        newProfileIsChild = false
                        showsAddProfile = true
                    } label: {
                        addProfileTile
                    }
                    .buttonStyle(.plain)
                    .disabled(isSwitchingProfile)
                    .accessibilityLabel("Add Profile")
                }
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private var addProfileTile: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.white.opacity(0.08)))
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 1)
                }
            Text("Add")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LoginPalette.primaryText)
        }
        .frame(width: 84)
    }

    private func householdAccessibility(_ profile: SiloHouseholdProfile, isCurrent: Bool) -> String {
        var parts = [profile.name]
        if isCurrent { parts.append("watching") }
        if profile.isPrimary { parts.append("primary") }
        if profile.isChild { parts.append("kids") }
        if profile.hasPin { parts.append("PIN required") }
        if !isCurrent { parts.append("switch profile") }
        return parts.joined(separator: ", ")
    }

    private func selectHouseholdProfile(_ profile: SiloHouseholdProfile) {
        householdError = nil
        guard profile.id != session.session?.profileID else { return }
        if profile.hasPin {
            profilePIN = ""
            pinProfile = profile
            return
        }
        Task { await switchHouseholdProfile(profile, pin: nil) }
    }

    private func switchHouseholdProfile(_ profile: SiloHouseholdProfile, pin: String?) async {
        isSwitchingProfile = true
        switchingProfileID = profile.id
        householdError = nil
        defer {
            isSwitchingProfile = false
            switchingProfileID = nil
            pinProfile = nil
            profilePIN = ""
        }
        do {
            try await session.applySiloProfile(profile, pin: pin)
        } catch {
            householdError = error.localizedDescription
        }
    }

    private var addProfileSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $newProfileName)
                    Toggle("Kids profile", isOn: $newProfileIsChild)
                    SecureField("PIN (optional)", text: $newProfilePIN)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("A PIN locks this person on this login. Leave it empty for an unlocked profile.")
                }
                Section {
                    Button("Create Profile") {
                        Task { await createHouseholdProfile() }
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSwitchingProfile)
                }
                if let householdError {
                    Section {
                        Text(householdError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .zelefinSettingsChrome(title: "Add Profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsAddProfile = false }
                }
            }
        }
    }

    private func createHouseholdProfile() async {
        isSwitchingProfile = true
        householdError = nil
        defer { isSwitchingProfile = false }
        do {
            let pinValue = newProfilePIN.trimmingCharacters(in: .whitespacesAndNewlines)
            try await session.createSiloProfile(
                name: newProfileName,
                pin: pinValue.isEmpty ? nil : pinValue,
                isChild: newProfileIsChild
            )
            showsAddProfile = false
            newProfileName = ""
            newProfilePIN = ""
            newProfileIsChild = false
        } catch {
            householdError = error.localizedDescription
        }
    }

    private func accountRow(_ account: SavedSession, isCurrent: Bool) -> some View {
        HStack(spacing: 14) {
            UserAvatarView(
                url: session.avatarURL(for: account),
                localImage: isCurrent ? localAvatar : nil,
                diameter: 48
            )
            .overlay {
                Circle()
                    .strokeBorder(isCurrent ? Color.white : Color.clear, lineWidth: 2)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(account.userName)
                    .font(.body.weight(.semibold))
                Text(isCurrent ? "Signed in" : accountSubtitle(account))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AccentPreferences.current)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
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

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        isUpdatingPhoto = true
        status = nil
        defer {
            isUpdatingPhoto = false
            pickerItem = nil
        }
        do {
            let image = try await PickedProfileImage.load(item)
            guard let jpeg = ProfileImageEncoder.jpegData(from: image) else {
                throw ZelefinError.server("Zelefin could not read that photo.")
            }
            localAvatar = image
            try await session.updateProfileImage(jpeg)
            statusIsError = false
            status = "Profile picture updated."
        } catch {
            localAvatar = nil
            statusIsError = true
            status = error.localizedDescription
        }
    }

    private func removePhoto() async {
        isUpdatingPhoto = true
        status = nil
        defer { isUpdatingPhoto = false }
        do {
            try await session.removeProfileImage()
            localAvatar = nil
            statusIsError = false
            status = "Profile picture removed."
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }

    private func savePassword() async {
        guard newPassword == confirmPassword else {
            statusIsError = true
            status = "The new passwords do not match."
            return
        }
        isSavingPassword = true
        status = nil
        defer { isSavingPassword = false }
        do {
            try await session.changePassword(current: currentPassword, new: newPassword)
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            statusIsError = false
            status = "Password updated."
        } catch {
            statusIsError = true
            status = error.localizedDescription
        }
    }
}

struct AddAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var householdPick: [SiloHouseholdProfile] = []

    var body: some View {
        Group {
            if !householdPick.isEmpty {
                SiloWhoIsWatchingView(
                    profiles: householdPick,
                    footerTitle: "Cancel",
                    isBusy: isConnecting,
                    errorMessage: errorMessage,
                    onSelect: { profile, pin in
                        await pick(profile, pin: pin)
                    },
                    onFooter: {
                        errorMessage = nil
                        householdPick = []
                        session.cancelSiloProfilePick()
                    }
                )
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            } else {
                addForm
            }
        }
        .onDisappear {
            householdPick = []
            if session.pendingSiloSignIn != nil {
                session.cancelSiloProfilePick()
            }
        }
    }

    private var addForm: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AccentPreferences.current)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(serverLabel)
                            .font(.body.weight(.semibold))
                        Text("This server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AccentPreferences.current)
                }
                .padding(.vertical, 4)
            } footer: {
                Text(session.usesSilo
                     ? "New accounts are added on the Silo server you’re already using. After you sign in, pick a household profile."
                     : "New users are added on the server you’re already using.")
            }

            Section {
                TextField(session.usesSilo ? "Username or email" : "Username", text: $username)
                    .textContentType(.username)
                    .keyboardType(session.usesSilo ? .emailAddress : .default)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Sign In")
            }

            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isConnecting {
                            ProgressView()
                        } else {
                            Text(session.usesSilo ? "Add Account" : "Add User")
                                .fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(!canSubmit || isConnecting)
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .zelefinSettingsChrome(title: session.usesSilo ? "Add Account" : "Add User")
    }

    private var serverLabel: String {
        session.session?.displayServer ?? session.serverName ?? "Jellyfin"
    }

    private var canSubmit: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    private func add() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await session.addUserOnCurrentServer(username: username, password: password)
            if let pending = session.pendingSiloSignIn {
                householdPick = pending.profiles
            } else {
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pick(_ profile: SiloHouseholdProfile, pin: String?) async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }
        do {
            try await session.selectSiloProfile(profile, pin: pin)
            householdPick = []
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UserAvatarView: View {
    let url: URL?
    var localImage: UIImage? = nil
    var diameter: CGFloat = 45
    @State private var remoteImage: UIImage?

    private var displayed: UIImage? { localImage ?? remoteImage }

    var body: some View {
        Group {
            if let displayed {
                Image(uiImage: displayed)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: diameter * 0.44, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: diameter, height: diameter)
        .background(Color.white.opacity(0.08))
        .clipShape(Circle())
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard localImage == nil else { return }
        remoteImage = nil
        guard let url else { return }
        if let loaded = await ArtworkCache.shared.load(from: url, persist: false) {
            guard !Task.isCancelled else { return }
            remoteImage = loaded
        }
    }
}

enum PickedProfileImage {
    static func load(_ item: PhotosPickerItem) async throws -> UIImage {
        if let picked = try await item.loadTransferable(type: ProfilePickerImage.self) {
            return picked.image
        }
        if let data = try await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            return image
        }
        throw ZelefinError.server("Zelefin could not read that photo.")
    }
}

private struct ProfilePickerImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .heic, importing: decode)
        DataRepresentation(importedContentType: .jpeg, importing: decode)
        DataRepresentation(importedContentType: .png, importing: decode)
        DataRepresentation(importedContentType: .webP, importing: decode)
        DataRepresentation(importedContentType: .image, importing: decode)
    }

    private static func decode(_ data: Data) throws -> ProfilePickerImage {
        guard let image = UIImage(data: data) else {
            throw ZelefinError.server("Zelefin could not read that photo.")
        }
        return ProfilePickerImage(image: image)
    }
}

/// The small camera glyph overlaid on the avatar. A standalone `View` value
/// (rather than a main-actor-isolated computed property) so it can be built
/// inside the `PhotosPicker` label closure without a Sendable-isolation warning.
private struct CameraBadge: View {
    var body: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 32, height: 32)
            .background(Circle().fill(.white))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }
}

enum ProfileImageEncoder {
    static func jpegData(from image: UIImage, maxPixel: CGFloat = 720, quality: CGFloat = 0.86) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxPixel ? maxPixel / longest : 1
        let size = CGSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let renderer = UIGraphicsImageRenderer(size: size)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
