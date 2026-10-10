import SwiftUI
import JellyfinAPI
import PhotosUI
import UIKit

struct UserManagementView: View {
    @Environment(SessionStore.self) private var session
    @State private var users: [ServerUserAccount] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty {
                ContentUnavailableView(
                    "No Users",
                    systemImage: "person.2",
                    description: Text(errorMessage ?? "This server did not return any users.")
                )
            } else {
                List {
                    if let errorMessage {
                        Section {
                            SettingsStatusText(text: errorMessage, isError: true)
                        }
                    }

                    Section {
                        ForEach(users) { account in
                            NavigationLink {
                                UserAccountEditorView(account: account) {
                                    await reload()
                                }
                            } label: {
                                SettingsPersonRow(
                                    name: account.name,
                                    subtitle: account.statusSubtitle,
                                    avatarURL: session.library?.userAvatarURL(
                                        userID: account.id,
                                        tag: account.primaryImageTag
                                    ),
                                    showsChevron: true
                                )
                            }
                        }
                    } footer: {
                        Text("Administrators can change photos, permissions, library access, and parental controls on this Jellyfin server.")
                    }
                }
            }
        }
        .zelefinSettingsChrome(title: "Users")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func reload() async {
        errorMessage = nil
        do {
            let admin = try session.userAdminClient()
            users = try await admin.users()
        } catch {
            users = []
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct UserAccountEditorView: View {
    @Environment(SessionStore.self) private var session
    @State var account: ServerUserAccount
    var onChanged: () async -> Void

    @State private var draft: UserPolicyDraft
    @State private var username: String
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var folders: [AdminMediaFolder] = []
    @State private var ratings: [ParentalRatingChoice] = []
    @State private var ratingID = "none"
    @State private var ratingsReady = false
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isSaving = false
    @State private var confirmDisable = false
    @State private var confirmResetPassword = false
    @State private var pendingAdministrator: Bool?
    @State private var localAvatar: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var isUpdatingPhoto = false
    @FocusState private var passwordField: PasswordField?

    private var isCurrentUser: Bool {
        session.session?.userID == account.id
    }

    init(account: ServerUserAccount, onChanged: @escaping () async -> Void) {
        self.account = account
        self.onChanged = onChanged
        let policy = account.policy
        _draft = State(
            initialValue: policy.map(UserPolicyDraft.init) ?? UserPolicyDraft(
                isAdministrator: false,
                isDisabled: false,
                enableSubtitleManagement: false,
                remoteClientBitrateLimit: 0,
                maxParentalRating: nil,
                blockUnratedItems: [],
                enableAllFolders: true,
                enabledFolders: []
            )
        )
        _username = State(initialValue: account.dto.name ?? "")
    }

    var body: some View {
        List {
            identitySection
            usernameSection
            permissionsSection
            bitrateSection
            passwordSection
            parentalSection
            librarySection
            if let status {
                Section {
                    SettingsStatusText(text: status, isError: statusIsError)
                }
            }
        }
        .zelefinSettingsChrome(title: account.name)
        .task { await loadSupport() }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
        }
        .onChange(of: ratingID) { _, newValue in
            guard ratingsReady else { return }
            applyRatingSelection(newValue)
        }
        .confirmationDialog(
            "Disable this account?",
            isPresented: $confirmDisable,
            titleVisibility: .visible
        ) {
            Button("Disable Account", role: .destructive) {
                draft.isDisabled = true
                Task { await savePolicy() }
            }
            Button("Cancel", role: .cancel) {
                draft.isDisabled = false
            }
        } message: {
            Text("They will not be able to sign in until you turn the account back on.")
        }
        .confirmationDialog(
            "Reset this password?",
            isPresented: $confirmResetPassword,
            titleVisibility: .visible
        ) {
            Button("Reset Password", role: .destructive) {
                Task { await resetPassword() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Jellyfin clears the password. They set a new one the next time they sign in.")
        }
        .confirmationDialog(
            "Remove administrator access?",
            isPresented: Binding(
                get: { pendingAdministrator != nil },
                set: { if !$0 { pendingAdministrator = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Access", role: .destructive) {
                draft.isAdministrator = false
                pendingAdministrator = nil
                Task { await savePolicy() }
            }
            Button("Cancel", role: .cancel) {
                draft.isAdministrator = true
                pendingAdministrator = nil
            }
        }
    }

    private enum PasswordField: Hashable {
        case newPassword, confirm
    }

    private var identitySection: some View {
        Section {
            VStack(spacing: 18) {
                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        UserAvatarView(
                            url: session.library?.userAvatarURL(userID: account.id, tag: account.primaryImageTag),
                            localImage: localAvatar,
                            diameter: 132
                        )
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

                    PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
                        SettingsCameraBadge()
                    }
                    .disabled(isUpdatingPhoto)
                    .offset(x: -2, y: -2)
                    .accessibilityLabel("Change Profile Picture")
                }

                VStack(spacing: 10) {
                    Text(account.name)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                    SettingsChip(
                        icon: account.isAdministrator ? "checkmark.shield.fill" : "person.fill",
                        leading: account.isDisabled ? "Disabled" : account.statusSubtitle
                    )
                }

                if account.primaryImageTag != nil || localAvatar != nil {
                    Button("Remove Photo", role: .destructive) {
                        Task { await removePhoto() }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(isSaving || isUpdatingPhoto)
                }
            }
            .frame(maxWidth: .infinity)
            .settingsHeroRow()
        } footer: {
            Text("Administrators can change this user's profile picture on the server.")
        }
    }

    private var usernameSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsLabeledField(label: "Username", systemImage: "person.fill") {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                SettingsPrimaryButton(
                    title: "Save Username",
                    isBusy: isSaving,
                    enabled: canSaveUsername && !isUpdatingPhoto
                ) {
                    Task { await saveUsername() }
                }
                .padding(.top, 16)
            }
        }
    }

    private var permissionsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("Administrator", isOn: administratorBinding)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.medium))
                SettingsCardDivider()
                Toggle("Edit Subtitles", isOn: subtitleManagementBinding)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.medium))
                SettingsCardDivider()
                Toggle("Disable Account", isOn: disabledBinding)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.medium))
            }
        } header: {
            Text("Permissions")
        } footer: {
            Text("Administrators can manage users, sessions, and server settings. Edit Subtitles lets this user search and download subtitles onto the server, same as an administrator.")
        }
    }

    private var bitrateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                SettingsFieldLabel(title: "Remote bitrate")
                Picker("Remote bitrate", selection: $draft.remoteClientBitrateLimit) {
                    ForEach(bitrateOptions, id: \.self) { limit in
                        Text(bitrateTitle(limit)).tag(limit)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                .onChange(of: draft.remoteClientBitrateLimit) { _, _ in
                    Task { await savePolicy() }
                }
            }
        } header: {
            Text("Streaming")
        } footer: {
            Text("Caps how fast this user can pull video from outside the local network. Unlimited leaves the client in charge.")
        }
    }

    private var passwordSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsLabeledField(label: "New", systemImage: "lock.fill") {
                    SecureField("New", text: $newPassword)
                        .textContentType(.newPassword)
                        .focused($passwordField, equals: .newPassword)
                        .submitLabel(.next)
                        .onSubmit { passwordField = .confirm }
                }
                SettingsCardDivider()
                SettingsLabeledField(label: "Confirm", systemImage: "lock.fill") {
                    SecureField("Confirm", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($passwordField, equals: .confirm)
                        .submitLabel(.go)
                        .onSubmit {
                            guard canSetPassword, !isSaving else { return }
                            Task { await setPassword() }
                        }
                }
                if !confirmPassword.isEmpty && newPassword != confirmPassword {
                    Text("The new passwords do not match.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(LoginPalette.failure)
                        .padding(.top, 12)
                }
                SettingsPrimaryButton(
                    title: "Set Password",
                    isBusy: isSaving,
                    enabled: canSetPassword
                ) {
                    Task { await setPassword() }
                }
                .padding(.top, 16)
                SettingsSecondaryButton(
                    title: "Reset Password",
                    role: .destructive,
                    enabled: !isSaving
                ) {
                    confirmResetPassword = true
                }
                .padding(.top, 10)
            }
        } header: {
            Text("Password")
        } footer: {
            Text("Reset clears the password on the server. Set Password stores the new one now.")
        }
    }

    private var parentalSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsFieldLabel(title: "Maximum rating")
                    .padding(.bottom, 8)
                Picker("Maximum rating", selection: $ratingID) {
                    Text("None").tag("none")
                    ForEach(ratings) { rating in
                        Text(rating.name).tag(rating.id)
                    }
                }
                .pickerStyle(.menu)
                .tint(AccentPreferences.current)
                ForEach(UnratedItem.allCases, id: \.self) { item in
                    SettingsCardDivider()
                    Toggle(item.settingsTitle, isOn: unratedBinding(item))
                        .tint(AccentPreferences.current)
                        .font(.body.weight(.medium))
                }
            }
        } header: {
            Text("Parental Controls")
        } footer: {
            Text("Maximum rating hides titles above that score. Blocked types stay hidden even when they have no rating.")
        }
    }

    private var librarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                Toggle("All libraries", isOn: allFoldersBinding)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.medium))
                if !draft.enableAllFolders {
                    ForEach(folders) { folder in
                        SettingsCardDivider()
                        Toggle(folder.name, isOn: folderBinding(folder.id))
                            .tint(AccentPreferences.current)
                            .font(.body.weight(.medium))
                    }
                }
            }
        } header: {
            Text("Library Access")
        } footer: {
            Text("Turn off All libraries to pick which folders this user can see.")
        }
    }

    private var canSaveUsername: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != account.dto.name
    }

    private var canSetPassword: Bool {
        !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var bitrateOptions: [Int] {
        var values = RemoteBitrateLimit.allCases.map(\.rawValue)
        let current = draft.remoteClientBitrateLimit
        if !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    private var administratorBinding: Binding<Bool> {
        Binding(
            get: { draft.isAdministrator },
            set: { newValue in
                if !newValue, draft.isAdministrator {
                    pendingAdministrator = false
                    return
                }
                draft.isAdministrator = newValue
                Task { await savePolicy() }
            }
        )
    }

    private var subtitleManagementBinding: Binding<Bool> {
        Binding(
            get: { draft.enableSubtitleManagement },
            set: { newValue in
                draft.enableSubtitleManagement = newValue
                Task { await savePolicy() }
            }
        )
    }

    private var disabledBinding: Binding<Bool> {
        Binding(
            get: { draft.isDisabled },
            set: { newValue in
                if newValue, !draft.isDisabled {
                    confirmDisable = true
                    return
                }
                draft.isDisabled = newValue
                Task { await savePolicy() }
            }
        )
    }

    private var allFoldersBinding: Binding<Bool> {
        Binding(
            get: { draft.enableAllFolders },
            set: { newValue in
                draft.enableAllFolders = newValue
                Task { await savePolicy() }
            }
        )
    }

    private func unratedBinding(_ item: UnratedItem) -> Binding<Bool> {
        Binding(
            get: { draft.blockUnratedItems.contains(item) },
            set: { isOn in
                if isOn {
                    draft.blockUnratedItems.insert(item)
                } else {
                    draft.blockUnratedItems.remove(item)
                }
                Task { await savePolicy() }
            }
        )
    }

    private func folderBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { draft.enabledFolders.contains(id) },
            set: { isOn in
                if isOn {
                    draft.enabledFolders.insert(id)
                } else {
                    draft.enabledFolders.remove(id)
                }
                Task { await savePolicy() }
            }
        )
    }

    private func bitrateTitle(_ bitsPerSecond: Int) -> String {
        RemoteBitrateLimit(rawValue: bitsPerSecond)?.title
            ?? "\(max(1, bitsPerSecond / 1_000)) kbps"
    }

    private func applyRatingSelection(_ id: String) {
        if id == "none" {
            guard draft.maxParentalRating != nil else { return }
            draft.maxParentalRating = nil
            Task { await savePolicy() }
            return
        }
        let value = ratings.first(where: { $0.id == id })?.value
        guard draft.maxParentalRating != value else { return }
        draft.maxParentalRating = value
        Task { await savePolicy() }
    }

    private func loadSupport() async {
        do {
            let admin = try session.userAdminClient()
            async let folderList = admin.mediaFolders()
            async let ratingList = admin.parentalRatings()
            folders = try await folderList
            ratings = try await ratingList
            ratingID = ratings.first(where: { $0.value == draft.maxParentalRating })?.id ?? "none"
            ratingsReady = true
        } catch {
            ratingsReady = true
            report(error, isError: true)
        }
    }

    private func saveUsername() async {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        await run {
            let admin = try session.userAdminClient()
            try await admin.renameUser(account, name: trimmed)
            account.dto.name = trimmed
            if isCurrentUser {
                session.applyRenamedCurrentUser(trimmed)
            }
        }
        await onChanged()
    }

    private func savePolicy() async {
        guard let policy = account.policy else {
            report(ZelefinError.server("This user has no policy on the server."), isError: true)
            return
        }
        await run {
            let admin = try session.userAdminClient()
            try await admin.updatePolicy(userID: account.id, policy: draft.applying(to: policy))
            account.dto.policy = draft.applying(to: policy)
            if isCurrentUser {
                await session.refreshSessionCapabilities()
            }
        }
        await onChanged()
    }

    private func resetPassword() async {
        await run {
            let admin = try session.userAdminClient()
            try await admin.resetPassword(userID: account.id)
        }
    }

    private func setPassword() async {
        guard newPassword == confirmPassword else {
            report(ZelefinError.server("The new passwords do not match."), isError: true)
            return
        }
        await run {
            let admin = try session.userAdminClient()
            try await admin.setPassword(userID: account.id, newPassword: newPassword)
            newPassword = ""
            confirmPassword = ""
        }
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
            report(error, isError: true)
            return
        }
        guard let jpeg = ProfileImageEncoder.jpegData(from: image) else {
            pickerItem = nil
            report(ZelefinError.server("Zelefin could not read that photo."), isError: true)
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
            try await session.updateProfileImage(userID: account.id, jpeg: jpeg)
            try await refreshEditedUser()
            report("Profile picture updated.", isError: false)
            await onChanged()
        } catch is CancellationError {
            localAvatar = nil
        } catch {
            localAvatar = nil
            report(error, isError: true)
        }
    }

    private func removePhoto() async {
        isUpdatingPhoto = true
        status = nil
        defer { isUpdatingPhoto = false }
        do {
            try await session.removeProfileImage(userID: account.id)
            localAvatar = nil
            account.dto.primaryImageTag = nil
            try await refreshEditedUser()
            report("Profile picture removed.", isError: false)
            await onChanged()
        } catch {
            report(error, isError: true)
        }
    }

    private func refreshEditedUser() async throws {
        let admin = try session.userAdminClient()
        account = try await admin.user(id: account.id)
        if isCurrentUser {
            localAvatar = nil
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isSaving = true
        status = nil
        defer { isSaving = false }
        do {
            try await work()
            report("Saved.", isError: false)
        } catch {
            report(error, isError: true)
        }
    }

    private func report(_ error: Error, isError: Bool) {
        report(error.localizedDescription, isError: isError)
    }

    private func report(_ message: String, isError: Bool) {
        statusIsError = isError
        status = message
    }
}
