import SwiftUI
import UIKit

struct CatalogFilterSortButtons: View {
    var filterCount: Int
    var sortTitle: String
    var onSort: () -> Void
    var onFilter: () -> Void

    var body: some View {
        ZelefinGlassPillCluster {
            ZelefinPillIconSegment(
                systemImage: "arrow.up.arrow.down",
                accessibilityLabel: "Sort",
                accessibilityValue: sortTitle,
                action: onSort
            )
            ZelefinGlassPillDivider()
            ZelefinPillIconSegment(
                systemImage: "line.3.horizontal.decrease",
                accessibilityLabel: "Filters",
                accessibilityValue: filterCount == 0 ? "Off" : "\(filterCount) selected",
                badge: filterCount,
                action: onFilter
            )
        }
    }
}

struct CatalogFilterButton: View {
    var filterCount: Int
    var onFilter: () -> Void

    var body: some View {
        ZelefinGlassPillCluster {
            ZelefinPillIconSegment(
                systemImage: "line.3.horizontal.decrease",
                accessibilityLabel: "Filters",
                accessibilityValue: filterCount == 0 ? "Off" : "\(filterCount) selected",
                badge: filterCount,
                action: onFilter
            )
        }
    }
}

struct ZelefinPillIconSegment<Icon: View>: View {
    var accessibilityLabel: String
    var accessibilityValue: String = ""
    var badge: Int = 0
    var isEnabled: Bool = true
    var action: () -> Void
    var icon: Icon

    init(
        accessibilityLabel: String,
        accessibilityValue: String = "",
        badge: Int = 0,
        isEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder icon: () -> Icon
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
        self.badge = badge
        self.isEnabled = isEnabled
        self.action = action
        self.icon = icon()
    }

    var body: some View {
        icon
            .frame(width: ZelefinPillMetrics.iconFrame, height: ZelefinPillMetrics.iconFrame)
            .frame(width: ZelefinPillMetrics.iconSegmentWidth, height: ZelefinPillMetrics.height)
            .overlay(alignment: .topTrailing) {
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(.white))
                        .offset(x: 2, y: 2)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .allowsHitTesting(false)
            .overlay {
                CatalogChromeHitButton(
                    accessibilityLabel: accessibilityLabel,
                    accessibilityValue: accessibilityValue,
                    action: { if isEnabled { action() } }
                )
            }
            .opacity(isEnabled ? 1 : 0.4)
    }
}

extension ZelefinPillIconSegment where Icon == ZelefinPillSymbol {
    init(
        systemImage: String,
        accessibilityLabel: String,
        accessibilityValue: String = "",
        badge: Int = 0,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.init(
            accessibilityLabel: accessibilityLabel,
            accessibilityValue: accessibilityValue,
            badge: badge,
            isEnabled: isEnabled,
            action: action
        ) {
            ZelefinPillSymbol(systemImage: systemImage)
        }
    }
}

private struct ZelefinPillSymbol: View {
    var systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: ZelefinPillMetrics.iconPointSize, weight: .semibold))
            .imageScale(.medium)
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(.white)
    }
}

/// Liquid Glass and the iPad top tab bar swallow SwiftUI `Button` taps in the
/// floating header. A clear UIKit control is the same hit target as the profile menu.
private struct CatalogChromeHitButton: UIViewRepresentable {
    var accessibilityLabel: String
    var accessibilityValue: String
    var action: () -> Void

    func makeUIView(context: Context) -> CatalogChromeHitUIButton {
        let button = CatalogChromeHitUIButton(type: .custom)
        button.backgroundColor = .clear
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue
        context.coordinator.install(on: button)
        return button
    }

    func updateUIView(_ button: CatalogChromeHitUIButton, context: Context) {
        context.coordinator.action = action
        button.accessibilityLabel = accessibilityLabel
        button.accessibilityValue = accessibilityValue
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CatalogChromeHitUIButton, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? ZelefinPillMetrics.iconSegmentWidth,
            height: proposal.height ?? ZelefinPillMetrics.height
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    @MainActor
    final class Coordinator {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        func install(on button: UIButton) {
            let work = CatalogChromeHitAction { [weak self] in
                self?.action()
            }
            nonisolated(unsafe) let handler: (UIAction) -> Void = { _ in
                work.run()
            }
            let action = UIAction(handler: handler)
            button.addAction(action, for: .touchUpInside)
        }
    }
}

private final class CatalogChromeHitAction: @unchecked Sendable {
    private let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
        self.perform = perform
    }

    func run() {
        Task { @MainActor in
            perform()
        }
    }
}

private final class CatalogChromeHitUIButton: UIButton {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }
}

extension View {
    func catalogFilterSheets(
        query: Binding<CatalogBrowseQuery>,
        options: CatalogFilterOptions,
        showFilters: Binding<Bool>,
        showSort: Binding<Bool>
    ) -> some View {
        self
            .sheet(isPresented: showFilters) {
                CatalogFilterSheet(query: query, options: options)
            }
            .sheet(isPresented: showSort) {
                CatalogSortSheet(query: query)
            }
    }

