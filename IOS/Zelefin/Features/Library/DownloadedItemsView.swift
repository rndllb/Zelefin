import SwiftUI

struct DownloadedItemsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @State private var pendingRemoval: DownloadLibraryRow?
    @State private var removalPrompt: DownloadRemovalPrompt?

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    private var rows: [DownloadLibraryRow] {
        downloads.libraryRows(for: session.session)
    }

    private var entries: [DownloadLibraryEntry] {
        DownloadLibraryEntry.grid(
            active: downloads.activeTransfers(for: session.session),
            rows: rows
        )
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Movies and episodes you download will show up here for offline playback.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(entries) { entry in
                            switch entry {
                            case .active(_, let title):
                                NavigationLink {
                                    ItemDetailView(
                                        item: title,
                                        downloadsOnly: title.kind == .series
                                    )
                                } label: {
                                    FillingPortraitPoster(
                                        item: title,
                                        imageURL: session.library?.primaryURL(for: title)
                                    )
                                }
                                .buttonStyle(.plain)
                            case .stored(let row):
                                NavigationLink {
                                    ItemDetailView(item: row.title, downloadsOnly: row.kind == .series)
                                } label: {
                                    FillingPortraitPoster(
                                        item: row.title,
                                        imageURL: downloads.posterURL(
                                            for: row.title,
                                            account: session.session,
                                            remote: downloads.preferredRemotePoster(
                                                for: row.title,
                                                account: session.session,
                                                library: session.library,
                                                fallback: session.library?.primaryURL(for: row.title)
                                            )
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Remove Download", systemImage: "trash", role: .destructive) {
                                        pendingRemoval = row
                                        removalPrompt = .make(row: row)
                                    }
                                }
                                .accessibilityHint(row.kind == .series ? "\(row.episodeCount) episodes" : "")
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.zelefinPage.ignoresSafeArea())
        .navigationTitle("Downloaded")
        .navigationBarTitleDisplayMode(.inline)
        .downloadRemovalConfirmation($removalPrompt) {
            if let pendingRemoval {
                downloads.remove(row: pendingRemoval, account: session.session)
            }
            pendingRemoval = nil
        }
    }
}
