import SwiftUI

struct TabCustomizationView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false
    @AppStorage(HomeRowKind.orderStorageKey) private var homeRowOrder = HomeRowKind.defaultOrderRaw
    @AppStorage(HomeRowKind.hiddenStorageKey) private var homeRowHidden = ""
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
                .padding(.vertical, 8)
            } header: {
                Text("Accent Color")
            } footer: {
                Text("Accent color tints buttons, highlights, and icons throughout the app.")
            }

            Section {
                Toggle("Combine Continue Watching and Next Up", isOn: $mergeContinueAndNextUp)
            } footer: {
                Text(homeFooterCopy)
            }

            Section {
                ForEach(HomeRowKind.ordered(from: homeRowOrder)) { row in
                    HStack(spacing: 12) {
                        Label(row.title, systemImage: row.systemImage)
                        Spacer(minLength: 8)
                        Toggle("Show \(row.title)", isOn: homeRowVisibilityBinding(for: row))
                            .labelsHidden()
                    }
                    .accessibilityElement(children: .combine)
                }
                .onMove(perform: moveHomeRows)
            } header: {
                Text("Home")
            } footer: {
                Text(homeRowsFooterCopy)
            }
            .environment(\.editMode, .constant(.active))

            Section {
                ForEach(AppTab.ordered(from: tabOrderRaw)) { tab in
                    HStack(spacing: 12) {
                        Label(tab.title, systemImage: tab.systemImage)
                        Spacer(minLength: 8)
                        if tab.canHide {
                            Toggle("Show \(tab.title)", isOn: visibilityBinding(for: tab))
                                .labelsHidden()
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                .onMove(perform: moveTabs)
            } header: {
                Text("Tabs")
            } footer: {
                Text("Drag to reorder. Turn off a tab to hide it from the tab bar. On iPad, you can also tap Edit at the top of the sidebar.")
            }
            .environment(\.editMode, .constant(.active))

            Section {
                Button("Reset Home Rows") {
                    homeRowOrder = HomeRowKind.defaultOrderRaw
                    homeRowHidden = ""
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
        .onChange(of: tabOrderRaw) {
            Task { await session.pushDisplayPreferences() }
        }
        .task {
            await session.pullDisplayPreferences()
        }
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

    private func visibilityBinding(for tab: AppTab) -> Binding<Bool> {
        Binding(
            get: { tabCustomization[sidebarVisibility: tab.customizationID] != .hidden },
            set: { isOn in
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