    func catalogFilterSortToolbar(
        filterCount: Int,
        sortTitle: String,
        showFilters: Binding<Bool>,
        showSort: Binding<Bool>
    ) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                CatalogFilterSortButtons(
                    filterCount: filterCount,
                    sortTitle: sortTitle,
                    onSort: { showSort.wrappedValue = true },
                    onFilter: { showFilters.wrappedValue = true }
                )
                .fixedSize()
                .imageScale(.medium)
                .controlSize(.regular)
            }
            .catalogToolbarHidesSystemBackground()
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    func catalogToolbarHidesSystemBackground() -> some ToolbarContent {
        if #available(iOS 26, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

struct CatalogFilterSheet: View {
    @Binding var query: CatalogBrowseQuery
    var options: CatalogFilterOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                section("Filters", CatalogStatusFilter.allCases, selection: $query.statuses) { $0.title }
                section("Features", CatalogFeatureFilter.allCases, selection: $query.features) { $0.title }
                section("Video Type", CatalogVideoKind.allCases, selection: $query.videoKinds) { $0.title }

                choiceLink("Genres", choices: options.genres, selected: $query.genres)
                choiceLink("Parental Ratings", choices: options.officialRatings, selected: $query.officialRatings)
                choiceLink("Tags", choices: options.tags, selected: $query.tags)
                yearLink()
                choiceLink("Studios", choices: options.studios, selected: $query.studios)
                choiceLink("Audio Languages", choices: options.languages, selected: $query.audioLanguages)
                choiceLink("Subtitle Languages", choices: options.languages, selected: $query.subtitleLanguages)
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { query.clearFilters() }
                        .disabled(query.activeFilterCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func section<Value: Hashable>(
        _ title: String,
        _ values: [Value],
        selection: Binding<Set<Value>>,
        name: @escaping (Value) -> String
    ) -> some View {
        Section(title) {
            ForEach(values, id: \.self) { value in
                Button {
                    if selection.wrappedValue.contains(value) {
                        selection.wrappedValue.remove(value)
                    } else {
                        selection.wrappedValue.insert(value)
                    }
                } label: {
                    HStack {
                        Text(name(value))
                            .foregroundStyle(.white)
                        Spacer()
                        if selection.wrappedValue.contains(value) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
        }
    }

    private func choiceLink(_ title: String, choices: [CatalogFilterChoice], selected: Binding<Set<String>>) -> some View {
        Group {
            if !choices.isEmpty {
                Section {
                    NavigationLink {
                        CatalogChoiceList(title: title, choices: choices, selected: selected)
                    } label: {
                        LabeledContent(title, value: summary(selected.wrappedValue, from: choices))
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                }
            }
        }
    }

    private func yearLink() -> some View {
        Group {
            if !options.years.isEmpty {
                Section {
                    NavigationLink {
                        CatalogChoiceList(
                            title: "Years",
                            choices: options.years,
                            selected: Binding(
                                get: { Set(query.years.map(String.init)) },
                                set: { query.years = Set($0.compactMap(Int.init)) }
                            )
                        )
                    } label: {
                        LabeledContent("Years", value: yearSummary)
                    }
                    .listRowBackground(Color.white.opacity(0.08))
                }
            }
        }
    }

    private func summary(_ selected: Set<String>, from choices: [CatalogFilterChoice]) -> String {
        guard !selected.isEmpty else { return "Any" }
        let names = choices.filter { selected.contains($0.id) }.map(\.name)
        if names.count <= 2 { return names.joined(separator: ", ") }
        return "\(names.count) selected"
    }

    private var yearSummary: String {
        guard !query.years.isEmpty else { return "Any" }
        let years = query.years.sorted(by: >).map(String.init)
        if years.count <= 2 { return years.joined(separator: ", ") }
        return "\(years.count) selected"
    }
}

struct CatalogChoiceList: View {
    let title: String
    let choices: [CatalogFilterChoice]
    @Binding var selected: Set<String>
    @State private var search = ""

    private var visible: [CatalogFilterChoice] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return choices }
        return choices.filter { $0.name.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        List {
            ForEach(visible) { choice in
                Button {
                    if selected.contains(choice.id) {
                        selected.remove(choice.id)
                    } else {
                        selected.insert(choice.id)
                    }
                } label: {
                    HStack {
                        Text(choice.name)
                            .foregroundStyle(.white)
                        Spacer()
                        if selected.contains(choice.id) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.white)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .listRowBackground(Color.white.opacity(0.08))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.black.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { selected = [] }
                    .disabled(selected.isEmpty)
            }
        }
    }
}

struct CatalogSortSheet: View {
    @Binding var query: CatalogBrowseQuery
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sort By") {
                    ForEach(CatalogSortField.allCases) { field in
                        Button {
                            query.sort = field
                            if !field.allowsDirection {
                                query.sortAscending = true
                            }
                        } label: {
                            HStack {
                                Text(field.title)
                                    .foregroundStyle(.white)
                                Spacer()
                                if query.sort == field {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.08))
                    }
                }
                if query.sort.allowsDirection {
                    Section("Order") {
                        sortOrderRow(title: "Ascending", ascending: true)
                        sortOrderRow(title: "Descending", ascending: false)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func sortOrderRow(title: String, ascending: Bool) -> some View {
        Button {
            query.sortAscending = ascending
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.white)
                Spacer()
                if query.sortAscending == ascending {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.white)
                        .fontWeight(.semibold)
                }
            }
        }
        .listRowBackground(Color.white.opacity(0.08))
    }
}
