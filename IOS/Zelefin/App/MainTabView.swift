import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(AppTab.hiddenDefaultsAppliedKey) private var hiddenDefaultsApplied = false
    @AppStorage(AppTab.favoritesHiddenDefaultKey) private var favoritesHiddenDefaultApplied = false
    @AppStorage(AppTab.liveTVHiddenDefaultKey) private var liveTVHiddenDefaultApplied = false
    @AppStorage(AppTab.showsTitlesStorageKey) private var showsTabNames = true
    @AppStorage(AppTab.dockLibrariesStorageKey) private var dockLibraryIDsRaw = ""
    @AppStorage(AppTab.startTabStorageKey) private var startTabRaw = AppTab.home.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @State private var dockSelection: DockSelection = .tab(.home)
    @State private var didResolveStartTab = false
    @AppStorage(LibraryLayoutPreferences.orderKey) private var macLibraryOrderRaw = ""
    @AppStorage(LibraryLayoutPreferences.hiddenKey) private var macLibraryHiddenRaw = ""
    @AppStorage(LibraryLayoutPreferences.pageHiddenKey) private var macLibraryPageHiddenRaw = ""
    @AppStorage(LibraryIcon.choicesStorageKey) private var libraryIconsRaw = ""

    init() {
        // Open on the page the user chose as their launch destination.
        let raw = UserDefaults.standard.string(forKey: AppTab.startTabStorageKey) ?? AppTab.home.rawValue
        _dockSelection = State(initialValue: .tab(AppTab.startTab(from: raw)))
    }

    var body: some View {
        #if targetEnvironment(macCatalyst)
        macSplitView
        #else
        tabView
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// The Mac uses a split view: its sidebar runs the full window height with the close, minimize
    /// and zoom buttons inside it, where the adaptable tab sidebar floats below them.
    private var macSplitView: some View {
        // ZelefinMacBridge keeps the sidebar from collapsing or resizing and hides its button.
        NavigationSplitView {
            // Drawn by hand: Catalyst's sidebar list has a fixed 46 pt row on the Mac, where the TV
            // and Music apps use 32 pt.
            ScrollView {
                // The TV app's layout: Search, Home, and Discover, then everything the iPhone's Library
                // page holds under a Library heading. There's no Library page on the Mac.
                VStack(spacing: 2) {
                    macSidebarRow("Search", systemImage: "magnifyingglass", assetName: "IconsaxSearch", selection: .search)
                    macSidebarRow(AppTab.home.title, systemImage: AppTab.home.systemImage, assetName: AppTab.home.iconAsset, selection: .tab(.home))
                    macSidebarRow("Discover", systemImage: "sparkles", assetName: nil, selection: .discover)

                    macSidebarHeading("Library")
                    macSidebarRow("Recently Added", systemImage: "clock", assetName: nil, selection: .recentlyAdded)
                    ForEach(macLibraries) { library in
                        let icon = macIcon(for: library)
                        macSidebarRow(library.name, systemImage: icon.system, assetName: icon.asset, selection: .library(library.id))
                    }
                    if !macHiddenBlocks.contains(.collections) {
                        macSidebarRow(AppTab.collections.title, systemImage: "square.stack", assetName: AppTab.collections.iconAsset, selection: .tab(.collections))
                    }
                    if !macHiddenBlocks.contains(.favorites) {
                        macSidebarRow(AppTab.favorites.title, systemImage: "heart", assetName: nil, selection: .tab(.favorites))
                    }
                    // The Watchlist is a Jellyfin playlist, and Silo's Jellyfin-compatible API has none.
                    if !macHiddenBlocks.contains(.watchlist), !session.isSiloServer {
                        macSidebarRow(LibraryPageBlock.watchlist.title, systemImage: "text.badge.plus", assetName: nil, selection: .watchlist)
                    }
                    if !macHiddenBlocks.contains(.genres) {
                        macSidebarRow(LibraryPageBlock.genres.title, systemImage: "square.grid.2x2", assetName: nil, selection: .genres)
                    }
                    if !macHiddenBlocks.contains(.downloaded) {
                        macSidebarRow("Downloads", systemImage: "arrow.down.circle", assetName: nil, selection: .downloads)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
            }
            // Removing the sidebar button here would make the split view ignore this width and drop the
            // window buttons out of the sidebar, so ZelefinMacBridge hides it in AppKit instead.
            .navigationSplitViewColumnWidth(229)
            .safeAreaInset(edge: .bottom) {
                ProfileMenu(diameter: 36, showsName: true, nameFont: .system(size: 13, weight: .medium), showsGlassRing: false)
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } detail: {
            NavigationStack {
                // A page still loading can be narrower than the column; black behind it keeps the
                // window's gray from showing around it.
                macDetail(dockSelection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.ignoresSafeArea())
            }
            .id(dockSelection)
            .zelefinSidebarLayout()
        }
        // Picking another page in the sidebar leaves any title or season it had open. Those pages
        // live in the split view's own navigation controller, which keeps them through a SwiftUI
        // rebuild, so it is popped directly. Rebuilding the whole split view instead flashed its
        // default layout and sidebar button on every switch.
        .onChange(of: dockSelection) {
            MacDetailNavigation.popToRoot()
        }
        .modifier(MiniPlayerDockChrome(isEnabled: session.nowPlayingItem != nil))
        .onAppear {
            applyHiddenTabDefaultsIfNeeded()
            resolveStartSelectionIfNeeded()
            dockSelection = macSelection(for: dockSelection)
        }
    }

    /// The server's libraries as the Library page arranges them (its order and hidden list).
    private var macLibraries: [MediaLibrary] {
        LibraryLayoutPreferences.displayed(
            LibraryLayoutPreferences.sidebarLibraries(session.libraries, hidesLiveTV: session.hidesLiveTV),
            orderRaw: macLibraryOrderRaw,
            hiddenRaw: macLibraryHiddenRaw
        )
    }

    private var macHiddenBlocks: Set<LibraryPageBlock> {
        LibraryLayoutPreferences.hiddenBlocks(from: macLibraryPageHiddenRaw)
    }

    private func macIcon(for library: MediaLibrary) -> (system: String, asset: String?) {
        if LibraryIcon.canChoose(library) {
            return ("square.grid.2x2", LibraryIcon.asset(for: library, raw: libraryIconsRaw))
        }
        return switch library.libraryKind {
        case .movies: (AppTab.movies.systemImage, AppTab.movies.iconAsset)
        case .shows: (AppTab.shows.systemImage, AppTab.shows.iconAsset)
        case .liveTV: (AppTab.liveTV.systemImage, AppTab.liveTV.iconAsset)
        default: ("square.grid.2x2", LibraryIcon.defaultAsset(for: library))
        }
    }

    /// Pages that have no sidebar row on the Mac open on the row that holds the same titles.
    private func macSelection(for selection: DockSelection) -> DockSelection {
        switch selection {
        case .tab(.library):
            return .tab(.home)
        case .tab(.movies):
            return macLibraries.first { $0.libraryKind == .movies }.map { .library($0.id) } ?? .tab(.home)
        case .tab(.shows):
            return macLibraries.first { $0.libraryKind == .shows }.map { .library($0.id) } ?? .tab(.home)
        default:
            return selection
        }
    }

    /// Recently added movies and shows from Home's rows, newest first.
    private var macRecentlyAdded: HomeSection {
        var seen = Set<String>()
        let items = session.homeLayout.sections
            .filter { $0.id.hasPrefix("library-") }
            .flatMap(\.items)
            .filter { seen.insert($0.id).inserted }
            .sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
        return HomeSection(id: "mac-recently-added", title: "Recently Added", style: .portrait, items: items)
    }

    private func macSidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .padding(.top, 14)
            .padding(.bottom, 4)
            .accessibilityAddTraits(.isHeader)
    }

    /// The TV app's sidebar metrics: 13 pt text, 18 pt icons, 30 pt rows 2 pt apart.
    private func macSidebarRow(_ title: String, systemImage: String, assetName: String?, selection: DockSelection) -> some View {
        let isSelected = dockSelection == selection
        return Button {
            dockSelection = selection
        } label: {
            HStack(spacing: 10) {
                if assetName == nil {
                    // A symbol's image carries its own margin, so it fits a slightly larger box to match the
                    // Iconsax glyphs beside it.
                    Image(systemName: isSelected && UIImage(systemName: "\(systemImage).fill") != nil ? "\(systemImage).fill" : systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16.75, height: 16.75)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                } else {
                    TabBarIcon(assetName: assetName, systemImage: systemImage, isSelected: isSelected, side: 18)
                }
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            // The app's tint, not `Color.accentColor`: on the Mac that follows the system accent setting.
            .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func macDetail(_ selection: DockSelection) -> some View {
        switch selection {
        case .tab(let tab):
            tabRoot(tab)
        case .library(let id):
            if let library = macLibraries.first(where: { $0.id == id }) {
                LibraryItemsView(library: library)
            }
        case .search:
            SearchView()
        case .discover:
            SearchView(scope: .discover)
        case .recentlyAdded:
            SectionGridView(section: macRecentlyAdded)
        case .watchlist:
            CatalogBrowseView(title: LibraryPageBlock.watchlist.title, libraryKind: .watchlist)
        case .genres:
            LibraryGenresView()
        case .downloads:
            DownloadedItemsView()
        }
    }
    #endif

    private var tabView: some View {
        TabView(selection: $dockSelection) {
            ForEach(dockTabs) { tab in
            Tab(value: DockSelection.tab(tab)) {
                NavigationStack {
                    tabRoot(tab)
                }
                .zelefinSidebarLayout()
            } label: {
                dockLabel(
                    tab.title,
                    systemImage: tab.systemImage,
                    assetName: tab.iconAsset,
                    isSelected: dockSelection == .tab(tab)
                )
            }
                .customizationID(tab.customizationID)
                .customizationBehavior(tab.canHide ? .automatic : .reorderable, for: .sidebar, .tabBar)
            }

            ForEach(dockLibraries) { library in
                Tab(value: DockSelection.library(library.id)) {
                    NavigationStack {
                        CatalogBrowseView(
                            title: library.name,
                            libraryKind: library.libraryKind,
                            libraryID: library.id
                        )
                    }
                    .zelefinSidebarLayout()
                } label: {
                    dockLabel(
                        library.name,
                        systemImage: "square.grid.2x2",
                        assetName: LibraryIcon.asset(for: library, raw: libraryIconsRaw),
                        isSelected: dockSelection == .library(library.id)
                    )
                }
                .customizationID("app.zelefin.library.\(library.id)")
                .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            }

            Tab(value: DockSelection.search, role: .search) {
                NavigationStack {
                    SearchView()
                }
                .zelefinSidebarLayout()
            } label: {
                dockLabel(
                    "Search",
                    systemImage: "magnifyingglass",
                    assetName: "IconsaxSearch",
                    isSelected: dockSelection == .search
                )
            }
            .customizationID("app.zelefin.tab.search")
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
        }
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization(tabCustomizationBinding)
        .tabViewSidebarBottomBar {
            ProfileMenu(diameter: 36, showsName: true)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .modifier(MiniPlayerDockChrome(isEnabled: session.nowPlayingItem != nil))
        .background(TabBarTitleApplier(showsTitles: showsDockTitles, selection: dockSelection))
        .onAppear {
            applyHiddenTabDefaultsIfNeeded()
            resolveStartSelectionIfNeeded()
            TabBarTitleChrome.libraryIcons = dockLibraryIcons
            TabBarTitleChrome.applyAfterRestore(showsTitles: showsDockTitles)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                SearchFieldWarmup.perform()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            TabBarTitleChrome.applyAfterRestore(showsTitles: showsDockTitles)
        }
        .onChange(of: showsDockTitles) { _, showsTitles in
            TabBarTitleChrome.apply(showsTitles: showsTitles)
        }
        .onChange(of: dockLibraryIcons) { _, icons in
            TabBarTitleChrome.libraryIcons = icons
            TabBarTitleChrome.apply(showsTitles: showsDockTitles, selection: dockSelection)
        }
        .onChange(of: dockSelection) { _, selection in
            TabBarTitleChrome.apply(showsTitles: showsDockTitles, selection: selection)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                TabBarTitleChrome.apply(showsTitles: showsDockTitles, selection: selection)
            }
        }
        .background(.clear)
    }

    /// iPad always shows tab names. The dock caption setting is iPhone only.
    private var showsDockTitles: Bool {
        UIDevice.current.userInterfaceIdiom.isLargeScreen || showsTabNames
    }

    private func dockLabel(
        _ title: String,
        systemImage: String,
        assetName: String? = nil,
        isSelected: Bool = false
    ) -> some View {
        Label {
            Text(showsDockTitles ? title : "")
        } icon: {
            TabBarIcon(assetName: assetName, systemImage: systemImage, isSelected: isSelected)
        }
        .accessibilityLabel(title)
    }

    private var tabCustomizationBinding: Binding<TabViewCustomization> {
        Binding(
            get: { tabCustomization },
            set: { tabCustomization = $0 }
        )
    }

    /// If the chosen start page is hidden from the dock, land on Home so launch never opens a missing tab.
    private func resolveStartSelectionIfNeeded() {
        guard !didResolveStartTab else { return }
        didResolveStartTab = true
        guard case let .tab(tab) = dockSelection, tab != .home, !dockTabs.contains(tab) else { return }
        dockSelection = .tab(.home)
    }

    private func applyHiddenTabDefaultsIfNeeded() {
        if !hiddenDefaultsApplied {
            AppTab.applyHiddenDefaults(to: &tabCustomization)
            hiddenDefaultsApplied = true
            favoritesHiddenDefaultApplied = true
            liveTVHiddenDefaultApplied = true
            return
        }
        if !favoritesHiddenDefaultApplied {
            AppTab.hide([.favorites], in: &tabCustomization)
            favoritesHiddenDefaultApplied = true
        }
        if !liveTVHiddenDefaultApplied {
            AppTab.hide([.liveTV], in: &tabCustomization)
            liveTVHiddenDefaultApplied = true
        }
    }

    private var pinnedLibraries: [MediaLibrary] {
        let ids = DockLibraryPreferences.ids(from: dockLibraryIDsRaw)
        return session.libraries.filter { ids.contains($0.id) && DockLibraryPreferences.canPin($0) }
    }

    private var enabledTabs: [AppTab] {
        var ordered = AppTab.ordered(from: tabOrderRaw)
        if session.hidesLiveTV {
            ordered.removeAll { $0 == .liveTV }
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            return ordered
        }
        return ordered.filter { tab in
            !tab.canHide || tabCustomization[sidebarVisibility: tab.customizationID] != .hidden
        }
    }

    private var phoneDock: (tabs: [AppTab], libraries: [MediaLibrary]) {
        PhoneDockLimit.content(tabs: enabledTabs, libraries: pinnedLibraries)
    }

    private var dockTabs: [AppTab] { phoneDock.tabs }

    private var dockLibraries: [MediaLibrary] { phoneDock.libraries }

    /// Pinned libraries whose icon isn't Library's: YouTube ones and anime ones with a picked icon.
    private var dockLibraryIcons: [String: String] {
        var icons: [String: String] = [:]
        for library in dockLibraries {
            let asset = LibraryIcon.asset(for: library, raw: libraryIconsRaw)
            if asset != LibraryIcon.library {
                icons[library.id] = asset
            }
        }
        return icons
    }

    @ViewBuilder
    private func tabRoot(_ tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView()
        case .movies:
            CatalogBrowseView(title: "Movies", libraryKind: .movies)
        case .shows:
            CatalogBrowseView(title: "Shows", libraryKind: .shows)
        case .liveTV:
            LiveTVView()
        case .collections:
            CatalogBrowseView(title: "Collections", libraryKind: .collections)
        case .library:
            LibraryView()
        case .favorites:
            CatalogBrowseView(title: "Favorites", libraryKind: .favorites)
        }
    }
}

#if targetEnvironment(macCatalyst)
private enum MacDetailNavigation {
    @MainActor
    static func popToRoot() {
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows {
                if let root = window.rootViewController {
                    popToRoot(in: root)
                }
            }
        }
    }

    @MainActor
    private static func popToRoot(in controller: UIViewController) {
        if let navigation = controller as? UINavigationController, navigation.viewControllers.count > 1 {
            navigation.popToRootViewController(animated: false)
        }
        for child in controller.children {
            popToRoot(in: child)
        }
    }
}
#endif

private enum DockSelection: Hashable {
    case tab(AppTab)
    case library(String)
    case search
    /// The Mac sidebar's own rows. iPhone and iPad reach Discover from Search and the rest from Library.
    case discover
    case recentlyAdded
    case watchlist
    case genres
    case downloads

    @MainActor
    init?(tab: UITab) {
        let identifier = tab.identifier
        let title = tab.title
        for appTab in AppTab.allCases {
            if identifier.contains(appTab.customizationID) || title == appTab.title {
                self = .tab(appTab)
                return
            }
        }
        if let range = identifier.range(of: "app.zelefin.library.") {
            let libraryID = String(identifier[range.upperBound...])
            if !libraryID.isEmpty {
                self = .library(libraryID)
                return
            }
        }
        if title == "Search" || identifier.localizedCaseInsensitiveContains("search") {
            self = .search
            return
        }
        return nil
    }
}

/// Hides the caption under each dock icon without replacing the tab bar material.
private struct TabBarTitleApplier: UIViewRepresentable {
    var showsTitles: Bool
    var selection: DockSelection

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        Coordinator.showsTitles = showsTitles
        context.coordinator.start()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        Coordinator.showsTitles = showsTitles
        let showsTitles = showsTitles
        DispatchQueue.main.async {
            TabBarTitleChrome.apply(showsTitles: showsTitles)
        }
    }

    @MainActor
    final class Coordinator {
        static var showsTitles = false
        nonisolated(unsafe) private var observer: NSObjectProtocol?

        func start() {
            guard observer == nil else { return }
            observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    TabBarTitleChrome.applyAfterRestore(showsTitles: Coordinator.showsTitles)
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}

@MainActor
private enum TabBarTitleChrome {
    /// Library ID to icon for pinned libraries that don't use Library's icon.
    static var libraryIcons: [String: String] = [:]

    private static var restoreTask: Task<Void, Never>?

    /// SwiftUI puts the 24-point asset back when the app returns. Apply again after that restore.
    static func applyAfterRestore(showsTitles: Bool) {
        apply(showsTitles: showsTitles)
        restoreTask?.cancel()
        restoreTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            apply(showsTitles: showsTitles)
        }
    }

    static func apply(showsTitles: Bool, selection: DockSelection? = nil) {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        var resolved = selection
        for window in windows {
            if let root = window.rootViewController,
               let detected = applyIcons(in: root, selection: selection) {
                resolved = detected
            }
            apply(showsTitles: showsTitles, in: window, selection: resolved)
        }
    }

    @discardableResult
    private static func applyIcons(in controller: UIViewController, selection: DockSelection?) -> DockSelection? {
        var detected = selection
        if let tabs = controller as? UITabBarController {
            if selection == nil, let selected = tabs.selectedTab, let parsed = DockSelection(tab: selected) {
                detected = parsed
            }
            let selectedIdentifier = tabs.selectedTab?.identifier
            for tab in tabs.tabs {
                applyIcon(to: tab, selectedIdentifier: selectedIdentifier, selection: detected)
            }
        }
        for child in controller.children {
            if let childSelection = applyIcons(in: child, selection: detected) {
                detected = childSelection
            }
        }
        if let presented = controller.presentedViewController,
           let presentedSelection = applyIcons(in: presented, selection: detected) {
            detected = presentedSelection
        }
        return detected
    }

    private static func applyIcon(to tab: UITab, selectedIdentifier: String?, selection: DockSelection?) {
        if let group = tab as? UITabGroup {
            for child in group.children {
                applyIcon(to: child, selectedIdentifier: selectedIdentifier, selection: selection)
            }
        }
        guard let base = assetBase(for: tab) else { return }
        let selected = isSelected(base: base, identifier: tab.identifier, title: tab.title, selectedIdentifier: selectedIdentifier, selection: selection)
        // Every tab (Search included) uses the template image so the bar tints it with the accent,
        // selected or not — Search no longer renders as a flat white icon when unselected.
        tab.image = TabBarIconMetrics.image(named: selected ? TabBarIconMetrics.selectedName(for: base) : base)
    }

    /// The search tab keeps showing `selectedImage` after another tab is open. Both images follow the real selection.
    private static func isSelected(
        base: String,
        identifier: String,
        title: String,
        selectedIdentifier: String?,
        selection: DockSelection?
    ) -> Bool {
        if base == "IconsaxSearch" {
            if let selection {
                return selection == .search
            }
            return title == "Search" && identifier == selectedIdentifier
                || identifier.localizedCaseInsensitiveContains("search") && identifier == selectedIdentifier
        }
        if let selection {
            switch selection {
            case .search, .discover, .recentlyAdded, .watchlist, .genres, .downloads:
                return false
            case .tab(let tab):
                return identifier.contains(tab.customizationID) || title == tab.title
            case .library(let id):
                return identifier.contains("app.zelefin.library.\(id)")
            }
        }
        return identifier == selectedIdentifier
    }

    private static func assetBase(for tab: UITab) -> String? {
        assetBase(identifier: tab.identifier, title: tab.title)
    }

    private static func assetBase(identifier: String, title: String) -> String? {
        if identifier.contains("tab.home") || title == "Home" { return "IconsaxHome" }
        if identifier.contains("tab.movies") || title == "Movies" { return "IconsaxMovies" }
        if identifier.contains("tab.shows") || title == "Shows" { return "IconsaxShows" }
        if identifier.contains("tab.liveTV") || title == "Live TV" { return "IconsaxLiveTV" }
        if identifier.contains("tab.collections") || title == "Collections" { return "IconsaxCollections" }
        if let range = identifier.range(of: "app.zelefin.library."),
           let asset = libraryIcons[String(identifier[range.upperBound...])] {
            return asset
        }
        if identifier.contains("library") || title == "Library" { return LibraryIcon.library }
        if identifier.localizedCaseInsensitiveContains("search") || title == "Search" { return "IconsaxSearch" }
        return nil
    }

    private static func apply(showsTitles: Bool, in view: UIView, selection: DockSelection?) {
        if let bar = view as? UITabBar {
            let standard = bar.standardAppearance.copy()
            style(standard, showsTitles: showsTitles)
            bar.standardAppearance = standard
            let edge = (bar.scrollEdgeAppearance ?? standard).copy()
            style(edge, showsTitles: showsTitles)
            bar.scrollEdgeAppearance = edge
            let inset = showsTitles
                ? UIEdgeInsets.zero
                : UIEdgeInsets(top: 6, left: 0, bottom: -6, right: 0)
            let shift = showsTitles ? UIOffset.zero : UIOffset(horizontal: 0, vertical: 80)
            for item in bar.items ?? [] {
                item.imageInsets = inset
                item.titlePositionAdjustment = shift
                guard let title = item.title, let base = assetBase(identifier: "", title: title) else { continue }
                let selected = isSelected(
                    base: base,
                    identifier: "",
                    title: title,
                    selectedIdentifier: nil,
                    selection: selection
                ) || (selection == nil && item == bar.selectedItem)
                let image = TabBarIconMetrics.image(named: selected ? TabBarIconMetrics.selectedName(for: base) : base)
                item.image = image
                item.selectedImage = image
            }
        }
        for subview in view.subviews {
            apply(showsTitles: showsTitles, in: subview, selection: selection)
        }
    }

    private static func style(_ appearance: UITabBarAppearance, showsTitles: Bool) {
        let hidden: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.clear,
            .font: UIFont.systemFont(ofSize: 0.01)
        ]
        let attributes = showsTitles ? [:] : hidden
        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance
        ] {
            layout.normal.titleTextAttributes = attributes
            layout.selected.titleTextAttributes = attributes
            layout.disabled.titleTextAttributes = attributes
            layout.focused.titleTextAttributes = attributes
            layout.normal.titlePositionAdjustment = showsTitles ? .zero : UIOffset(horizontal: 0, vertical: 80)
            layout.selected.titlePositionAdjustment = showsTitles ? .zero : UIOffset(horizontal: 0, vertical: 80)
        }
    }
}

enum ProfileSheet: String, Identifiable {
    case profile
    case sessions
    case syncplay
    case scheduledTasks
    case settings
    case addUser

    var id: String { rawValue }
}

extension Notification.Name {
    static let zelefinProfileSheet = Notification.Name("zelefin.profileSheet")
}

/// Presents profile sheets from `RootView`. Toolbar / sidebar views do not
/// inherit `@Observable` environment objects, and binding an `@Observable`
/// sheet into the same view that tracks it cycles AttributeGraph.
@MainActor
enum ProfilePresentation {
    static func show(_ destination: ProfileSheet) {
        // UIMenu is still dismissing when the action runs. Presenting a sheet
        // in that window freezes the app and drops HID handlers. A short delay
        // lets the popover finish without polling presentedViewController,
        // which stayed true for the menu itself.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            NotificationCenter.default.post(name: .zelefinProfileSheet, object: destination)
        }
    }

    static func dismiss() {
        NotificationCenter.default.post(name: .zelefinProfileSheet, object: nil)
    }

    static func replace(with destination: ProfileSheet) {
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            NotificationCenter.default.post(name: .zelefinProfileSheet, object: destination)
        }
    }

    static func promptPIN(named name: String) async -> String? {
        await waitUntilNoModal()
        guard let presenter = topViewController() else { return nil }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(
                title: "PIN for \(name)",
                message: "This profile is locked.",
                preferredStyle: .alert
            )
            alert.addTextField { field in
                field.isSecureTextEntry = true
                field.keyboardType = .numberPad
                field.placeholder = "PIN"
            }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            alert.addAction(UIAlertAction(title: "Switch", style: .default) { _ in
                continuation.resume(returning: alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }
    }

    static func showMessage(_ message: String) async {
        await waitUntilNoModal()
        guard let presenter = topViewController() else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                continuation.resume()
            })
            presenter.present(alert, animated: true)
        }
    }

    private static func topViewController() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        let window = windows.first { $0.isKeyWindow } ?? windows.first { !$0.isHidden }
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private static func waitUntilNoModal() async {
        guard hasPresentedViewController else { return }
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            if !hasPresentedViewController {
                try? await Task.sleep(for: .milliseconds(200))
                return
            }
        }
    }

    private static var hasPresentedViewController: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { window in
                !window.isHidden && window.rootViewController?.presentedViewController != nil
            }
    }
}

