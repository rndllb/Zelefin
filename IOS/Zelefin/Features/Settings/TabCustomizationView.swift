import SwiftUI

struct TabCustomizationView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false
    @AppStorage(HomeRowKind.orderStorageKey) private var homeRowOrder = HomeRowKind.defaultOrderRaw
    @AppStorage(HomeRowKind.hiddenStorageKey) private var homeRowHidden = HomeRowKind.defaultHiddenRaw
    @AppStorage(FeaturedHeroContent.storageKey) private var featuredHeroContent = FeaturedHeroContent.recentlyAdded.rawValue
    @AppStorage(HeroSizePreferences.storageKey) private var heroSizeRaw = HeroSizePreferences.compact.rawValue
    @AppStorage(PosterBadgePreferences.ratingKey) private var showsPosterRating = true
    @AppStorage(PosterBadgePreferences.qualityKey) private var showsPosterQuality = true
    @AppStorage(PosterBadgePreferences.watchedKey) private var showsPosterWatched = true
    @AppStorage(AppTab.showsTitlesStorageKey) private var showsTabNames = true
    @AppStorage(AppTab.dockLibrariesStorageKey) private var dockLibraryIDsRaw = ""
    @AppStorage(AppTab.startTabStorageKey) private var startTabRaw = AppTab.home.rawValue
    @AppStorage(LibraryIcon.choicesStorageKey) private var libraryIconsRaw = ""
    @AppStorage(LibraryLayoutPreferences.orderKey) private var libraryOrderRaw = ""
    @AppStorage(LibraryLayoutPreferences.hiddenKey) private var libraryHiddenRaw = ""
    @AppStorage(LibraryLayoutPreferences.pageHiddenKey) private var libraryPageHiddenRaw = ""
    @AppStorage(AccentPreferences.presetIdKey) private var accentPresetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customAccentHex = AccentPreferences.defaultCustomHex

    @Environment(\.editMode) private var editMode

    private var isEditing: Bool {
        editMode?.wrappedValue.isEditing == true
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    AccentColorPickerGrid(
                        accentPresetId: $accentPresetId,
                        customAccentHex: $customAccentHex
                    )

                    if accentPresetId == AccentPreferences.customId {
                        CustomAccentColorControls(
                            accentPresetId: $accentPresetId,
                            customAccentHex: $customAccentHex
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.vertical, 4)
                .animation(.spring(response: 0.34, dampingFraction: 0.84), value: accentPresetId)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Tints buttons, highlights, and icons throughout the app.")
            }
            .zelefinRowBackground()

            Section {
                Toggle("Combine Continue Watching and Next Up", isOn: gatedMergeBinding)
            } footer: {
                Text(homeFooterCopy)
            }
            .zelefinRowBackground()

            Section {
                Picker("Content", selection: $featuredHeroContent) {
                    ForEach(FeaturedHeroContent.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                Picker("Size", selection: $heroSizeRaw) {
                    ForEach(HeroSizePreferences.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            } header: {
                Text("Featured Hero")
            } footer: {
                Text("What the Home hero cycles through, and how tall the Featured and title-page backdrops run. Compact shows more of a landscape image; Tall is the previous full-bleed height. Recently Added is the default content.")
            }
            .zelefinRowBackground()

            Section {
                Toggle("Community Rating", isOn: $showsPosterRating)
                Toggle("Quality Badges", isOn: $showsPosterQuality)
                Toggle("Watched Mark", isOn: $showsPosterWatched)
            } header: {
                Text("Poster Badges")
            } footer: {
                Text("Rating stars, 4K/HDR/Atmos marks, and the watched check on posters. Turn any of them off to quiet the covers.")
            }
            .zelefinRowBackground()

            Section {
                ForEach(homeRowSlots) { slot in
                    homeRowSlotRow(slot)
                }
                .onMove(perform: moveHomeRowSlots)
                if !isEditing {
                    Button {
                        addCustomHomeRow()
                    } label: {
                        Label("Add Custom Row", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("Home")
            } footer: {
                Text(homeRowsFooterCopy)
            }
            .zelefinRowBackground()

            Section {
                Picker("Page", selection: $startTabRaw) {
                    ForEach(startPageChoices) { tab in
                        Text(tab.title).tag(tab.rawValue)
                    }
                }
            } header: {
                Text("Start Page")
            } footer: {
                Text("The page Zelefin opens to when you launch it. Home is the default.")
            }
            .zelefinRowBackground()

            #if targetEnvironment(macCatalyst)
            sidebarSections
            #else
            if !UIDevice.current.userInterfaceIdiom.isLargeScreen {
                Section {
                    Toggle("Show Tab Names", isOn: $showsTabNames)
                }
                .zelefinRowBackground()
            }

            Section {
                ForEach(AppTab.ordered(from: tabOrderRaw).filter { tab in
                    !(session.hidesLiveTV && tab == .liveTV)
                }) { tab in
                    if isEditing {
                        Label(tab.title, systemImage: tab.systemImage)
                    } else {
                        Toggle(isOn: visibilityBinding(for: tab)) {
                            Label(tab.title, systemImage: tab.systemImage)
                        }
                        .disabled(!tab.canHide)
                    }
                }
                .onMove(perform: moveTabs)
            } header: {
                Text("Tabs")
            } footer: {
                Text(tabFooterCopy)
            }
            .zelefinRowBackground()

            if !pinnableLibraries.isEmpty {
                Section {
                    ForEach(pinnableLibraries) { library in
                        Toggle(isOn: dockLibraryBinding(for: library)) {
                            libraryLabel(library)
                        }
                    }
                } header: {
                    Text("Libraries")
                } footer: {
                    Text(libraryDockFooter)
                }
                .zelefinRowBackground()
            }
            #endif

            if !animeLibraries.isEmpty {
                Section {
                    ForEach(animeLibraries) { library in
                        NavigationLink {
                            LibraryIconPickerView(library: library)
                        } label: {
                            HStack(spacing: 12) {
                                TabBarIcon(
                                    assetName: LibraryIcon.asset(for: library, raw: libraryIconsRaw),
                                    systemImage: "books.vertical",
                                    side: 24
                                )
                                .foregroundStyle(.tint)
                                Text(library.name)
                                Spacer(minLength: 8)
                                Text(LibraryIcon.chosen(for: library, raw: libraryIconsRaw) == nil ? "Default" : "Custom")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Anime Icons")
                } footer: {
                    Text(animeIconsFooter)
                }
                .zelefinRowBackground()
            }

            Section {
                Button("Reset Home Rows") {
                    let customIDs = Set(CustomHomeRows.rows.map(\.id))
                    homeRowOrder = HomeRowSlot.rawOrder(
                        HomeRowSlot.ordered(from: HomeRowKind.defaultOrderRaw, customIDs: customIDs)
                    )
                    homeRowHidden = HomeRowKind.defaultHiddenRaw
                    featuredHeroContent = FeaturedHeroContent.recentlyAdded.rawValue
                }
                #if targetEnvironment(macCatalyst)
                Button("Reset Sidebar") {
                    libraryOrderRaw = ""
                    libraryHiddenRaw = ""
                    libraryPageHiddenRaw = ""
                }
                #else
                Button("Reset Tabs") {
                    tabOrderRaw = AppTab.defaultOrderRaw
                    tabCustomization = AppTab.defaultCustomization()
                }
                #endif
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: "Interface")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .onChange(of: mergeContinueAndNextUp) {
            Task {
                await session.refreshHome()
                await session.pushDisplayPreferences()
            }
        }
        .onChange(of: homeRowOrder) {
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: homeRowHidden) {
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: featuredHeroContent) {
            Task {
                await session.refreshHome()
                await session.pushDisplayPreferences()
            }
        }
        .onChange(of: tabOrderRaw) {
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: libraryOrderRaw) {
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: libraryHiddenRaw) {
            Task { await session.pushDisplayPreferences() }
        }
        .onChange(of: libraryPageHiddenRaw) {
            Task { await session.pushDisplayPreferences() }
        }
        .task {
            await session.pullDisplayPreferences()
        }
    }

    /// The Mac opens on Home, Movies, or Shows. It has no Library page.
    private var startPageChoices: [AppTab] {
        #if targetEnvironment(macCatalyst)
        AppTab.startPageChoices.filter { $0 != .library }
        #else
        AppTab.startPageChoices
        #endif
    }

    #if targetEnvironment(macCatalyst)
    /// The sidebar's Library section: Search, Home, Discover, and Recently Added always lead it.
    @ViewBuilder
    private var sidebarSections: some View {
        Section {
            ForEach(sidebarLibraries) { library in
                if isEditing {
                    libraryLabel(library)
                } else {
                    Toggle(isOn: sidebarLibraryBinding(for: library)) {
                        libraryLabel(library)
                    }
                }
            }
            .onMove(perform: moveSidebarLibraries)
        } header: {
            Text("Sidebar")
        } footer: {
            Text("Search, Home, Discover, and Recently Added always stay at the top. Turn off a library to hide it from the sidebar. Click Edit to drag libraries into a new order.")
        }
        .zelefinRowBackground()

        Section {
            ForEach(sidebarBlocks) { block in
                Toggle(isOn: sidebarBlockBinding(for: block)) {
                    Label(block.sidebarTitle, systemImage: block.systemImage)
                }
            }
        } footer: {
            Text("These follow your libraries in the sidebar.")
        }
        .zelefinRowBackground()
    }

    private var sidebarLibraries: [MediaLibrary] {
        LibraryLayoutPreferences.arranged(
            LibraryLayoutPreferences.sidebarLibraries(session.libraries, hidesLiveTV: session.hidesLiveTV),
            orderRaw: libraryOrderRaw
        )
    }

    /// In the order the sidebar lists them. The Watchlist is a Jellyfin playlist, and Silo has none.
    private var sidebarBlocks: [LibraryPageBlock] {
        [LibraryPageBlock.collections, .favorites, .watchlist, .genres, .downloaded].filter { block in
            !(block == .watchlist && session.isSiloServer)
        }
    }

    private func sidebarLibraryBinding(for library: MediaLibrary) -> Binding<Bool> {
        Binding(
            get: { !LibraryLayoutPreferences.resolvedHidden(from: libraryHiddenRaw, libraries: sidebarLibraries).contains(library.id) },
            set: { isOn in
                var hidden = LibraryLayoutPreferences.resolvedHidden(from: libraryHiddenRaw, libraries: sidebarLibraries)
                if isOn {
                    hidden.remove(library.id)
                } else {
                    hidden.insert(library.id)
                }
                libraryHiddenRaw = LibraryLayoutPreferences.hiddenRaw(from: hidden)
            }
        )
    }

    private func sidebarBlockBinding(for block: LibraryPageBlock) -> Binding<Bool> {
        Binding(
            get: { !LibraryLayoutPreferences.hiddenBlocks(from: libraryPageHiddenRaw).contains(block) },
            set: { isOn in
                var hidden = LibraryLayoutPreferences.hiddenBlocks(from: libraryPageHiddenRaw)
                if isOn {
                    hidden.remove(block)
                } else {
                    hidden.insert(block)
                }
                libraryPageHiddenRaw = LibraryLayoutPreferences.pageHiddenRaw(from: hidden)
            }
        )
    }

    private func moveSidebarLibraries(from offsets: IndexSet, to destination: Int) {
        var order = sidebarLibraries
        order.move(fromOffsets: offsets, toOffset: destination)
        libraryOrderRaw = LibraryLayoutPreferences.orderRaw(from: order)
    }
    #endif

    /// The icon the dock and sidebar show for the library, beside its name.
    private func libraryLabel(_ library: MediaLibrary) -> some View {
        Label {
            Text(library.name)
        } icon: {
            TabBarIcon(
                assetName: LibraryIcon.asset(for: library, raw: libraryIconsRaw),
                systemImage: "books.vertical",
                side: 22
            )
            .foregroundStyle(.tint)
        }
    }

    /// Libraries with "Anime" in the name that show an icon here: every one in the Mac sidebar, pinnable ones in the dock.
    private var animeLibraries: [MediaLibrary] {
        #if targetEnvironment(macCatalyst)
        LibraryLayoutPreferences.sidebarLibraries(session.libraries, hidesLiveTV: session.hidesLiveTV)
            .filter(LibraryIcon.canChoose)
        #else
        pinnableLibraries.filter(LibraryIcon.canChoose)
        #endif
    }

    private var animeIconsFooter: String {
        #if targetEnvironment(macCatalyst)
        "Pick the icon a library with Anime in its name shows in the sidebar."
        #else
        "Pick the icon a library with Anime in its name shows when it's in the dock."
        #endif
    }

    private var libraryDockFooter: String {
        if UIDevice.current.userInterfaceIdiom.isLargeScreen {
            "Turn on a custom library, such as Anime, to put it in the dock."
        } else {
            "Turn on a custom library, such as Anime, to put it in the dock. It uses one of the 5 iPhone spots."
        }
    }

    private var tabFooterCopy: String {
        let names = UIDevice.current.userInterfaceIdiom.isLargeScreen
            ? ""
            : (showsTabNames
                ? "Each dock icon shows its name. The iPhone dock holds 5 tabs, including Search. "
                : "The dock shows icons only. Turn Show Tab Names on to put a name under each icon. The iPhone dock holds 5 tabs, including Search. ")
        return names + "Turn off a tab to hide it from the tab bar. Tap Edit to drag rows into a new order. On iPad, you can also tap Edit at the top of the sidebar."
    }

    private var homeFooterCopy: String {
        if mergeContinueAndNextUp {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
        }
    }

    private var homeRowsFooterCopy: String {
        #if targetEnvironment(macCatalyst)
        let edit = "Click Edit to drag rows into a new order."
        #else
        let edit = "Tap Edit to drag rows into a new order."
        #endif
        let custom = "Custom rows use catalog filters and can sit between built-in rows. "
        let rows = custom + "Turn off a row to hide it from Home. \(edit)"
        return mergeContinueAndNextUp
            ? rows + " Next Up only appears when Combine Continue Watching and Next Up is off."
            : rows
    }

    private var homeRowSlots: [HomeRowSlot] {
        HomeRowSlot.ordered(from: homeRowOrder, customIDs: Set(CustomHomeRows.rows.map(\.id)))
    }

    @ViewBuilder
    private func homeRowSlotRow(_ slot: HomeRowSlot) -> some View {
        switch slot {
        case let .builtIn(row):
            if isEditing {
                Label(row.title, systemImage: row.systemImage)
            } else {
                Toggle(isOn: homeRowVisibilityBinding(for: row)) {
                    Label(row.title, systemImage: row.systemImage)
                }
            }
        case let .custom(id):
            if let row = CustomHomeRows.row(id: id) {
                Group {
                    if isEditing {
                        Label(row.title, systemImage: "line.3.horizontal.decrease.circle")
                    } else {
                        HStack(spacing: 12) {
                            NavigationLink {
                                CustomHomeRowEditorView(rowID: id)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.title)
                                    Text(CustomHomeRows.filterSummary(row))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 8)
                            Toggle("Visible", isOn: customHomeRowEnabledBinding(for: row))
                                .labelsHidden()
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        deleteCustomHomeRow(id: id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private var gatedMergeBinding: Binding<Bool> {
        Binding(
            get: { mergeContinueAndNextUp },
            set: { mergeContinueAndNextUp = $0 }
        )
    }

    private func homeRowVisibilityBinding(for row: HomeRowKind) -> Binding<Bool> {
        Binding(
            get: { !HomeRowKind.hidden(from: homeRowHidden).contains(row) },
            set: { isOn in
                var hidden = HomeRowKind.hidden(from: homeRowHidden)
                if isOn {
                    hidden.remove(row)
                } else {
                    hidden.insert(row)
                }
                homeRowHidden = HomeRowKind.hiddenRaw(from: hidden)
            }
        )
    }

    private func moveHomeRowSlots(from offsets: IndexSet, to destination: Int) {
        var slots = homeRowSlots
        slots.move(fromOffsets: offsets, toOffset: destination)
        homeRowOrder = HomeRowSlot.rawOrder(slots)
    }

    private func customHomeRowEnabledBinding(for row: CustomHomeRow) -> Binding<Bool> {
        Binding(
            get: { CustomHomeRows.row(id: row.id)?.enabled ?? row.enabled },
            set: { enabled in
                var next = row
                next.enabled = enabled
                CustomHomeRows.update(next)
                Task {
                    await session.refreshHome()
                    await session.pushDisplayPreferences()
                }
            }
        )
    }

    private func addCustomHomeRow() {
        let row = CustomHomeRows.add()
        CustomHomeRows.insertCustomSlot(id: row.id, into: &homeRowOrder)
        Task {
            await session.refreshHome()
            await session.pushDisplayPreferences()
        }
    }

    private func deleteCustomHomeRow(id: String) {
        CustomHomeRows.removeCustomSlot(id: id, from: &homeRowOrder)
        CustomHomeRows.remove(id: id)
        Task {
            await session.refreshHome()
            await session.pushDisplayPreferences()
        }
    }

    private var enabledDockTabCount: Int {
        AppTab.ordered(from: tabOrderRaw).filter { tab in
            if session.hidesLiveTV && tab == .liveTV { return false }
            return !tab.canHide || tabCustomization[sidebarVisibility: tab.customizationID] != .hidden
        }.count
    }

    private var enabledDockLibraryCount: Int {
        let ids = DockLibraryPreferences.ids(from: dockLibraryIDsRaw)
        return pinnableLibraries.filter { ids.contains($0.id) }.count
    }

    private var canEnableAnotherDockItem: Bool {
        PhoneDockLimit.canEnableAnother(
            enabledTabs: enabledDockTabCount,
            enabledLibraries: enabledDockLibraryCount
        )
    }

    private var pinnableLibraries: [MediaLibrary] {
        session.libraries.filter(DockLibraryPreferences.canPin)
    }

    private func dockLibraryBinding(for library: MediaLibrary) -> Binding<Bool> {
        Binding(
            get: { DockLibraryPreferences.ids(from: dockLibraryIDsRaw).contains(library.id) },
            set: { isOn in
                var ids = DockLibraryPreferences.ids(from: dockLibraryIDsRaw)
                let alreadyOn = ids.contains(library.id)
                if isOn, !alreadyOn, !canEnableAnotherDockItem {
                    return
                }
                if isOn {
                    ids.insert(library.id)
                } else {
                    ids.remove(library.id)
                }
                dockLibraryIDsRaw = DockLibraryPreferences.raw(from: ids)
            }
        )
    }

    private func visibilityBinding(for tab: AppTab) -> Binding<Bool> {
        Binding(
            get: { tabCustomization[sidebarVisibility: tab.customizationID] != .hidden },
            set: { isOn in
                let alreadyOn = tabCustomization[sidebarVisibility: tab.customizationID] != .hidden
                if isOn, !alreadyOn, !canEnableAnotherDockItem {
                    return
                }
                tabCustomization[sidebarVisibility: tab.customizationID] = isOn ? .automatic : .hidden
            }
        )
    }

    private func moveTabs(from offsets: IndexSet, to destination: Int) {
        var order = AppTab.ordered(from: tabOrderRaw)
        order.move(fromOffsets: offsets, toOffset: destination)
        tabOrderRaw = AppTab.raw(from: order)
        tabCustomization.resetSectionOrder()
    }
}

struct CustomHomeRowEditorView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    let rowID: String

    @State private var draft: CustomHomeRow
    @State private var browseQuery: CatalogBrowseQuery
    @State private var options = CatalogFilterOptions()
    @State private var showFilters = false
    @State private var showSort = false
    @State private var confirmDelete = false

    init(rowID: String) {
        self.rowID = rowID
        let row = CustomHomeRows.row(id: rowID) ?? CustomHomeRow()
        _draft = State(initialValue: row)
        _browseQuery = State(initialValue: row.browseQuery)
    }

    var body: some View {
        List {
            Section {
                TextField("Title", text: $draft.title)
                Picker("Scope", selection: $draft.scope) {
                    ForEach(CustomHomeRowScope.allCases) { scope in
                        Text(scope.title).tag(scope.rawValue)
                    }
                }
            }
            .zelefinRowBackground()

            Section {
                Text(CustomHomeRows.filterSummary(draft.withQuery(browseQuery)))
                    .foregroundStyle(.secondary)
                Button("Filters") { showFilters = true }
                Button("Sort") { showSort = true }
            } header: {
                Text("Catalog Filters")
            }
            .zelefinRowBackground()

            Section {
                Button("Delete Custom Row", role: .destructive) {
                    confirmDelete = true
                }
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: "Custom Row")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
            }
        }
        .catalogFilterSheets(
            query: $browseQuery,
            options: options,
            showFilters: $showFilters,
            showSort: $showSort
        )
        .confirmationDialog("Delete this custom row?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteRow() }
            Button("Cancel", role: .cancel) {}
        }
        .task { await loadOptions() }
        .onChange(of: browseQuery) { _, _ in
            draft = draft.withQuery(browseQuery)
        }
        .onChange(of: draft.scope) { _, _ in
            Task { await loadOptions() }
        }
    }

    private func loadOptions() async {
        guard let library = session.library else { return }
        let scope = CustomHomeRowScope.from(raw: draft.scope)
        if scope == .both {
            options = await library.mixedCatalogFilterOptions()
        } else {
            options = await library.catalogFilterOptions(for: scope.primaryLibraryKind)
        }
    }

    private func save() {
        let next = draft.withQuery(browseQuery)
        CustomHomeRows.update(next)
        Task {
            await session.refreshHome()
            await session.pushDisplayPreferences()
        }
    }

    private func deleteRow() {
        var order = UserDefaults.standard.string(forKey: HomeRowKind.orderStorageKey) ?? HomeRowKind.defaultOrderRaw
        CustomHomeRows.removeCustomSlot(id: rowID, from: &order)
        UserDefaults.standard.set(order, forKey: HomeRowKind.orderStorageKey)
        CustomHomeRows.remove(id: rowID)
        Task {
            await session.refreshHome()
            await session.pushDisplayPreferences()
        }
        dismiss()
    }
}

/// The icon a library with Anime in its name shows in the dock and the Mac sidebar.
struct LibraryIconPickerView: View {
    let library: MediaLibrary
    @AppStorage(LibraryIcon.choicesStorageKey) private var libraryIconsRaw = ""

    private var chosen: String? {
        LibraryIcon.chosen(for: library, raw: libraryIconsRaw)
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 12)], spacing: 14) {
                    tile(
                        asset: LibraryIcon.defaultAsset(for: library),
                        title: "Default",
                        isSelected: chosen == nil
                    ) {
                        choose(nil)
                    }
                    ForEach(LibraryIcon.animeChoices) { choice in
                        tile(asset: choice.asset, title: choice.title, isSelected: chosen == choice.asset) {
                            choose(choice.asset)
                        }
                    }
                }
                .padding(.vertical, 4)
            } footer: {
                Text("Icons by PlainIcon (Anime characters), licensed under CC BY 4.0.")
            }
            .zelefinRowBackground()
        }
        .zelefinSettingsChrome(title: library.name)
    }

    private func tile(asset: String, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .frame(width: 60, height: 60)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.primary.opacity(isSelected ? 0.14 : 0.06))
                    }
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.tint, lineWidth: 2)
                        }
                    }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 26, alignment: .top)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ asset: String?) {
        var choices = LibraryIcon.choices(from: libraryIconsRaw)
        choices[library.id] = asset
        libraryIconsRaw = LibraryIcon.raw(from: choices)
    }
}

