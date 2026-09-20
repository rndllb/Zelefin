import SwiftUI

struct CacheSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(CachePreferences.autoRefreshMissingImagesKey) private var autoRefreshMissingImages = false
    @AppStorage(CachePreferences.autoRefreshMissingMetadataKey) private var autoRefreshMissingMetadata = false

    @State private var artwork = ArtworkCacheUsage()
    @State private var metadata = MetadataCacheUsage()
    @State private var confirmArtwork: ArtworkImageKind?
    @State private var confirmAllArtwork = false
    @State private var confirmMetadata: MetadataCacheFolder?
    @State private var confirmAllMetadata = false
    @State private var isRefreshingMetadata = false

    var body: some View {
        List {
            artworkSection
            metadataSection
        }
        .zelefinSettingsChrome(title: "Cache")
        .task { reload() }
        .onChange(of: autoRefreshMissingMetadata) { _, isOn in
            if isOn {
                Task { await refreshMetadata() }
            }
        }
        .confirmationDialog(
            "Clear this image cache?",
            isPresented: Binding(
                get: { confirmArtwork != nil },
                set: { if !$0 { confirmArtwork = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                if let confirmArtwork {
                    session.purgeArtworkCache(confirmArtwork)
                    reload()
                }
                confirmArtwork = nil
            }
            Button("Cancel", role: .cancel) {
                confirmArtwork = nil
            }
        }
        .confirmationDialog(
            "Clear every cached image?",
            isPresented: $confirmAllArtwork,
            titleVisibility: .visible
        ) {
            Button("Clear All Images", role: .destructive) {
                session.purgeArtworkCache(nil)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "Clear this metadata cache?",
            isPresented: Binding(
                get: { confirmMetadata != nil },
                set: { if !$0 { confirmMetadata = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                if let confirmMetadata {
                    session.purgeMetadataCache(confirmMetadata)
                    reload()
                }
                confirmMetadata = nil
            }
            Button("Cancel", role: .cancel) {
                confirmMetadata = nil
            }
        }
        .confirmationDialog(
            "Clear every metadata cache?",
            isPresented: $confirmAllMetadata,
            titleVisibility: .visible
        ) {
            Button("Clear All Metadata", role: .destructive) {
                session.purgeMetadataCache(nil)
                reload()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var artworkSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsInfoRow(label: "Total", value: CacheInventory.formatBytes(artwork.total.bytes))
                ForEach(ArtworkImageKind.allCases) { kind in
                    SettingsCardDivider()
                    cacheRow(
                        title: kind.title,
                        bucket: artwork.bucket(for: kind),
                        clearEnabled: !artwork.bucket(for: kind).isEmpty
                    ) {
                        confirmArtwork = kind
                    }
                }
                SettingsSecondaryButton(
                    title: "Clear All Images",
                    role: .destructive,
                    enabled: !artwork.total.isEmpty
                ) {
                    confirmAllArtwork = true
                }
                .padding(.top, 16)
                SettingsCardDivider()
                Toggle("Auto-refresh missing images", isOn: $autoRefreshMissingImages)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Images")
        } footer: {
            Text("Posters, backdrops, and logos stay on this device. Auto-refresh retries artwork this server previously returned as missing.")
        }
    }

    private var metadataSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 0) {
                SettingsInfoRow(label: "Total", value: CacheInventory.formatBytes(metadata.total.bytes))
                ForEach(MetadataCacheFolder.allCases) { folder in
                    SettingsCardDivider()
                    cacheRow(
                        title: folder.title,
                        bucket: metadata.bucket(for: folder),
                        clearEnabled: !metadata.bucket(for: folder).isEmpty
                    ) {
                        confirmMetadata = folder
                    }
                }
                SettingsSecondaryButton(
                    title: "Clear All Metadata",
                    role: .destructive,
                    enabled: !metadata.total.isEmpty
                ) {
                    confirmAllMetadata = true
                }
                .padding(.top, 16)
                SettingsCardDivider()
                Toggle("Auto-refresh missing metadata", isOn: $autoRefreshMissingMetadata)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.semibold))
                SettingsPrimaryButton(title: "Refresh Missing Metadata", isBusy: isRefreshingMetadata) {
                    Task { await refreshMetadata() }
                }
                .padding(.top, 16)
            }
            .settingsLoginCard()
            .settingsCardRow()
        } header: {
            Text("Metadata")
        } footer: {
            Text("Home rows, library catalogs, and title pages. Auto-refresh pulls anything this device has not cached yet.")
        }
    }

    private func cacheRow(
        title: String,
        bucket: CacheBucket,
        clearEnabled: Bool,
        clear: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(LoginPalette.primaryText)
                Text(CacheInventory.formatBytes(bucket.bytes))
                    .font(.caption)
                    .foregroundStyle(LoginPalette.secondaryText)
            }
            Spacer(minLength: 8)
            Button("Clear", role: .destructive, action: clear)
                .font(.caption.weight(.bold))
                .disabled(!clearEnabled)
        }
    }

    private func reload() {
        artwork = ArtworkCache.shared.usage()
        metadata = CacheInventory.metadataUsage()
    }

    private func refreshMetadata() async {
        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }
        await session.refreshMissingMetadata()
        reload()
    }
}