struct ProfileMenu: View {
    @Environment(SessionStore.self) private var session
    var diameter: CGFloat = 45
    var showsName = false
    var nameFont: Font = .body.weight(.semibold)
    /// The thin glass outline; the Mac sidebar shows the plain photo, as the TV app does.
    var showsGlassRing = true

    /// Thin glass outline; photo fills most of the circle.
    private var glassInset: CGFloat { showsGlassRing ? max(3, (diameter * 0.08).rounded()) : 0 }
    private var photoDiameter: CGFloat { diameter - glassInset * 2 }
    private var displayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    var body: some View {
        labelContent
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .overlay {
                ProfileSystemMenuButton(
                    accessibilityLabel: showsName ? displayName : "Profile",
                    otherAccounts: session.otherAccounts,
                    isSiloServer: session.isSiloServer,
                    siloProfiles: session.siloProfiles,
                    currentSiloProfileID: session.currentSiloProfileID,
                    onProfile: { ProfilePresentation.show(.profile) },
                    onSessions: session.isSiloServer
                        ? nil
                        : { ProfilePresentation.show(.sessions) },
                    onSyncPlay: session.lacksJellyfinOnlyFeatures
                        ? nil
                        : { ProfilePresentation.show(.syncplay) },
                    onScheduledTasks: session.isAdministrator
                        ? { ProfilePresentation.show(.scheduledTasks) }
                        : nil,
                    onAddUser: { ProfilePresentation.show(.addUser) },
                    onSettings: { ProfilePresentation.show(.settings) },
                    onSignOut: { Task { await session.signOut() } },
                    onSwitchTo: { account in
                        Task { await session.switchTo(account) }
                    },
                    onSwitchToProfile: { profile in
                        Task { await switchSiloProfile(profile) }
                    }
                )
            }
            .frame(minWidth: 44, minHeight: 44)
    }

