import SwiftUI
import UIKit

struct SearchView: View {
    @State private var term = ""
    @State private var scope: SearchScope = .library
    @FocusState private var searchFieldFocused: Bool
    @State private var searchChromeHeight: CGFloat = 68
    @Environment(\.tabBarPlacement) private var tabBarPlacement
    @State private var headerVisible = true

    private var usesPadTopChrome: Bool {
        UIDevice.current.userInterfaceIdiom.isLargeScreen
    }

    private var isSearchSessionActive: Bool {
        searchFieldFocused
            || !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSidebarVisible: Bool {
        tabBarPlacement == .sidebar
    }

    private var searchChromeTopInset: CGFloat {
        SearchChromeMetrics.topInset(
            statusBarHeight: ScreenInsets.top,
            usesPadTopChrome: usesPadTopChrome,
            isSidebarVisible: isSidebarVisible
        )
    }

    private var reservedHeaderHeight: CGFloat {
        searchChromeTopInset + searchChromeHeight
    }

    var body: some View {
        ZStack(alignment: .top) {
            SearchPage(
                term: $term,
                isSearchPresented: isSearchSessionActive,
                scope: scope,
                reservedHeaderHeight: reservedHeaderHeight,
                headerVisible: $headerVisible,
                onDismissKeyboard: {
                    guard searchFieldFocused else { return }
                    dismissSearchKeyboard()
                }
            )

            SearchTabChrome(
                term: $term,
                scope: $scope,
                searchFieldFocused: $searchFieldFocused,
                isSearchSessionActive: isSearchSessionActive,
                showsProfile: RootPageChrome.showsTitle && !isSidebarVisible,
                headerVisible: headerVisible,
                fieldHeight: $searchChromeHeight,
                onCancel: endSearch
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .padding(.top, searchChromeTopInset)

            if !RootPageChrome.showsTitle {
                FloatingPageHeader()
                    .padding(.top, ScreenInsets.top)
                    .transition(.opacity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .animation(ZelefinMotion.sidebarChrome, value: searchChromeTopInset)
        .animation(ZelefinMotion.sidebarChrome, value: isSidebarVisible)
        .onChange(of: searchFieldFocused) { _, focused in
            if !focused, term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                dismissSearchKeyboard()
            }
        }
    }

    private func endSearch() {
        term = ""
        headerVisible = true
        dismissSearchKeyboard()
    }

    private func dismissSearchKeyboard() {
        searchFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

private struct SearchTabChrome: View {
    @Binding var term: String
    @Binding var scope: SearchScope
    @FocusState.Binding var searchFieldFocused: Bool
    var isSearchSessionActive: Bool
    var showsProfile: Bool
    var headerVisible: Bool
    @Binding var fieldHeight: CGFloat
    var onCancel: () -> Void

    private var showsScopeBar: Bool {
        UIDevice.current.userInterfaceIdiom.isLargeScreen || searchFieldFocused
    }

    private var showsTitleRow: Bool {
        RootPageChrome.showsTitle && !isSearchSessionActive
    }

    private var showsFieldProfile: Bool {
        guard showsProfile else { return false }
        if !RootPageChrome.showsTitle { return true }
        return isSearchSessionActive
    }

    private var chromeVisible: Bool {
        headerVisible || isSearchSessionActive
    }

    var body: some View {
        VStack(spacing: 10) {
            if showsTitleRow {
                HStack(spacing: 12) {
                    Text("Search")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 0)
                    if showsProfile {
                        ProfileMenu(diameter: 45)
                    }
                }
                .opacity(headerVisible ? 1 : 0)
                .offset(y: headerVisible ? 0 : -10)
                .allowsHitTesting(headerVisible)
                .accessibilityHidden(!headerVisible)
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                    TextField(
                        "",
                        text: $term,
                        prompt: Text(scope.searchPrompt).foregroundStyle(.white.opacity(0.45))
                    )
                    .focused($searchFieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.webSearch)
                    .submitLabel(.search)
                    .background(SearchFieldInputConfigurator())
                    .foregroundStyle(.white)
                    .tint(.white)
                    if !term.isEmpty {
                        Button {
                            term = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .zelefinLiquidGlassCapsule(interactive: false)

                if isSearchSessionActive {
                    Button {
                        term = ""
                        searchFieldFocused = false
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 46, height: 46)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .zelefinLiquidGlassCircle()
                    .zIndex(1)
                    .accessibilityLabel("Cancel search")
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }

                if showsFieldProfile {
                    ProfileMenu(diameter: 45)
                        .transition(.opacity.combined(with: .scale(scale: 0.86)))
                }
            }
            .opacity(chromeVisible ? 1 : 0)
            .offset(y: chromeVisible ? 0 : -10)
            .allowsHitTesting(chromeVisible)
            .accessibilityHidden(!chromeVisible)

            if showsScopeBar {
                SearchScopeBar(scope: $scope)
                    .opacity(chromeVisible ? 1 : 0)
                    .offset(y: chromeVisible ? 0 : -10)
                    .allowsHitTesting(chromeVisible)
                    .accessibilityHidden(!chromeVisible)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, isSearchSessionActive ? 8 : 0)
        .padding(.bottom, showsScopeBar ? 4 : 12)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            guard abs(fieldHeight - height) > 0.5 else { return }
            fieldHeight = height
        }
        .animation(.smooth(duration: 0.25), value: isSearchSessionActive)
        .animation(.smooth(duration: 0.22), value: headerVisible)
        .animation(.smooth(duration: 0.22), value: chromeVisible)
        .animation(.easeInOut(duration: 0.22), value: searchFieldFocused)
        .animation(ZelefinMotion.sidebarChrome, value: showsProfile)
    }
}

private struct SearchScopeBar: View {
    @Binding var scope: SearchScope
    @Namespace private var selection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SearchScope.allCases) { option in
                Button {
                    withAnimation(.smooth(duration: 0.22)) { scope = option }
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(scope == option ? Color.white : Color.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background {
                            if scope == option {
                                Capsule(style: .continuous)
                                    .fill(Color.black.opacity(0.32))
                                    .matchedGeometryEffect(id: "scope", in: selection)
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == option ? .isSelected : [])
            }
        }
        .padding(3)
        .zelefinLiquidGlassCapsule(interactive: false)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search source")
    }
}

/// Keeps the keyboard candidate bar from laying out at zero width the first time Search appears.
private struct SearchFieldInputConfigurator: UIViewRepresentable {
    func makeUIView(context: Context) -> ConfigView { ConfigView() }
    func updateUIView(_ uiView: ConfigView, context: Context) { uiView.configure() }

    final class ConfigView: UIView {
        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            backgroundColor = .clear
            configure()
        }

        func configure() {
            DispatchQueue.main.async { [weak self] in
                guard let field = self?.nearestTextField() else { return }
                field.autocorrectionType = .no
                field.spellCheckingType = .no
                field.smartQuotesType = .no
                field.smartDashesType = .no
                field.smartInsertDeleteType = .no
                if #available(iOS 17.0, *) {
                    field.inlinePredictionType = .no
                }
            }
        }

        private func nearestTextField() -> UITextField? {
            var view: UIView? = superview
            while let current = view {
                if let field = current.firstDescendantTextField() { return field }
                view = current.superview
            }
            return nil
        }
    }
}

private extension UIView {
    func firstDescendantTextField() -> UITextField? {
        if let field = self as? UITextField { return field }
        for child in subviews {
            if let field = child.firstDescendantTextField() { return field }
        }
        return nil
    }
}

@MainActor
enum SearchFieldWarmup {
    private static var didWarm = false

    static func perform() {
        guard !didWarm else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.flatMap(\.windows).first else { return }
        didWarm = true
        let field = UITextField(frame: .zero)
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        if #available(iOS 17.0, *) {
            field.inlinePredictionType = .no
        }
        field.inputView = UIView(frame: .zero)
        field.isHidden = true
        window.addSubview(field)
        field.becomeFirstResponder()
        field.resignFirstResponder()
        field.removeFromSuperview()
    }
}

enum SearchChromeMetrics {
    /// Space the iPad floating top tab bar occupies below the status bar.
    static var topTabBarClearance: CGFloat { RootPageChrome.padTopTabBarClearance }

    static func topInset(
        statusBarHeight: CGFloat,
        usesPadTopChrome: Bool,
        isSidebarVisible: Bool
    ) -> CGFloat {
        guard usesPadTopChrome, !isSidebarVisible else {
            return statusBarHeight
        }
        return statusBarHeight + topTabBarClearance
    }
}

enum SearchScope: String, CaseIterable, Identifiable, Hashable, Sendable {
    case library
    case discover

    var id: String { rawValue }

    var title: String {
        switch self {
        case .library: "Library"
        case .discover: "Discover"
        }
    }

    var searchPrompt: String {
        switch self {
        case .library: "Shows, Movies, and More"
        case .discover: "Request movies and shows"
        }
    }
}

enum SearchGenreGrid {
    static let spacing: CGFloat = 12
    static let horizontalInset: CGFloat = 36

    static func columnCount(gridWidth _: CGFloat, isRegularWidth: Bool, isPortrait: Bool) -> Int {
        if !isRegularWidth { return 3 }
        if isPortrait { return 5 }
        return 7
    }

    /// Window orientation, not content width — opening the sidebar must not flip 7 columns to 5.
    @MainActor
    static func isWindowPortrait() -> Bool? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        switch scene?.interfaceOrientation {
        case .portrait, .portraitUpsideDown:
            return true
        case .landscapeLeft, .landscapeRight:
            return false
        default:
            return nil
        }
    }
}

private struct SearchGenreTile: View {
    let genre: MediaItem
    var compact = false

    var body: some View {
        Color.clear
            .aspectRatio(1 / 1.52, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    GenrePosterCard(
                        title: genre.name,
                        width: geo.size.width,
                        height: geo.size.height,
                        cornerRadius: compact ? 8 : 10
                    )
                }
            }
    }
}

private struct SearchPage: View {
    @Environment(SessionStore.self) private var session
    @Binding var term: String
    var isSearchPresented: Bool
    var scope: SearchScope
    var reservedHeaderHeight: CGFloat
    var headerVisible: Binding<Bool>? = nil
    var onDismissKeyboard: (() -> Void)? = nil

    @State private var hits: [LibrarySearchHit] = []
    @State private var seerrResults: [SeerrTitle] = []
    @State private var recents: [MediaItem] = SearchHistoryStore.load()
    @State private var genres: [MediaItem] = []
    @State private var isLoadingResults = false
    @State private var requestTitle: SeerrTitle?
    @State private var discoverHome = SeerrDiscoverHome()
    @State private var isLoadingDiscover = false
    @State private var discoverError: String?
    @State private var playingItem: MediaItem?
    @State private var playbackError: String?
    @State private var subtitleSearchItem: MediaItem?
    @State private var scrollDistance: CGFloat = 0
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearchActive: Bool {
        isSearchPresented || !trimmedTerm.isEmpty
    }

    private var genreColumnCount: Int {
        SearchGenreGrid.columnCount(
            gridWidth: 0,
            isRegularWidth: sizeClass == .regular,
            isPortrait: SearchGenreGrid.isWindowPortrait() ?? (sizeClass != .regular)
        )
    }

    private var genreColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: SearchGenreGrid.spacing), count: genreColumnCount)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: reservedHeaderHeight)
                    .accessibilityHidden(true)
                    .animation(ZelefinMotion.sidebarChrome, value: reservedHeaderHeight)
                Group {
                    if scope == .discover {
                        if session.isDiscoverAvailable {
                            discoverContent
                        } else {
                            ContentUnavailableView(
                                "Sign In to Seerr",
                                systemImage: "sparkles.rectangle.stack",
                                description: Text("Add Seerr in Settings to request movies and shows.")
                            )
                            .padding(.top, 24)
                        }
                    } else if isSearchActive {
                        libraryContent
                    } else {
                        genreGrid
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: ScrollSample.self, of: { geometry in
            ScrollSample(
                offset: geometry.contentOffset.y,
                distanceFromBottom: RootPageChrome.distanceFromBottom(geometry)
            )
        }) { oldSample, sample in
            let next = max(0, sample.offset)
            if abs(next - scrollDistance) > 0.5 {
                scrollDistance = next
            }
            if let headerVisible {
                let visible = RootPageChrome.headerVisible(
                    offset: next,
                    previousOffset: max(0, oldSample.offset),
                    wasVisible: headerVisible.wrappedValue,
                    distanceFromBottom: sample.distanceFromBottom
                )
                if visible != headerVisible.wrappedValue, sample.distanceFromBottom > 80 {
                    withAnimation(.smooth(duration: 0.22)) {
                        headerVisible.wrappedValue = visible
                    }
                }
            }
            if sample.offset - oldSample.offset > 24 {
                onDismissKeyboard?()
            }
        }
        .simultaneousGesture(
            TapGesture().onEnded { onDismissKeyboard?() }
        )
        .task {
            await loadGenres()
        }
        .task(id: session.homeLayout.sections.first(where: { $0.id == "genres" })?.items.map(\.id)) {
            await loadGenres()
        }
        .task(id: "\(scope.rawValue)|\(term)") {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await search(term)
        }
        .task(id: scope) {
            if scope == .discover {
                await loadDiscover()
            }
        }
        .sheet(item: $requestTitle) { title in
            NavigationStack {
                SeerrRequestView(title: title) {
                    markRequested(title)
                }
            }
        }
        .presentsPlayerFromRoot($playingItem)
        .openSubtitlesSearch(item: $subtitleSearchItem)
        .alert("Playback", isPresented: Binding(
            get: { playbackError != nil },
            set: { if !$0 { playbackError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(playbackError ?? "")
        }
    }

    @ViewBuilder
    private var libraryContent: some View {
        if trimmedTerm.isEmpty {
            recentsSection
        } else if isLoadingResults && hits.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if hits.isEmpty {
            ContentUnavailableView.search(text: trimmedTerm)
                .padding(.top, 24)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(hits) { hit in
                    searchHitRow(hit)
                }
            }
        }
    }

    @ViewBuilder
    private var discoverContent: some View {
        if trimmedTerm.isEmpty {
            SeerrDiscoverHomeView(home: $discoverHome, isLoading: isLoadingDiscover) { title in
                handleRequest(title)
            }
        } else if isLoadingResults && seerrResults.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else if let discoverError {
            ContentUnavailableView(
                "Couldn’t Search",
                systemImage: "exclamationmark.triangle",
                description: Text(discoverError)
            )
            .padding(.top, 24)
        } else if seerrResults.isEmpty {
            ContentUnavailableView.search(text: trimmedTerm)
                .padding(.top, 24)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(seerrResults) { title in
                    SeerrRequestRow(title: title) {
                        handleRequest(title)
                    }
                }
            }
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recently Searched")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                if !recents.isEmpty {
                    Button("Clear") {
                        SearchHistoryStore.clear()
                        recents = []
                    }
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if recents.isEmpty {
                Text("Titles you open from Search show up here.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                ForEach(recents) { item in
                    searchRow(item, isRecent: true)
                }
            }
        }
    }

    private var genreGrid: some View {
        LazyVGrid(columns: genreColumns, spacing: SearchGenreGrid.spacing) {
            ForEach(GenreOrder.shuffled(genres, name: \.name)) { genre in
                NavigationLink {
                    CatalogGridView(title: genre.name, query: .genre(genre.id))
                } label: {
                    SearchGenreTile(genre: genre, compact: genreColumnCount >= 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, SearchGenreGrid.horizontalInset / 2)
        .padding(.top, 8)
        .geometryGroup()
    }

    private func searchRow(_ item: MediaItem, isRecent: Bool) -> some View {
        HStack(spacing: 14) {
            NavigationLink {
                ItemDetailView(item: item)
                    .onAppear { recordRecent(item) }
            } label: {
                HStack(spacing: 14) {
                    PosterImage(url: session.library?.primaryURL(for: item))
                        .frame(width: 52, height: 78)
                        .posterCard(cornerRadius: 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(item.searchListSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button("Play", systemImage: "play.fill") {
                    play(item)
                }
                NavigationLink("View Details") {
                    ItemDetailView(item: item)
                }
                if item.kind == .movie || item.kind == .episode {
                    TitlePlaybackMenus(
                        item: item,
                        onAddSubtitles: { subtitleSearchItem = item }
                    )
                } else if session.shouldShowAddSubtitles(for: item) {
                    Button("Add Subtitles", systemImage: "captions.bubble") {
                        subtitleSearchItem = item
                    }
                }
                if isRecent {
                    Button("Remove", systemImage: "trash", role: .destructive) {
                        SearchHistoryStore.remove(id: item.id)
                        recents = SearchHistoryStore.load()
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 32, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, 82)
        }
    }

    @ViewBuilder
    private func searchHitRow(_ hit: LibrarySearchHit) -> some View {
        HStack(spacing: 14) {
            NavigationLink {
                searchDestination(hit)
            } label: {
                HStack(spacing: 14) {
                    PosterImage(url: searchImageURL(hit))
                        .frame(width: 52, height: 78)
                        .posterCard(cornerRadius: 6)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        if let subtitle = hit.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, 82)
        }
    }

    @ViewBuilder
    private func searchDestination(_ hit: LibrarySearchHit) -> some View {
        switch hit.kind {
        case let .title(kind):
            switch kind {
            case .playlist:
                PlaylistDetailView(playlist: hit.recentItem(kind: kind))
            case .photo:
                PhotoViewerView(item: hit.recentItem(kind: kind))
            default:
                ItemDetailView(itemID: hit.id)
                    .onAppear {
                        recordRecent(hit.recentItem(kind: kind))
                    }
            }
        case .person:
            PersonDetailView(personID: hit.id, name: hit.name, imageTag: hit.imageTag)
        case .genre:
            CatalogGridView(title: hit.name, query: .genre(hit.id))
        case .studio:
            CatalogGridView(title: hit.name, query: .studio(hit.id))
        }
    }

    private func searchImageURL(_ hit: LibrarySearchHit) -> URL? {
        session.library?.searchHitImageURL(hit)
    }

    private func loadGenres() async {
        if let cached = session.homeLayout.sections.first(where: { $0.id == "genres" })?.items, !cached.isEmpty {
            genres = cached
            return
        }
        genres = await session.library?.genresSectionIgnoringErrors()?.items ?? []
    }

    private func loadDiscover() async {
        guard let client = PluginSettings.seerrClient else { return }
        if !discoverHome.isEmpty { return }
        isLoadingDiscover = true
        defer { isLoadingDiscover = false }
        discoverHome = await client.discoverHome()
    }

    private func search(_ newValue: String) async {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            hits = []
            seerrResults = []
            discoverError = nil
            isLoadingResults = false
            return
        }
        isLoadingResults = true
        if scope == .discover {
            hits = []
            do {
                if let client = PluginSettings.seerrClient {
                    seerrResults = try await client.search(term: trimmed)
                } else {
                    seerrResults = []
                }
                discoverError = nil
            } catch {
                seerrResults = []
                discoverError = error.localizedDescription
            }
        } else {
            seerrResults = []
            discoverError = nil
            hits = (try? await session.library?.searchLibrary(trimmed)) ?? []
        }
        isLoadingResults = false
    }

    private func handleRequest(_ title: SeerrTitle) {
        guard !title.isInJellyfin(catalog: session.tmdbCatalog) else { return }
        requestTitle = title
    }

    private func markRequested(_ title: SeerrTitle) {
        if let index = seerrResults.firstIndex(where: { $0.id == title.id }) {
            seerrResults[index].availability = .pending
        }
        discoverHome.markRequested(title)
    }

    private func recordRecent(_ item: MediaItem) {
        SearchHistoryStore.record(item)
        recents = SearchHistoryStore.load()
    }

    private func play(_ item: MediaItem) {
        recordRecent(item)
        if session.playIfSyncPlay(item) { return }
        playingItem = item
    }
}

struct SeerrRequestRow: View {
    @Environment(SessionStore.self) private var session
    let title: SeerrTitle
    var onRequest: () -> Void

    private var isInJellyfin: Bool {
        title.isInJellyfin(catalog: session.tmdbCatalog)
    }

    private var isFullyOnServer: Bool {
        title.availability == .available || (title.kind == .movie && isInJellyfin)
    }

    private var canRequestNow: Bool {
        title.canRequest && !isFullyOnServer
    }

    var body: some View {
        Group {
            if isFullyOnServer {
                row
            } else {
                Button(action: onRequest) { row }
                    .buttonStyle(.plain)
            }
        }
    }

    private var row: some View {
        HStack(spacing: 14) {
                PosterImage(url: title.posterURL)
                    .frame(width: 52, height: 78)
                    .overlay(alignment: .topTrailing) {
                        if isInJellyfin {
                            JellyfinLibraryMark()
                                .font(.system(size: 16, weight: .bold))
                                .padding(3)
                        }
                    }
                    .posterCard(cornerRadius: 6)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(isFullyOnServer ? "In Library" : (title.review == .pendingApproval ? "Pending" : title.availability.buttonTitle))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canRequestNow ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(
                        canRequestNow ? Color.white : Color.white.opacity(0.18),
                        in: Capsule()
                    )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.leading, 82)
        }
    }

    private var subtitle: String {
        var parts = [title.kind == .movie ? "Movie" : "Show"]
        if let year = title.year {
            parts.append("\(year)")
        }
        return parts.joined(separator: " · ")
    }
}
