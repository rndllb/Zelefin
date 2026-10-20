import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
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
            }
            .zelefinRowBackground()

            if session.usesSilo {
                Section {
                    householdStrip
                    if let householdError, !showsAddProfile {
                        Text(householdError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .zelefinRowBackground()
                    }
                } header: {
                    Text("Who’s watching")
                } footer: {
                    Text("Continue Watching, recommendations, and watched flags follow the selected profile — not the account password.")
                }
            }

            if let current = session.session {
                Section("Server") {
                    LabeledContent("Server", value: current.displayServer)
                    LabeledContent("Address", value: current.serverURL.absoluteString)
                    if current.usesSilo, let profile = current.profileName, !profile.isEmpty {
                        LabeledContent("Profile", value: profile)
                    }
                }
                .zelefinRowBackground()
            }

            Section {
                if canChangePassword {
                    SecureField("Current Password", text: $currentPassword)
                        .textContentType(.password)
                        .focused($passwordField, equals: .current)
                        .submitLabel(.next)
                        .onSubmit { advancePasswordField(from: .current) }
                    SecureField("New Password", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($passwordField, equals: .newPassword)
                        .submitLabel(.next)
                        .onSubmit { advancePasswordField(from: .newPassword) }
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($passwordField, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit { advancePasswordField(from: .confirm) }
                    if passwordMismatch {
                        Text("The new passwords do not match.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Button("Update Password") {
                        Task { await savePassword() }
                    }
                    .disabled(!canUpdatePassword || isSavingPassword)
                } else {
                    Text("This household profile cannot change the account password.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Password")
            } footer: {
                Text(passwordFooter)
            }
            .zelefinRowBackground()

            if session.session != nil, !accessToken.isEmpty {
                Section {
                    LabeledContent("Device Token", value: tokenVisible ? accessToken : maskedToken)
                    Button(tokenVisible ? "Hide Token" : "Show Token") {
                        tokenVisible.toggle()
                    }
                    Button(tokenCopied ? "Copied" : "Copy Token") {
                        copyAccessToken()
                    }
                    .disabled(accessToken.isEmpty)
                } header: {
                    Text("Device Token")
                } footer: {
                    Text("This token signs this device into \(serverLabel). Copy it only into apps you trust.")
                }
                .zelefinRowBackground()
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
                addUserRow
            } header: {
                Text(session.usesSilo ? "Accounts" : "Users")
            } footer: {
                Text(session.usesSilo
                     ? "Saved logins stay on this device. People on a login are household profiles, not extra accounts."
                     : "Add another person on \(serverLabel). Saved users stay on this device.")
            }
            .zelefinRowBackground()
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
        VStack(spacing: 12) {
            if session.usesSilo {
                Button {
                    showsSiloAvatarPicker = true
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        profileAvatar
                        CameraBadge()
                            .offset(x: 2, y: 2)
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
                    .offset(x: 2, y: 2)
                    .accessibilityLabel("Change Profile Picture")
                }
            }

            VStack(spacing: 4) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("\(serverKindLabel) · \(serverLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(displayName), \(serverKindLabel), \(serverLabel)")

            if canRemovePhoto, !session.usesSilo {
                Button("Remove Photo", role: .destructive) {
                    Task { await removePhoto() }
                }
                .disabled(isUpdatingPhoto)
            }

            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var serverKindLabel: String {
        session.usesSilo ? "Silo" : "Jellyfin"
    }

    private var profileAvatar: some View {
        ZStack {
            UserAvatarView(url: session.avatarURL, localImage: localAvatar, diameter: 72)
                .id(session.avatarRevision)
            if isUpdatingPhoto {
                Circle()
                    .fill(.black.opacity(0.48))
                    .frame(width: 72, height: 72)
                ProgressView()
            }
        }
        .frame(width: 72, height: 72)
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
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                .zelefinRowBackground()
                Section {
                    Button("Create Profile") {
                        Task { await createHouseholdProfile() }
                    }
                    .disabled(newProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSwitchingProfile)
                }
                .zelefinRowBackground()
                if let householdError {
                    Section {
                        Text(householdError)
                            .foregroundStyle(.red)
                    }
                    .zelefinRowBackground()
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

    private var addUserTitle: String {
        session.usesSilo ? "Add Account" : "Add User"
    }

    private var addUserRow: some View {
        NavigationLink {
            AddAccountView()
        } label: {
            addUserLabel
        }
    }

    private var addUserLabel: some View {
        Label(addUserTitle, systemImage: "person.badge.plus")
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
                    .foregroundStyle(Color.accentColor)
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

    private func uploadPhoto(_ item: PhotosPickerItem) async {
        let image: UIImage
        do {
            image = try await PickedProfileImage.load(item)
        } catch is CancellationError {
            pickerItem = nil
            return
        } catch {
            pickerItem = nil
            statusIsError = true
            status = error.localizedDescription
            return
        }
        guard let jpeg = ProfileImageEncoder.jpegData(from: image) else {
            pickerItem = nil
            statusIsError = true
            status = "Zelefin could not read that photo."
            return
        }
        isUpdatingPhoto = true
        status = nil
        localAvatar = image
        defer {
            isUpdatingPhoto = false
            pickerItem = nil
        }
        do {
            try await session.updateProfileImage(jpeg)
            statusIsError = false
            status = "Profile picture updated."
        } catch is CancellationError {
            localAvatar = nil
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
                LabeledContent("Server", value: serverLabel)
            } footer: {
                Text(session.usesSilo
                     ? "New accounts are added on the Silo server you’re already using. After you sign in, pick a household profile."
                     : "New users are added on the server you’re already using.")
            }
            .zelefinRowBackground()

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
            .zelefinRowBackground()

            Section {
                Button(session.usesSilo ? "Add Account" : "Add User") {
                    Task { await add() }
                }
                .disabled(!canSubmit || isConnecting)
            }
            .zelefinRowBackground()

            if let errorMessage {
                Section {
                    SettingsStatusText(text: errorMessage, isError: true)
                }
                .zelefinRowBackground()
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
        guard let url else {
            remoteImage = nil
            return
        }
        guard let loaded = await ArtworkCache.shared.load(from: url, persist: false) else { return }
        guard !Task.isCancelled else { return }
        remoteImage = loaded
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