    @ViewBuilder
    private var labelContent: some View {
        if showsName {
            HStack(spacing: 10) {
                avatarBadge
                Text(displayName)
                    .font(nameFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        } else {
            avatarBadge
        }
    }

    @ViewBuilder
    private var avatarBadge: some View {
        if showsGlassRing {
            UserAvatarView(url: session.avatarURL, diameter: photoDiameter)
                .padding(glassInset)
                .zelefinLiquidGlassCircle(interactive: false)
                .contentShape(Circle())
        } else {
            UserAvatarView(url: session.avatarURL, diameter: photoDiameter)
                .contentShape(Circle())
        }
    }

    private func switchSiloProfile(_ profile: SiloProfile) async {
        var pin: String?
        if profile.hasPin {
            let entered = await ProfilePresentation.promptPIN(named: profile.name)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !entered.isEmpty else { return }
            pin = entered
        }
        do {
            try await session.switchSiloProfile(profile, pin: pin)
        } catch {
            await ProfilePresentation.showMessage(error.localizedDescription)
        }
    }
}

/// SwiftUI `Menu` over Liquid Glass / toolbar avatars merges every row into one
/// control. A UIKit `UIMenu` is the same popover as the `…` buttons, with real
/// per-row actions.
private struct ProfileSystemMenuButton: UIViewRepresentable {
    var accessibilityLabel: String
    var otherAccounts: [SavedSession]
    var isSiloServer: Bool
    var siloProfiles: [SiloProfile]
    var currentSiloProfileID: String?
    var onProfile: () -> Void
    var onSessions: (() -> Void)?
    var onSyncPlay: (() -> Void)?
    var onScheduledTasks: (() -> Void)?
    var onAddUser: () -> Void
    var onSettings: () -> Void
    var onSignOut: () -> Void
    var onSwitchTo: (SavedSession) -> Void
    var onSwitchToProfile: (SiloProfile) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> ProfileMenuHitButton {
        let button = ProfileMenuHitButton(type: .custom)
        button.showsMenuAsPrimaryAction = true
        button.preferredMenuElementOrder = .fixed
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityHint = "Shows profile, sessions, settings, and account options"
        context.coordinator.attachMenu(to: button)
        return button
    }

    func updateUIView(_ button: ProfileMenuHitButton, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = accessibilityLabel
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ProfileMenuHitButton, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions(by: CGSize(width: 44, height: 44))
    }

    @MainActor
    final class Coordinator {
        var parent: ProfileSystemMenuButton

        init(parent: ProfileSystemMenuButton) {
            self.parent = parent
        }

        func attachMenu(to button: UIButton) {
            button.menu = UIMenu(children: [
                // Rebuilt on every open so the rows reflect the latest accounts/profiles — but the
                // completion is called synchronously (the provider already runs on the main thread).
                // Hopping through DispatchQueue.main.async deferred it a frame, so UIKit flashed the
                // menu's loading placeholder first, which read as a slow, janky open on iPad.
                UIDeferredMenuElement.uncached { [weak self] completion in
                    MainActor.assumeIsolated {
                        completion(self?.menuChildren() ?? [])
                    }
                }
            ])
        }

        func menuChildren() -> [UIMenuElement] {
            var rows: [UIMenuElement] = [
                Self.action("Profile", "person.crop.circle") { [parent] in
                    parent.onProfile()
                }
            ]
            let otherProfiles = parent.siloProfiles.filter { $0.id != parent.currentSiloProfileID }
            if !otherProfiles.isEmpty {
                let switchProfile = parent.onSwitchToProfile
                let items = otherProfiles.map { profile in
                    var parts: [String] = []
                    if profile.isChild { parts.append("Kids") }
                    if profile.hasPin { parts.append("PIN") }
                    let work = ProfileMenuAction { switchProfile(profile) }
                    nonisolated(unsafe) let handler: (UIAction) -> Void = { _ in
                        work.run()
                    }
                    return UIAction(
                        title: profile.name,
                        subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
                        handler: handler
                    )
                }
                rows.append(
                    UIMenu(
                        title: "Switch Profile",
                        image: UIImage(systemName: "person.crop.rectangle.stack"),
                        children: items
                    )
                )
            }
            if let onSessions = parent.onSessions {
                rows.append(
                    Self.action("Sessions", "play.tv") {
                        onSessions()
                    }
                )
            }
            if let onSyncPlay = parent.onSyncPlay {
                rows.append(
                    Self.action("SyncPlay", "person.2.wave.2") {
                        onSyncPlay()
                    }
                )
            }
            if let onScheduledTasks = parent.onScheduledTasks {
                rows.append(
                    Self.action("Scheduled Tasks", "clock.arrow.2.circlepath") {
                        onScheduledTasks()
                    }
                )
            }
            if !parent.otherAccounts.isEmpty {
                let switchTo = parent.onSwitchTo
                let users = parent.otherAccounts.map { account in
                    let work = ProfileMenuAction { switchTo(account) }
                    nonisolated(unsafe) let handler: (UIAction) -> Void = { _ in
                        work.run()
                    }
                    return UIAction(title: account.userName, subtitle: account.displayServer, handler: handler)
                }
                rows.append(
                    UIMenu(
                        title: parent.isSiloServer ? "Switch Account" : "Switch User",
                        image: UIImage(systemName: "person.2"),
                        children: users
                    )
                )
            }
            rows.append(contentsOf: [
                Self.action(parent.isSiloServer ? "Add Account" : "Add User", "person.badge.plus") { [parent] in
                    parent.onAddUser()
                },
                Self.action("Settings", "gearshape") { [parent] in
                    parent.onSettings()
                }
            ])
            return [
                UIMenu(options: .displayInline, children: rows),
                UIMenu(
                    options: .displayInline,
                    children: [
                        Self.action(
                            "Sign Out",
                            "rectangle.portrait.and.arrow.right",
                            attributes: .destructive
                        ) { [parent] in
                            parent.onSignOut()
                        }
                    ]
                )
            ]
        }

        private static func action(
            _ title: String,
            _ systemImage: String,
            attributes: UIMenuElement.Attributes = [],
            perform: @escaping @MainActor () -> Void
        ) -> UIAction {
            let work = ProfileMenuAction(perform)
            nonisolated(unsafe) let handler: (UIAction) -> Void = { _ in
                work.run()
            }
            return UIAction(title: title, image: UIImage(systemName: systemImage), attributes: attributes, handler: handler)
        }
    }
}

private final class ProfileMenuAction: @unchecked Sendable {
    private let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    func run() {
        DispatchQueue.main.async { [perform] in
            perform()
        }
    }
}

private final class ProfileMenuHitButton: UIButton {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

struct ProfileSheetContainer: View {
    let destination: ProfileSheet
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            switch destination {
            case .profile:
                ProfileView()
                    .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
            case .sessions:
                SessionsView()
                    .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
            case .syncplay:
                SyncPlayView()
                    .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
            case .scheduledTasks:
                ScheduledTasksView()
                    .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
            case .settings:
                SettingsView()
                    .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
            case .addUser:
                AddAccountView()
                    .profileSheetToolbar("Cancel") { ProfilePresentation.dismiss() }
            }
        }
    }
}

private extension View {
    func profileSheetToolbar(_ title: String, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: title == "Cancel" || title == "Close" ? .cancellationAction : .confirmationAction) {
                Button(title, action: action)
            }
        }
    }
}
