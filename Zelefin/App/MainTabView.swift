import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    #if os(iOS)
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = TabViewCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    #endif

    var body: some View {
        tabView
    }

    private var tabView: some View {
        TabView {
            ForEach(visibleTabs) { tab in
            Tab(tab.title, systemImage: tab.systemImage) {
                NavigationStack {
                    tabRoot(tab)
                }
                .zelefinSidebarLayout()
            }
                #if os(iOS)
                .customizationID(tab.customizationID)
                .customizationBehavior(tab.canHide ? .automatic : .reorderable, for: .sidebar, .tabBar)
                #endif
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    SearchView()
                }
                .zelefinSidebarLayout()
            }
            #if os(iOS)
            .customizationBehavior(.disabled, for: .sidebar, .tabBar)
            #endif
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        .tabViewCustomization($tabCustomization)
        .tabViewSidebarBottomBar {
            ProfileMenu(diameter: 36, showsName: true)
                .padding(.leading, 20)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        #endif
        .background(.clear)
    }

    private var visibleTabs: [AppTab] {
        #if os(iOS)
        let ordered = AppTab.ordered(from: tabOrderRaw)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return ordered
        }
        return ordered.filter { tab in
            !tab.canHide || tabCustomization[sidebarVisibility: tab.customizationID] != .hidden
        }
        #else
        AppTab.allCases.map { $0 }
        #endif
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
        case .library:
            LibraryView()
        }
    }
}

struct ProfileMenu: View {
    @Environment(SessionStore.self) private var session
    var diameter: CGFloat = 45
    var showsName = false
    @State private var avatar: UIImage?
    @State private var showSettings = false

    /// Thin glass outline; photo fills most of the circle.
    private var glassInset: CGFloat { max(3, (diameter * 0.08).rounded()) }
    private var photoDiameter: CGFloat { diameter - glassInset * 2 }
    private var displayName: String {
        let name = session.session?.userName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Account" : name
    }

    var body: some View {
        Menu {
            if let server = session.serverName {
                Text(server)
            }
            Button("Settings") {
                showSettings = true
            }
            Button("Sign Out", role: .destructive) {
                Task { await session.signOut() }
            }
        } label: {
            if showsName {
                HStack(spacing: 10) {
                    avatarBadge
                    Text(displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            } else {
                avatarBadge
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(showsName ? displayName : "Profile")
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showSettings = false }
                        }
                    }
                    #endif
            }
        }
        .task(id: session.avatarURL) {
            await loadAvatar()
        }
    }

    private var avatarBadge: some View {
        avatarContent
            .frame(width: photoDiameter, height: photoDiameter)
            .clipShape(Circle())
            .padding(glassInset)
            .zelefinLiquidGlassCircle()
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let avatar {
            Image(uiImage: avatar)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: "person.fill")
                .font(.system(size: photoDiameter * 0.44, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadAvatar() async {
        avatar = nil
        guard let url = session.avatarURL else { return }
        do {
            let (data, response) = try await JellyfinNetworking.data(from: url)
            guard !Task.isCancelled else { return }
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
                  let image = UIImage(data: data)
            else { return }
            avatar = image
        } catch {
            return
        }
    }
}
