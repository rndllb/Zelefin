import SwiftUI

struct LibraryView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @AppStorage(LibraryLayoutPreferences.orderKey) private var libraryOrderRaw = ""
    @AppStorage(LibraryLayoutPreferences.hiddenKey) private var libraryHiddenRaw = ""
    @AppStorage(LibraryLayoutPreferences.pageHiddenKey) private var pageHiddenRaw = ""
    @State private var libraries: [MediaLibrary] = []
    @State private var catalog: [MediaLibrary] = []
    @State private var covers: [String: [MediaItem]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var headerVisible = true
    @State private var showsOrganize = false
    @State private var catalogCounts: ServerCatalogCounts?
    @State private var roomCounts: [String: LibraryRoomCounts] = [:]

    private var hiddenPageBlocks: Set<LibraryPageBlock> {
        LibraryLayoutPreferences.hiddenBlocks(from: pageHiddenRaw)
    }

    private var collectionCovers: [MediaItem] {
        guard !hiddenPageBlocks.contains(.collections) else { return [] }
        return session.homeLayout.sections.first(where: { $0.id == "collections" })?.items ?? []
    }

    private var organizedCatalog: [MediaLibrary] {
        LibraryLayoutPreferences.arranged(catalog, orderRaw: libraryOrderRaw)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, libraries.isEmpty {
                ContentUnavailableView(
                    "Couldn’t Load Library",
                    systemImage: "rectangle.stack",
                    description: Text(errorMessage)
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        VStack(alignment: .leading, spacing: 16) {
                            if let catalogCounts, catalogCounts.movies + catalogCounts.shows + catalogCounts.episodes > 0 {
                                LibraryServerStats(counts: catalogCounts)
                            }
                            rooms
                        }
                        if showsJumpRow {
                            jumpRow
                        }
                        if !collectionCovers.isEmpty {
                            collections
                        }
                    }
                    .padding(.top, RootPageChrome.showsTitle ? RootPageChrome.headerRowHeight : 8)
                    .padding(.bottom, 32)
                }
                .scrollClipDisabled()
                .zelefinScrollEdgeBlur()
                .zelefinHeaderScrollVisibility($headerVisible)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            FloatingPageHeader(
                title: "Library",
                isVisible: RootPageChrome.showsTitle ? headerVisible : true,
                liftsIntoPadTabBar: true
            ) {
                Button {
                    showsOrganize = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 45, height: 45)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .zelefinLiquidGlassCircle()
                .accessibilityLabel("Arrange Library")
            }
        }
        .sheet(isPresented: $showsOrganize) {
            NavigationStack {
                LibraryOrganizeView(
                    libraries: organizedCatalog,
                    orderRaw: $libraryOrderRaw,
                    hiddenRaw: $libraryHiddenRaw,
                    pageHiddenRaw: $pageHiddenRaw
                )
            }
            .presentationBackground(Color.black)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .animation(ZelefinMotion.sidebarChrome, value: tabBarPlacement)
        .task {
            if !session.libraries.isEmpty {
                applyCatalog(session.libraries)
                isLoading = false
            }
            await load()
        }
        .onChange(of: session.libraries) { _, next in
            guard !next.isEmpty else { return }
            applyCatalog(next)
            isLoading = false
            errorMessage = nil
            Task { await loadDetails() }
        }
        .onChange(of: libraryOrderRaw) { _, _ in
            applyCatalog(catalog)
        }
        .onChange(of: libraryHiddenRaw) { _, _ in
            applyCatalog(catalog)
            Task { await loadRoomCounts() }
        }
    }

    private var rooms: some View {
        VStack(spacing: 12) {
            ForEach(libraries) { library in
                NavigationLink {
                    LibraryItemsView(library: library)
                } label: {
                    LibraryRoomBand(
                        library: library,
                        covers: covers[library.id] ?? [],
                        showsArtwork: library.libraryKind != .liveTV,
                        countCaption: roomCounts[library.id]?.caption
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var showsJumpRow: Bool {
        visibleJumpBlocks.isEmpty == false
    }

    private var visibleJumpBlocks: [LibraryPageBlock] {
        [LibraryPageBlock.favorites, .downloaded, .genres].filter { !hiddenPageBlocks.contains($0) }
    }

    private var jumpRow: some View {
        HStack(spacing: 10) {
            ForEach(visibleJumpBlocks) { block in
                jumpTile(block)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func jumpTile(_ block: LibraryPageBlock) -> some View {
        switch block {
        case .favorites:
            jumpLink(block.title, systemImage: block.systemImage) {
                CatalogBrowseView(title: "Favorites", libraryKind: .favorites, showsBackButton: true)
            }
        case .downloaded:
            jumpLink(block.title, systemImage: block.systemImage) {
                DownloadedItemsView()
            }
        case .genres:
            jumpLink(block.title, systemImage: block.systemImage) {
                LibraryGenresView()
            }
        case .collections:
            EmptyView()
        }
    }

    private func jumpLink<Destination: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            LibraryJumpTile(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private var collections: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Collections", showsChevron: false)
            LazyVGrid(columns: PosterGridLayout.columns(for: sidebarLayout), spacing: 20) {
                ForEach(collectionCovers.prefix(12)) { item in
                    NavigationLink {
                        CatalogGridView(title: item.name, query: .parent(item.id))
                    } label: {
                        FillingPosterCell { size in
                            LabeledPortraitCard(
                                title: item.browsingCardTitle,
                                imageURL: session.library?.artworkURL(for: item, style: .labeledPortrait),
                                collection: item,
                                width: size.width,
                                height: size.height
                            )
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func eligibleLibraries(from source: [MediaLibrary]) -> [MediaLibrary] {
        var libraries = HomeLayoutPreferences.libraryTabLibraries(source)
        if session.usesSilo {
            libraries.removeAll { $0.libraryKind == .liveTV }
        }
        return libraries
    }

    private func applyCatalog(_ source: [MediaLibrary]) {
        catalog = eligibleLibraries(from: source)
        libraries = LibraryLayoutPreferences.displayed(
            catalog,
            orderRaw: libraryOrderRaw,
            hiddenRaw: libraryHiddenRaw
        )
        seedCovers(for: libraries)
    }

    private func load() async {
        guard let client = session.library else {
            errorMessage = "Not signed in."
            isLoading = false
            return
        }
        async let counts = client.serverCatalogCounts()
        do {
            applyCatalog(try await client.libraries())
            errorMessage = nil
        } catch is CancellationError {
            _ = await counts
            return
        } catch {
            errorMessage = error.localizedDescription
        }
        catalogCounts = await counts
        isLoading = false
        await loadDetails()
    }

    private func loadDetails() async {
        async let covers: Void = loadCovers()
        async let counts: Void = loadRoomCounts()
        _ = await covers
        _ = await counts
    }

    private func loadRoomCounts() async {
        guard let client = session.library else { return }
        let snapshot = libraries
        await withTaskGroup(of: (String, LibraryRoomCounts).self) { group in
            for library in snapshot {
                group.addTask {
                    (library.id, await client.roomCounts(for: library))
                }
            }
            for await (id, counts) in group {
                roomCounts[id] = counts
            }
        }
    }

    private func seedCovers(for rooms: [MediaLibrary]) {
        for library in rooms where library.libraryKind != .liveTV {
            if let existing = covers[library.id], !existing.isEmpty { continue }
            if let items = previewFromHome(library), !items.isEmpty {
                covers[library.id] = Array(items.prefix(8))
            }
        }
    }

    private func previewFromHome(_ library: MediaLibrary) -> [MediaItem]? {
        let sections = session.homeLayout.sections
        if let match = sections.first(where: { $0.id == "library-\(library.id)" }) {
            return match.items
        }
        if library.libraryKind == .shows {
            return sections.first(where: { $0.id == "library-shows" })?.items
        }
        return nil
    }

    private func loadCovers() async {
        guard let client = session.library else { return }
        let snapshot = libraries
        seedCovers(for: snapshot)
        await withTaskGroup(of: (String, [MediaItem]).self) { group in
            for library in snapshot where library.libraryKind != .liveTV {
                group.addTask {
                    (library.id, await client.previewItems(in: library, limit: 8))
                }
            }
            for await (id, items) in group where !items.isEmpty {
                covers[id] = items
            }
        }
    }
}

private struct LibraryServerStats: View {
    let counts: ServerCatalogCounts

    var body: some View {
        HStack(spacing: 0) {
            fact(counts.movies, label: "Movies")
            divider
            fact(counts.shows, label: "Shows")
            divider
            fact(counts.episodes, label: "Episodes")
        }
        .frame(height: 64)
        .background(Color.white.opacity(0.08))
        .posterCard(cornerRadius: 16)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        "\(formatted(counts.movies)) movies, \(formatted(counts.shows)) shows, \(formatted(counts.episodes)) episodes"
    }

    private func fact(_ value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(formatted(value))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.16))
            .frame(width: 1, height: 28)
    }

    private func formatted(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

private struct LibraryRoomBand: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let library: MediaLibrary
    let covers: [MediaItem]
    var showsArtwork = true
    var countCaption: String?

    private var height: CGFloat {
        168 * sidebarLayout.scale
    }

    private var posterSize: CGSize {
        CGSize(width: 76, height: 114).scaled(by: sidebarLayout.scale)
    }

    private var overlap: CGFloat {
        -24 * sidebarLayout.scale
    }

    var body: some View {
        ZStack(alignment: .leading) {
            wash
            LinearGradient(
                colors: [
                    Color.black.opacity(0.82),
                    Color.black.opacity(0.38),
                    Color.black.opacity(0.12)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(library.name)
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    if let caption {
                        Text(caption)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.62))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if showsArtwork {
                    fan
                }
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .posterCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(caption.map { "\(library.name), \($0)" } ?? library.name)
    }

    private var caption: String? {
        if let countCaption, !countCaption.isEmpty { return countCaption }
        switch library.libraryKind {
        case .other:
            return nil
        default:
            let label = library.libraryKind.browseLabel
            if library.name.caseInsensitiveCompare(label) == .orderedSame {
                return nil
            }
            return label
        }
    }

    @ViewBuilder
    private var wash: some View {
        if showsArtwork, let lead = covers.first {
            PosterImage(
                url: session.library?.backdropURL(for: lead) ?? session.library?.primaryURL(for: lead),
                contentMode: .fill
            )
        } else {
            Color.white.opacity(0.08)
        }
    }

    private var fanArt: [MediaItem] {
        let usable = covers.filter { item in
            !item.usesGeneratedCollage && (item.primaryImageTag != nil || item.posterURL != nil)
        }
        return Array((usable.isEmpty ? covers : usable).prefix(4))
    }

    @ViewBuilder
    private var fan: some View {
        let art = fanArt
        if art.isEmpty {
            Image(systemName: library.libraryKind.systemImage)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white.opacity(0.34))
                .frame(width: posterSize.width, height: posterSize.height)
        } else {
            HStack(spacing: overlap) {
                ForEach(Array(art.enumerated()), id: \.element.id) { index, item in
                    PosterImage(url: session.library?.primaryURL(for: item), contentMode: .fill)
                        .frame(width: posterSize.width, height: posterSize.height)
                        .posterCard(cornerRadius: 8)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: -3, y: 2)
                        .zIndex(Double(index))
                }
            }
        }
    }

}

private struct LibraryJumpTile: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title2.weight(.medium))
                .foregroundStyle(.white)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 88)
        .background(Color.white.opacity(0.08))
        .posterCard(cornerRadius: 14)
        .accessibilityLabel(title)
    }
}

private struct LibraryOrganizeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let libraries: [MediaLibrary]
    @Binding var orderRaw: String
    @Binding var hiddenRaw: String
    @Binding var pageHiddenRaw: String
    @State private var rows: [MediaLibrary] = []
    @State private var draggingID: String?
    @State private var dragTranslation: CGFloat = 0

    private let rowStride: CGFloat = 84

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Hold a room and drag it up or down. The eye hides it from Library.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 10) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, library in
                        roomRow(library, index: index)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Also on Library")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("These stay under your rooms. Hide any you don’t need.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(spacing: 10) {
                        ForEach(LibraryPageBlock.allCases) { block in
                            shortcutRow(block)
                        }
                    }
                    .padding(.top, 4)
                }

                Button("Reset arrangement") {
                    orderRaw = ""
                    hiddenRaw = ""
                    pageHiddenRaw = ""
                }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Arrange")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            if rows.isEmpty { rows = libraries }
        }
        .onChange(of: libraries.map(\.id).joined(separator: ",")) { _, _ in
            guard draggingID == nil else { return }
            rows = libraries
        }
        .onChange(of: orderRaw) { _, _ in
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: hiddenRaw) { _, _ in
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: pageHiddenRaw) { _, _ in
            Task { await session.pushDisplayPreferences() }
        }
        .task {
            await session.pullDisplayPreferences()
        }
    }

    private func roomRow(_ library: MediaLibrary, index: Int) -> some View {
        let shown = isShown(library.id)
        let isDragging = draggingID == library.id
        return HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.body.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(dragGesture(for: library.id))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(library.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if !shown {
                    Text("Hidden")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(dragGesture(for: library.id))

            Button {
                setShown(!shown, id: library.id)
            } label: {
                Image(systemName: shown ? "eye" : "eye.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(minHeight: 74)
        .background(Color.white.opacity(shown ? 0.08 : 0.04))
        .posterCard(cornerRadius: 18)
        .scaleEffect(isDragging ? 1.03 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.45 : 0), radius: 16, y: 8)
        .offset(y: rowOffset(for: library.id, index: index))
        .zIndex(isDragging ? 1 : 0)
        .animation(isDragging ? nil : .smooth(duration: 0.22), value: neighborOffset(for: index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? library.name : "\(library.name), hidden")
        .accessibilityHint("Drag to change order")
        .accessibilityAction(named: Text("Move up")) { move(library.id, by: -1) }
        .accessibilityAction(named: Text("Move down")) { move(library.id, by: 1) }
        .accessibilityAction(named: Text(shown ? "Hide" : "Show")) { setShown(!shown, id: library.id) }
    }

    private func shortcutRow(_ block: LibraryPageBlock) -> some View {
        let shown = isBlockShown(block)
        return HStack(spacing: 12) {
            Image(systemName: block.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 28)
            Text(block.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            Button {
                setBlockShown(!shown, block)
            } label: {
                Image(systemName: shown ? "eye" : "eye.slash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 64)
        .background(Color.white.opacity(shown ? 0.08 : 0.04))
        .posterCard(cornerRadius: 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shown ? block.title : "\(block.title), hidden")
        .accessibilityAction(named: Text(shown ? "Hide" : "Show")) { setBlockShown(!shown, block) }
    }

    private func dragGesture(for id: String) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .onChanged { value in
                if draggingID != id {
                    draggingID = id
                    dragTranslation = 0
                }
                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                guard let from = rows.firstIndex(where: { $0.id == id }) else {
                    draggingID = nil
                    dragTranslation = 0
                    return
                }
                let target = targetIndex(from: from)
                if target != from {
                    rows.move(fromOffsets: IndexSet(integer: from), toOffset: target > from ? target + 1 : target)
                    orderRaw = LibraryLayoutPreferences.orderRaw(from: rows)
                }
                dragTranslation = 0
                draggingID = nil
            }
    }

    private func targetIndex(from index: Int) -> Int {
        let shift = Int((dragTranslation / rowStride).rounded())
        return min(max(0, index + shift), max(rows.count - 1, 0))
    }

    private func rowOffset(for id: String, index: Int) -> CGFloat {
        if draggingID == id { return dragTranslation }
        return neighborOffset(for: index)
    }

    private func neighborOffset(for index: Int) -> CGFloat {
        guard let draggingID, let from = rows.firstIndex(where: { $0.id == draggingID }) else { return 0 }
        let target = targetIndex(from: from)
        if from < target, index > from, index <= target { return -rowStride }
        if from > target, index < from, index >= target { return rowStride }
        return 0
    }

    private func move(_ id: String, by delta: Int) {
        guard let from = rows.firstIndex(where: { $0.id == id }) else { return }
        let target = from + delta
        guard rows.indices.contains(target) else { return }
        withAnimation(.smooth(duration: 0.22)) {
            rows.move(fromOffsets: IndexSet(integer: from), toOffset: delta > 0 ? target + 1 : target)
        }
        orderRaw = LibraryLayoutPreferences.orderRaw(from: rows)
    }

    private func isShown(_ id: String) -> Bool {
        !LibraryLayoutPreferences.hiddenIDs(from: hiddenRaw).contains(id)
    }

    private func setShown(_ shown: Bool, id: String) {
        var hidden = LibraryLayoutPreferences.hiddenIDs(from: hiddenRaw)
        if shown {
            hidden.remove(id)
        } else {
            hidden.insert(id)
        }
        hiddenRaw = LibraryLayoutPreferences.hiddenRaw(from: hidden)
    }

    private func isBlockShown(_ block: LibraryPageBlock) -> Bool {
        !LibraryLayoutPreferences.hiddenBlocks(from: pageHiddenRaw).contains(block)
    }

    private func setBlockShown(_ shown: Bool, _ block: LibraryPageBlock) {
        var hidden = LibraryLayoutPreferences.hiddenBlocks(from: pageHiddenRaw)
        if shown {
            hidden.remove(block)
        } else {
            hidden.insert(block)
        }
        pageHiddenRaw = LibraryLayoutPreferences.pageHiddenRaw(from: hidden)
    }
}

struct LibraryGenresView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    @State private var genres: [MediaItem] = []
    @State private var isLoading = true

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            } else if genres.isEmpty {
                ContentUnavailableView(
                    "No Genres",
                    systemImage: "square.grid.2x2",
                    description: Text("Genres from your libraries will show up here.")
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(genres) { genre in
                        NavigationLink {
                            CatalogGridView(title: genre.name, query: .genre(genre.id))
                        } label: {
                            FillingPosterCell { size in
                                GenrePosterCard(
                                    title: genre.name,
                                    width: size.width,
                                    height: size.height
                                )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .zelefinPushedChrome(title: "Genres") { EmptyView() }
        .task { await load() }
    }

    private func load() async {
        if let cached = session.homeLayout.sections.first(where: { $0.id == "genres" })?.items, !cached.isEmpty {
            genres = cached
            isLoading = false
            return
        }
        genres = await session.library?.genresSectionIgnoringErrors()?.items ?? []
        isLoading = false
    }
}

struct LibraryItemsView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.zelefinSidebarLayout) private var sidebarLayout
    let library: MediaLibrary
    @State private var items: [MediaItem] = []
    @State private var isLoading = true
    @State private var query = CatalogBrowseQuery.default
    @State private var options = CatalogFilterOptions()
    @State private var showFilters = false
    @State private var showSort = false
    @State private var indexProgress: CatalogIndexProgress?

    private var columns: [GridItem] {
        PosterGridLayout.columns(for: sidebarLayout)
    }

    var body: some View {
        if library.libraryKind == .liveTV, !session.usesSilo {
            LiveTVView(showsBackButton: true)
        } else {
            catalogBody
        }
    }

    private var catalogBody: some View {
        ScrollView {
            if isLoading && items.isEmpty {
                ProgressView().tint(.white).padding(.top, 80)
            } else if items.isEmpty {
                ContentUnavailableView(
                    query.isDefault ? "No Titles Yet" : "No Matches",
                    systemImage: "rectangle.stack",
                    description: Text(query.isDefault ? "Titles from this library will show up here." : "No titles match these filters.")
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    CatalogIndexBar(progress: indexProgress)
                    LazyVGrid(columns: columns, spacing: 20) {
                        ForEach(items) { item in
                            NavigationLink {
                                LibraryItemRoute(item: item)
                            } label: {
                                FillingPortraitPoster(
                                    item: item,
                                    imageURL: session.library?.primaryURL(for: item)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .zelefinScrollEdgeBlur()
        .navigationTitle(library.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .catalogFilterSortToolbar(
            filterCount: query.activeFilterCount,
            sortTitle: query.sort.title,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .catalogFilterSheets(
            query: $query,
            options: options,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .task { await loadOptions() }
        .task { await load() }
        .onChange(of: query) { _, _ in
            guard !showFilters, !showSort else { return }
            Task { await load() }
        }
        .onChange(of: showFilters) { _, open in
            if !open { Task { await load() } }
        }
        .onChange(of: showSort) { _, open in
            if !open { Task { await load() } }
        }
    }

    private func loadOptions() async {
        guard let client = session.library else { return }
        options = await client.catalogFilterOptions(for: library)
    }

    private func load() async {
        guard let client = session.library else {
            items = []
            isLoading = false
            indexProgress = nil
            return
        }
        items = (try? await client.items(in: library, query: query) { update in
            indexProgress = .listing(loaded: update.items.count, total: update.totalCount)
            guard !update.items.isEmpty else { return }
            items = update.items
            isLoading = false
        }) ?? []
        isLoading = false
        await finishArtwork(for: items, client: client)
    }

    private func finishArtwork(for items: [MediaItem], client: any LibraryServing) async {
        guard PosterPrefetcher.prefetchesPosters(for: library.libraryKind), !items.isEmpty else {
            indexProgress = nil
            return
        }
        let urls = PosterPrefetcher.posterURLs(for: items, library: client)
        await PosterPrefetcher.download(urls) { cached, total in
            if cached >= total {
                indexProgress = nil
            } else {
                indexProgress = .artwork(cached: cached, total: total)
            }
        }
        indexProgress = nil
    }
}
