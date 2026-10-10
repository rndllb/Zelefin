import SwiftUI

struct TabCustomizationView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false
    @AppStorage(HomeRowKind.orderStorageKey) private var homeRowOrder = HomeRowKind.defaultOrderRaw
    @AppStorage(HomeRowKind.hiddenStorageKey) private var homeRowHidden = ""
    @AppStorage(FeaturedHeroContent.storageKey) private var featuredHeroContent = FeaturedHeroContent.recentlyAdded.rawValue
    @AppStorage(AppTab.showsTitlesStorageKey) private var showsTabNames = true
    @AppStorage(AppTab.dockLibrariesStorageKey) private var dockLibraryIDsRaw = ""

    var body: some View {
        List {
            Section {
                Toggle("Combine Continue Watching and Next Up", isOn: gatedMergeBinding)
                    .tint(AccentPreferences.current)
                    .font(.body.weight(.medium))
            } footer: {
                Text(homeFooterCopy)
            }

            Section {
                Picker("Content", selection: $featuredHeroContent) {
                    ForEach(FeaturedHeroContent.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
            } header: {
                Text("Featured Hero")
            } footer: {
                Text("What the Home hero cycles through. Recently Added is the default. Random picks a new set when Home refreshes.")
            }

            Section {
                ForEach(displayedHomeRows) { row in
                    Toggle(isOn: homeRowVisibilityBinding(for: row)) {
                        Label(row.title, systemImage: row.systemImage)
                    }
                }
                .onMove(perform: moveHomeRows)
            } header: {
                Text("Home")
            } footer: {
                Text(homeRowsFooterCopy)
            }
            .environment(\.editMode, .constant(.active))

            if UIDevice.current.userInterfaceIdiom != .pad {
                Section {
                    Toggle("Show Tab Names", isOn: $showsTabNames)
                }
            }

            Section {
                ForEach(AppTab.ordered(from: tabOrderRaw).filter { tab in
                    !(session.usesSilo && tab == .liveTV)
                }) { tab in
                    Toggle(isOn: visibilityBinding(for: tab)) {
                        Label {
                            Text(tab.title)
                        } icon: {
                            TabBarIcon(assetName: tab.iconAsset, systemImage: tab.systemImage)
                        }
                    }
                    .disabled(!tab.canHide)
                }
                .onMove(perform: moveTabs)
            } header: {
                Text("Tabs")
            } footer: {
                Text(tabFooterCopy)
            }
            .environment(\.editMode, .constant(.active))

            if !pinnableLibraries.isEmpty {
                Section {
                    ForEach(pinnableLibraries) { library in
                        Toggle(isOn: dockLibraryBinding(for: library)) {
                            Label {
                                Text(library.name)
                            } icon: {
                                TabBarIcon(assetName: "IconsaxLibrary", systemImage: "book")
                            }
                        }
                    }
                } header: {
                    Text("Libraries")
                } footer: {
                    Text(libraryDockFooter)
                }
            }

            Section {
                Button("Reset Home Rows") {
                    homeRowOrder = HomeRowKind.defaultOrderRaw
                    homeRowHidden = ""
                    featuredHeroContent = FeaturedHeroContent.recentlyAdded.rawValue
                }
                Button("Reset Tabs") {
                    tabOrderRaw = AppTab.defaultOrderRaw
                    tabCustomization = AppTab.defaultCustomization()
                }
            }
        }
        .zelefinSettingsChrome(title: "Interface")
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
        .task {
            await session.pullDisplayPreferences()
        }
    }

    private var libraryDockFooter: String {
        if UIDevice.current.userInterfaceIdiom == .pad {
            "Turn on a custom library, such as Anime, to put it in the dock."
        } else {
            "Turn on a custom library, such as Anime, to put it in the dock. It uses one of the 5 iPhone spots."
        }
    }

    private var tabFooterCopy: String {
        let names = UIDevice.current.userInterfaceIdiom == .pad
            ? ""
            : (showsTabNames
                ? "Each dock icon shows its name. The iPhone dock holds 5 tabs, including Search. "
                : "The dock shows icons only. Turn Show Tab Names on to put a name under each icon. The iPhone dock holds 5 tabs, including Search. ")
        return names + "Drag to reorder. Turn off a tab to hide it from the tab bar. On iPad, you can also tap Edit at the top of the sidebar."
    }

    private var homeFooterCopy: String {
        if mergeContinueAndNextUp {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
        }
    }

    private var homeRowsFooterCopy: String {
        if mergeContinueAndNextUp {
            "Drag to reorder. Turn off a row to hide it from Home. Next Up only appears when Combine Continue Watching and Next Up is off."
        } else {
            "Drag to reorder. Turn off a row to hide it from Home."
        }
    }

    private var displayedHomeRows: [HomeRowKind] {
        HomeRowKind.ordered(from: homeRowOrder)
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

    private func moveHomeRows(from offsets: IndexSet, to destination: Int) {
        var order = HomeRowKind.ordered(from: homeRowOrder)
        order.move(fromOffsets: offsets, toOffset: destination)
        homeRowOrder = HomeRowKind.raw(from: order)
    }

    private var enabledDockTabCount: Int {
        AppTab.ordered(from: tabOrderRaw).filter { tab in
            if session.usesSilo && tab == .liveTV { return false }
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

struct AppearanceSettingsView: View {
    @AppStorage(AccentPreferences.presetIdKey) private var accentPresetId = AccentPreferences.defaultId
    @AppStorage(AccentPreferences.customHexKey) private var customAccentHex = AccentPreferences.defaultCustomHex

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    AccentColorPickerGrid(
                        accentPresetId: $accentPresetId,
                        customAccentHex: $customAccentHex
                    )
                    .padding(.vertical, 4)

                    if accentPresetId == AccentPreferences.customId {
                        CustomAccentColorControls(
                            accentPresetId: $accentPresetId,
                            customAccentHex: $customAccentHex
                        )
                    }
                }
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Accent color tints buttons, highlights, and icons throughout the app.")
            }
        }
        .zelefinSettingsChrome(title: "Appearance")
    }
}
