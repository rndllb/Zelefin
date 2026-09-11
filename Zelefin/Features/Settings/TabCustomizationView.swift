import SwiftUI

struct TabCustomizationView: View {
    @Environment(SessionStore.self) private var session
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(HomeLayoutPreferences.mergeContinueAndNextUpKey) private var mergeContinueAndNextUp = false
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
                Button("Reset Tabs") {
                    tabOrderRaw = AppTab.defaultOrderRaw
                    tabCustomization = AppTab.defaultCustomization()
                }
            }
        }
        .zelefinSettingsChrome(title: "Interface")
        .onChange(of: mergeContinueAndNextUp) {
            Task { await session.refreshHome() }
        }
    }

    private var homeFooterCopy: String {
        if mergeContinueAndNextUp {
            "In-progress titles and the next episode after you finish one appear in a single Continue Watching row. Each title is still labeled CONTINUE or NEXT."
        } else {
            "Keep in-progress titles in Continue Watching and the next episode after you finish one in Next Up."
        }
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
