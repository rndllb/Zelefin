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
    @State private var tokenVisible = false
    @State private var tokenCopied = false

    var body: some View {
        Form {
            Section {
                identityHero
                    .listRowInsets(EdgeInsets(top: 20, leading: 16, bottom: 16, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if session.session != nil {
                Section {
                    LabeledContent("User", value: displayName)
                    LabeledContent("Server", value: session.session?.serverURL.absoluteString ?? serverLabel)
                    accessTokenRow
                } header: {
                    Text("Account")
                } footer: {
                    Text("Your access token authenticates this device to Jellyfin. Copy it only into apps you trust.")
                }
            }

            Section {
                SecureField("Current password", text: $currentPassword)
                    .textContentType(.password)
                SecureField("New password", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("Confirm new password", text: $confirmPassword)
                    .textContentType(.newPassword)
                Button {
                    Task { await savePassword() }
                } label: {
                    HStack {
                        Spacer(minLength: 0)
                        if isSavingPassword {
                            ProgressView()
                        } else {
                            Text("Update Password")
                                .fontWeight(.semibold)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .disabled(!canUpdatePassword || isSavingPassword)
            } header: {
                Text("Password")
            } footer: {
                Text("Saved on \(serverLabel).")
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
                        Label("Add User", systemImage: "person.badge.plus")
                    }
                } else {
                    Button {
                        plus.request(.extraAccounts)
                    } label: {
                        HStack {
                            Label("Add User", systemImage: "person.badge.plus")
                            Spacer(minLength: 8)
                            Image(systemName: "lock.fill")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            } header: {
                Text("Users")
            } footer: {
                Text("Add another person on \(serverLabel). Saved users stay on this device.")
            }
        }
        .zelefinSettingsChrome(title: "Profile")
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item) }
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

    private var canUpdatePassword: Bool {
        !currentPassword.isEmpty && !newPassword.isEmpty && newPassword == confirmPassword
    }

    private var accessToken: String {
        session.session?.accessToken ?? ""
    }

    private var accessTokenRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token")
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
        .padding(.vertical, 2)
    }

    private var maskedToken: String {
        guard !accessToken.isEmpty else { return "—" }
        return String(repeating: "•", count: min(28, max(12, accessToken.count)))
    }

    private func copyAccessToken() {
        guard !accessToken.isEmpty else { return }
        UIPasteboard.general.string = accessToken
        tokenCopied = true
        statusIsError = false
        status = "Access token copied."
    }

    private var identityHero: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                ZStack {
                    UserAvatarView(url: session.avatarURL, localImage: localAvatar, diameter: 118)
                        .padding(5)
                        .zelefinLiquidGlassCircle(interactive: false)
                    if isUpdatingPhoto {
                        Circle()
                            .fill(.black.opacity(0.48))
                            .frame(width: 128, height: 128)
                        ProgressView()
                            .tint(.white)
                    }
                }
                .frame(width: 128, height: 128)
                .accessibilityHidden(true)

                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.white))
                        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                }
                .disabled(isUpdatingPhoto)
                .offset(x: -2, y: -2)
                .accessibilityLabel("Change Profile Picture")
            }

            VStack(spacing: 5) {
                Text(displayName)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(serverLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(displayName), \(serverLabel)")

            if session.session?.userImageTag != nil || localAvatar != nil {
                Button("Remove Photo", role: .destructive) {
                    Task { await removePhoto() }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isUpdatingPhoto)
            }

            if let status {
                Text(status)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(statusIsError ? Color.red : .secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func accountRow(_ account: SavedSession, isCurrent: Bool) -> some View {
        HStack(spacing: 12) {
            UserAvatarView(
                url: session.avatarURL(for: account),
                localImage: isCurrent ? localAvatar : nil,
                diameter: 40
            )
            VStack(alignment: .leading, spacing: 2) {
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
        .padding(.vertical, 4)
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

    var body: some View {
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
                Text("New users are added on the server you’re already using.")
            }

            Section {
                TextField("Username", text: $username)
                    .textContentType(.username)
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
                            Text("Add User")
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
        .zelefinSettingsChrome(title: "Add User")
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
