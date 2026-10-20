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
                LabeledContent("Total", value: CacheInventory.formatBytes(artwork.total.bytes))
                ForEach(ArtworkImageKind.allCases) { kind in
                    cacheBucketRow(
                        title: kind.title,
                        bucket: artwork.bucket(for: kind),
                        clearEnabled: !artwork.bucket(for: kind).isEmpty
                    ) {
                        confirmArtwork = kind
                    }
                }
                Button("Clear All Images", role: .destructive) {
                    confirmAllArtwork = true
                }
                .disabled(artwork.total.isEmpty)
                Toggle("Auto-refresh missing images", isOn: $autoRefreshMissingImages)
            } header: {
                Text("Images")
            } footer: {
                Text("Posters, backdrops, and logos stay on this device. Auto-refresh retries artwork this server previously returned as missing.")
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: "Cache")
        .task { artwork = ArtworkCache.shared.usage() }
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
                    artwork = ArtworkCache.shared.usage()
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
                artwork = ArtworkCache.shared.usage()
            }
            Button("Cancel", role: .cancel) {}
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
                LabeledContent("Total", value: CacheInventory.formatBytes(metadata.total.bytes))
                ForEach(MetadataCacheFolder.allCases) { folder in
                    cacheBucketRow(
                        title: folder.title,
                        bucket: metadata.bucket(for: folder),
                        clearEnabled: !metadata.bucket(for: folder).isEmpty
                    ) {
                        confirmMetadata = folder
                    }
                }
                Button("Clear All Metadata", role: .destructive) {
                    confirmAllMetadata = true
                }
                .disabled(metadata.total.isEmpty)
                Toggle("Auto-refresh missing metadata", isOn: $autoRefreshMissingMetadata)
                Button("Refresh Missing Metadata") {
                    Task { await refreshMetadata() }
                }
                .disabled(isRefreshingMetadata)
            } header: {
                Text("Saved Home Data")
            } footer: {
                Text("Home rows, library catalogs, and title pages. Auto-refresh pulls anything this device has not cached yet.")
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: "Metadata")
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
            Button("Clear", role: .destructive) {
                if let confirmMetadata {
                    session.purgeMetadataCache(confirmMetadata)
                    metadata = CacheInventory.metadataUsage()
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
                metadata = CacheInventory.metadataUsage()
            }
            Button("Cancel", role: .cancel) {}
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
        Button("Clear", role: .destructive, action: clear)
            .font(.caption.weight(.bold))
            .disabled(!clearEnabled)
    }
}
