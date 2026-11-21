import SwiftUI

struct CacheSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(CachePreferences.autoRefreshMissingImagesKey) private var autoRefreshMissingImages = false

    @State private var artwork = ArtworkCacheUsage()
    @State private var confirmArtwork: ArtworkImageKind?
    @State private var confirmAllArtwork = false

    var body: some View {
        List {
            Section {
                LabeledContent(AppLanguage.string("ui.total", default: "Total"), value: CacheInventory.formatBytes(artwork.total.bytes))
                ForEach(ArtworkImageKind.allCases) { kind in
                    cacheBucketRow(
                        title: kind.title,
                        bucket: artwork.bucket(for: kind),
                        clearEnabled: !artwork.bucket(for: kind).isEmpty
                    ) {
                        confirmArtwork = kind
                    }
                }
                Button(AppLanguage.string("ui.clear_all_images", default: "Clear All Images"), role: .destructive) {
                    confirmAllArtwork = true
                }
                .disabled(artwork.total.isEmpty)
                Toggle(AppLanguage.string("ui.auto_refresh_missing_images", default: "Auto-refresh missing images"), isOn: $autoRefreshMissingImages)
            } header: {
                Text(AppLanguage.string("ui.images", default: "Images"))
            } footer: {
                Text(AppLanguage.string("Posters, backdrops, and logos stay on this device. Auto-refresh retries artwork this server previously returned as missing.", default: "Posters, backdrops, and logos stay on this device. Auto-refresh retries artwork this server previously returned as missing."))
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: AppLanguage.string("settings.cache", default: "Cache"))
        .task { artwork = ArtworkCache.shared.usage() }
        .confirmationDialog(
            "Clear this image cache?",
            isPresented: Binding(
                get: { confirmArtwork != nil },
                set: { if !$0 { confirmArtwork = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLanguage.string("common.clear", default: "Clear"), role: .destructive) {
                if let confirmArtwork {
                    session.purgeArtworkCache(confirmArtwork)
                    artwork = ArtworkCache.shared.usage()
                }
                confirmArtwork = nil
            }
            Button(AppLanguage.string("common.cancel", default: "Cancel"), role: .cancel) {
                confirmArtwork = nil
            }
        }
        .confirmationDialog(
            "Clear every cached image?",
            isPresented: $confirmAllArtwork,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.string("ui.clear_all_images", default: "Clear All Images"), role: .destructive) {
                session.purgeArtworkCache(nil)
                artwork = ArtworkCache.shared.usage()
            }
            Button(AppLanguage.string("common.cancel", default: "Cancel"), role: .cancel) {}
        }
    }
}

struct MetadataSettingsView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(CachePreferences.autoRefreshMissingMetadataKey) private var autoRefreshMissingMetadata = false

    @State private var metadata = MetadataCacheUsage()
    @State private var confirmMetadata: MetadataCacheFolder?
    @State private var confirmAllMetadata = false
    @State private var isRefreshingMetadata = false

    var body: some View {
        List {
            Section {
                LabeledContent(AppLanguage.string("ui.total", default: "Total"), value: CacheInventory.formatBytes(metadata.total.bytes))
                ForEach(MetadataCacheFolder.allCases) { folder in
                    cacheBucketRow(
                        title: folder.title,
                        bucket: metadata.bucket(for: folder),
                        clearEnabled: !metadata.bucket(for: folder).isEmpty
                    ) {
                        confirmMetadata = folder
                    }
                }
                Button(AppLanguage.string("ui.clear_all_metadata", default: "Clear All Metadata"), role: .destructive) {
                    confirmAllMetadata = true
                }
                .disabled(metadata.total.isEmpty)
                Toggle(AppLanguage.string("ui.auto_refresh_missing_metadata", default: "Auto-refresh missing metadata"), isOn: $autoRefreshMissingMetadata)
                Button(AppLanguage.string("ui.refresh_missing_metadata", default: "Refresh Missing Metadata")) {
                    Task { await refreshMetadata() }
                }
                .disabled(isRefreshingMetadata)
            } header: {
                Text(AppLanguage.string("Saved Home Data", default: "Saved Home Data"))
            } footer: {
                Text(AppLanguage.string("Home rows, library catalogs, and title pages. Auto-refresh pulls anything this device has not cached yet.", default: "Home rows, library catalogs, and title pages. Auto-refresh pulls anything this device has not cached yet."))
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: AppLanguage.string("settings.metadata", default: "Metadata"))
        .task { metadata = CacheInventory.metadataUsage() }
        .onChange(of: autoRefreshMissingMetadata) { _, isOn in
            if isOn {
                Task { await refreshMetadata() }
            }
        }
        .confirmationDialog(
            "Clear this metadata cache?",
            isPresented: Binding(
                get: { confirmMetadata != nil },
                set: { if !$0 { confirmMetadata = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(AppLanguage.string("common.clear", default: "Clear"), role: .destructive) {
                if let confirmMetadata {
                    session.purgeMetadataCache(confirmMetadata)
                    metadata = CacheInventory.metadataUsage()
                }
                confirmMetadata = nil
            }
            Button(AppLanguage.string("common.cancel", default: "Cancel"), role: .cancel) {
                confirmMetadata = nil
            }
        }
        .confirmationDialog(
            "Clear every metadata cache?",
            isPresented: $confirmAllMetadata,
            titleVisibility: .visible
        ) {
            Button(AppLanguage.string("ui.clear_all_metadata", default: "Clear All Metadata"), role: .destructive) {
                session.purgeMetadataCache(nil)
                metadata = CacheInventory.metadataUsage()
            }
            Button(AppLanguage.string("common.cancel", default: "Cancel"), role: .cancel) {}
        }
    }

    private func refreshMetadata() async {
        isRefreshingMetadata = true
        defer { isRefreshingMetadata = false }
        await session.refreshMissingMetadata()
        metadata = CacheInventory.metadataUsage()
    }
}

private func cacheBucketRow(
    title: String,
    bucket: CacheBucket,
    clearEnabled: Bool,
    clear: @escaping () -> Void
) -> some View {
    HStack {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            Text(CacheInventory.formatBytes(bucket.bytes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 8)
        Button(AppLanguage.string("common.clear", default: "Clear"), role: .destructive, action: clear)
            .font(.caption.weight(.bold))
            .disabled(!clearEnabled)
    }
}
