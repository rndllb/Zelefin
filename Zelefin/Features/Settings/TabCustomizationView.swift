import SwiftUI

#if os(iOS)
struct TabCustomizationView: View {
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = TabViewCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw

    var body: some View {
        List {
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
            } footer: {
                Text("Drag to reorder. Turn off a tab to hide it from the tab bar. On iPad, you can also tap Edit at the top of the sidebar.")
            }

            Section {
                Button("Reset Tabs") {
                    tabOrderRaw = AppTab.defaultOrderRaw
                    tabCustomization = TabViewCustomization()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .navigationTitle("Tabs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
#endif
