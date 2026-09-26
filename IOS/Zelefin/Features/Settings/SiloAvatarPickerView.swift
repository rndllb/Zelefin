import SwiftUI
import PhotosUI

struct SiloAvatarPickerView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var styleID = SiloProfileAvatars.styles[0].id
    @State private var batch = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var localPreview: UIImage?

    private var profile: SiloHouseholdProfile? {
        session.householdProfiles.first(where: { $0.id == session.session?.profileID })
            ?? session.householdProfiles.first
    }

    private var presets: [SiloProfileAvatars.Preset] {
        SiloProfileAvatars.batch(styleID: styleID, batch: batch)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    styleRow
                    presetGrid
                    if session.siloAvatarUploadEnabled {
                        photosRow
                    } else {
                        Text("This server only keeps preset avatars. Custom photos need avatar storage on the Silo host.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .zelefinSettingsChrome(title: "Profile Picture")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView()
                        .controlSize(.large)
                        .padding(20)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await upload(item) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 16) {
            UserAvatarView(
                url: profile?.avatarURL,
                localImage: localPreview,
                diameter: 72
            )
            .id(session.avatarRevision)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile?.name ?? "Profile")
                    .font(.headline)
                Text("Shown for this household profile.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var styleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SiloProfileAvatars.styles) { style in
                    Button {
                        styleID = style.id
                        batch = 0
                    } label: {
                        Text(style.label)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(style.id == styleID ? Color.primary.opacity(0.16) : Color.primary.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(style.id == styleID ? [.isSelected] : [])
                }
                Button {
                    batch += 1
                } label: {
                    Label("More", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .disabled(isSaving)
            }
        }
    }

    private var presetGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 72, maximum: 92), spacing: 10)],
            spacing: 10
        ) {
                ForEach(presets) { preset in
                    Button {
                        Task { await select(preset) }
                    } label: {
                        SiloAvatarPresetThumb(
                            url: preset.previewURL,
                            isSelected: isCurrent(preset)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isSaving)
                    .accessibilityLabel(preset.label)
                    .accessibilityAddTraits(isCurrent(preset) ? [.isSelected] : [])
                }
        }
    }

    private var photosRow: some View {
        PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
            Label("Choose Photo", systemImage: "photo.on.rectangle")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .disabled(isSaving)
        .accessibilityLabel("Upload a photo")
    }

    private func isCurrent(_ preset: SiloProfileAvatars.Preset) -> Bool {
        SiloProfileAvatars.presetID(from: profile?.avatar) == preset.id
    }

    private func select(_ preset: SiloProfileAvatars.Preset) async {
        if isCurrent(preset) {
            dismiss()
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await session.updateSiloAvatarPreset(preset.id)
            localPreview = nil
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        let image: UIImage
        do {
            image = try await PickedProfileImage.load(item)
        } catch is CancellationError {
            pickerItem = nil
            return
        } catch {
            pickerItem = nil
            errorMessage = error.localizedDescription
            return
        }
        guard let jpeg = ProfileImageEncoder.jpegData(from: image) else {
            pickerItem = nil
            errorMessage = "Zelefin could not read that photo."
            return
        }
        isSaving = true
        errorMessage = nil
        localPreview = image
        defer {
            isSaving = false
            pickerItem = nil
        }
        do {
            try await session.updateSiloAvatar(jpeg: jpeg)
            dismiss()
        } catch is CancellationError {
            localPreview = nil
        } catch {
            localPreview = nil
            errorMessage = error.localizedDescription
        }
    }

}

private struct SiloAvatarPresetThumb: View {
    var url: URL
    var isSelected: Bool
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.08))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 3)
        }
        .task(id: url.absoluteString) {
            image = await ArtworkCache.shared.load(from: url, persist: false)
        }
    }
}
