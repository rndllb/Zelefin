import SwiftUI

struct DownloadedItemsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    private var rows: [DownloadLibraryRow] {
        downloads.libraryRows(for: session.session)
    }

    private var inFlight: [DownloadProgress] {
        downloads.activeTransfers(for: session.session)
    }

    var body: some View {
        Group {
            if rows.isEmpty && inFlight.isEmpty {
                ContentUnavailableView(
                    "No Downloads",
                    systemImage: "arrow.down.circle",
                    description: Text("Movies and episodes you download will show up here for offline playback.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(inFlight) { transfer in
                            if let title = transfer.item {
                                NavigationLink {
                                    ItemDetailView(item: title)
                                } label: {
                                    FillingPortraitPoster(
                                        item: title,
                                        imageURL: session.library?.primaryURL(for: title)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ForEach(rows) { row in
                            NavigationLink {
                                ItemDetailView(item: row.title)
                            } label: {
                                FillingPortraitPoster(
                                    item: row.title,
                                    imageURL: downloads.posterURL(
                                        for: row.title,
                                        account: session.session,
                                        remote: session.library?.primaryURL(for: row.title)
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove Download", systemImage: "trash", role: .destructive) {
                                    downloads.remove(row: row, account: session.session)
                                }
                            }
                            .accessibilityHint(row.kind == .series ? "\(row.episodeCount) episodes" : "")
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Downloaded")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
