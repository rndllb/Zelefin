import SwiftUI
import UIKit
import UniformTypeIdentifiers
import PhotosUI
import JellyfinAPI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var status: String?
    @State private var statusIsError = false
    @State private var isUpdatingPhoto = false
    @State private var localAvatar: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var tokenVisible = false
    @State private var tokenCopied = false
    @State private var showsSiloAvatarPicker = false
    @State private var pinProfile: SiloProfile?
    @State private var profilePIN = ""
    @State private var switchingProfileID: String?
    @State private var profileError: String?
    @State private var overview: ProfileAccountOverview?
    @State private var overviewError: String?
    @State private var isLoadingOverview = false

    var body: some View {
        Form {
            Section {
                identityHero
            }
            .zelefinRowBackground()

            if session.hasSiloLink, !session.siloProfiles.isEmpty {
                Section {
                    profileStrip
                    if let profileError {
                        Text(profileError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Who’s watching")
                } footer: {
                    Text("Continue Watching, recommendations, and watched flags follow the selected profile.")
                }
                .zelefinRowBackground()
            }

            if isLoadingOverview, overview == nil {
                Section {
                    HStack {
                        ProgressView()
                        Text("Loading account…")
                            .foregroundStyle(.secondary)
                    }
                }
                .zelefinRowBackground()
            }

            if let overviewError, overview == nil {
                Section {
                    SettingsStatusText(text: overviewError, isError: true)
                }
                .zelefinRowBackground()
            }

            accountSection(overview)

            if let overview {
                librariesSection(overview)
                limitsSection(overview)
                capabilitiesSection(overview)
                preferencesSection(overview)
            }

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

        }
        .zelefinSettingsChrome(title: "Profile")
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
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
                let pin = profilePIN
                Task { await switchProfile(profile, pin: pin) }
            }
        } message: {
            Text("This profile is locked.")
        }
        .task {
            if session.hasSiloLink { await session.refreshSiloProfiles() }
            await loadOverview()
        }
        .refreshable { await loadOverview() }
        .sheet(isPresented: $showsSiloAvatarPicker) {
            SiloAvatarPickerView()
        }
    }

    // MARK: Server account overview

    private func accountSection(_ overview: ProfileAccountOverview?) -> some View {
        Section {
            AccountPINControls(status: $status, statusIsError: $statusIsError)
            if let overview {
                LabeledContent("Name", value: overview.displayName)
                LabeledContent("Role", value: overview.role)
                LabeledContent("Password", value: overview.hasPassword ? "Set" : "Not set")
                LabeledContent("Last sign-in", value: ProfileAccountFormatting.absolute(overview.lastLogin))
                LabeledContent("Last active", value: ProfileAccountFormatting.relative(overview.lastActivity))
            }
            if let status {
                SettingsStatusText(text: status, isError: statusIsError)
            }
        } header: {
            Text("Account")
        } footer: {
            Text(
                "A 4–6 digit PIN locks this account on this device so others can’t sign into it. "
                    + "\(AccountSwitchPIN.biometricsName) can unlock it instead of typing the PIN."
            )
        }
        .zelefinRowBackground()
    }

    private func librariesSection(_ overview: ProfileAccountOverview) -> some View {
        Section {
            LabeledContent("Access", value: overview.librariesSummary)
        } header: {
            Text("Libraries")
        }
        .zelefinRowBackground()
    }

    private func limitsSection(_ overview: ProfileAccountOverview) -> some View {
        Section {
            LabeledContent("Maximum rating", value: overview.maxRatingLabel)
            LabeledContent("Unrated titles", value: overview.unratedLabel)
            LabeledContent("Allowed time", value: overview.accessScheduleLabel)
        } header: {
            Text("Limits")
        } footer: {
            Text(overview.limitsFooter)
        }
        .zelefinRowBackground()
    }

    private func capabilitiesSection(_ overview: ProfileAccountOverview) -> some View {
        Section {
            ForEach(overview.capabilities) { capability in
                ProfileCapabilityRow(title: capability.title, isAllowed: capability.isAllowed)
            }
        } header: {
            Text("Capabilities")
        } footer: {
            Text("What this login is allowed to do on \(serverLabel).")
        }
        .zelefinRowBackground()
    }

    private func preferencesSection(_ overview: ProfileAccountOverview) -> some View {
        Section {
            LabeledContent("Audio language", value: overview.audioLanguageLabel)
            ProfileCapabilityRow(title: "Play the default audio track", isAllowed: overview.playDefaultAudio)
            LabeledContent("Subtitle language", value: overview.subtitleLanguageLabel)
            LabeledContent("Subtitles", value: overview.subtitleModeLabel)
            ProfileCapabilityRow(title: "Play next episode automatically", isAllowed: overview.autoPlayNextEpisode)
            ProfileCapabilityRow(title: "Remember audio choices", isAllowed: overview.rememberAudio)
            ProfileCapabilityRow(title: "Remember subtitle choices", isAllowed: overview.rememberSubtitles)
            ProfileCapabilityRow(title: "Hide watched titles in Latest", isAllowed: overview.hideWatchedInLatest)
            NavigationLink("Edit in Playback") {
                PlaybackSettingsView()
            }
        } header: {
            Text("Preferences")
        } footer: {
            Text("Language and autoplay defaults live on the server. Caps and library access are changed from the dashboard.")
        }
        .zelefinRowBackground()
    }

    private func loadOverview() async {
        isLoadingOverview = true
        overviewError = nil
        defer { isLoadingOverview = false }
        do {
            let user = try await session.currentUserDto()
            var ratingNames: [Int: String] = [:]
            if session.isAdministrator, let admin = try? session.userAdminClient() {
                let ratings = (try? await admin.parentalRatings()) ?? []
                for rating in ratings {
                    if let value = rating.value {
                        ratingNames[value] = rating.name
                    }
                }
            }
            overview = ProfileAccountOverview.make(
                user: user,
                libraries: session.libraries,
                ratingNames: ratingNames
            )
        } catch {
            overview = nil
            overviewError = error.localizedDescription
        }
    }

    // MARK: Household / identity

    private var profileStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(session.siloProfiles) { profile in
                    let isCurrent = profile.id == session.currentSiloProfileID
                    Button {
                        selectProfile(profile)
                    } label: {
                        HouseholdProfileTile(
                            profile: profile,
                            isCurrent: isCurrent,
                            isSelected: switchingProfileID == profile.id,
                            size: 76
                        )
                        .opacity(switchingProfileID != nil && switchingProfileID != profile.id ? 0.5 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(switchingProfileID != nil || isCurrent)
                    .accessibilityLabel(isCurrent ? "\(profile.name), watching" : "Switch to \(profile.name)")
                }
            }
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func selectProfile(_ profile: SiloProfile) {
        profileError = nil
        if profile.hasPin {
            profilePIN = ""
            pinProfile = profile
        } else {
            Task { await switchProfile(profile, pin: nil) }
        }
    }

    private func switchProfile(_ profile: SiloProfile, pin: String?) async {
        switchingProfileID = profile.id
        defer {
            switchingProfileID = nil
            pinProfile = nil
            profilePIN = ""
        }
        do {
            try await session.switchSiloProfile(profile, pin: pin)
            await loadOverview()
        } catch {
            profileError = error.localizedDescription
        }
    }

    private var displayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    private var serverLabel: String {
        let name = session.session?.displayServer ?? session.serverName ?? ""
        return name.isEmpty ? "this server" : name
    }

    private var serverAddress: String {
        session.session?.serverURL.absoluteString ?? ""
    }

    private var accessToken: String {
        session.session?.accessToken ?? ""
    }

    private var maskedToken: String {
        guard !accessToken.isEmpty else { return "—" }
        return String(repeating: "•", count: min(28, max(12, accessToken.count)))
    }

    private var canRemovePhoto: Bool {
        guard !session.isSiloServer else { return false }
        return session.session?.userImageTag != nil || localAvatar != nil
    }

    /// Silo's Jellyfin-compatible API can't change pictures; Silo's own sign-in can.
    private var canChangePhoto: Bool {
        !session.isSiloServer || session.hasSiloLink
    }

    private func copyAccessToken() {
        guard !accessToken.isEmpty else { return }
        UIPasteboard.general.string = accessToken
        tokenCopied = true
        statusIsError = false
        status = "Access token copied."
    }

    private var identityHero: some View {
        HStack(alignment: .center, spacing: 16) {
            identityAvatarControl
            VStack(alignment: .leading, spacing: 4) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                if !serverAddress.isEmpty {
                    Text(serverAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                } else {
                    Text("\(serverKindLabel) · \(serverLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if canRemovePhoto {
                    Button("Remove Photo", role: .destructive) {
                        Task { await removePhoto() }
                    }
                    .font(.footnote)
                    .disabled(isUpdatingPhoto)
                }
                if let status {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(statusIsError ? Color.red : .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(displayName), \(serverKindLabel), \(serverLabel)")
    }

    @ViewBuilder
    private var identityAvatarControl: some View {
        if !canChangePhoto {
            profileAvatar
        } else if session.hasSiloLink {
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
    }

    private var serverKindLabel: String {
        session.isSiloServer ? "Silo" : session.isEmbyServer ? "Emby" : "Jellyfin"
    }

    private var profileAvatar: some View {
        ZStack {
            UserAvatarView(url: session.avatarURL, localImage: localAvatar, diameter: 64)
                .id(session.avatarRevision)
            if isUpdatingPhoto {
                Circle()
                    .fill(.black.opacity(0.48))
                    .frame(width: 64, height: 64)
                ProgressView()
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
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

}

private struct ProfileCapabilityRow: View {
    let title: String
    let isAllowed: Bool

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Image(systemName: isAllowed ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(isAllowed ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .accessibilityLabel(isAllowed ? "Allowed" : "Not allowed")
        }
        .accessibilityElement(children: .combine)
    }
}

struct AddAccountView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Server", value: serverLabel)
            } footer: {
                Text(session.isSiloServer
                     ? "Sign in as username#profile to add another household profile on this Silo server."
                     : "New users are added on the server you’re already using.")
            }
            .zelefinRowBackground()

            Section {
                TextField(session.isSiloServer ? "username#profile" : "Username", text: $username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Sign In")
            }
            .zelefinRowBackground()

            Section {
                Button(session.isSiloServer ? "Add Account" : "Add User") {
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
        .zelefinSettingsChrome(title: session.isSiloServer ? "Add Account" : "Add User")
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
            // Drop the previous face immediately so a failed reload can't leave the old user up.
            remoteImage = nil
            await load()
        }
    }

    private func load() async {
        guard localImage == nil else { return }
        guard let url else { return }
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
