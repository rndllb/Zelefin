import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                NavigationStack {
                    HomeView()
                }
            }
            Tab("Library", systemImage: "rectangle.stack.fill") {
                NavigationStack {
                    LibraryView()
                }
            }
            Tab("Search", systemImage: "magnifyingglass") {
                NavigationStack {
                    SearchView()
                }
            }
        }
        #if os(iOS)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        #endif
    }
}

struct ProfileMenu: View {
    @Environment(SessionStore.self) private var session
    var diameter: CGFloat = 45
    @State private var avatar: UIImage?
    @State private var showSettings = false

    /// Thin glass outline; photo fills most of the circle.
    private var glassInset: CGFloat { max(3, (diameter * 0.08).rounded()) }
    private var photoDiameter: CGFloat { diameter - glassInset * 2 }

    var body: some View {
        Menu {
            if let name = session.session?.userName {
                Text(name)
            }
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
            avatarContent
                .frame(width: photoDiameter, height: photoDiameter)
                .clipShape(Circle())
                .padding(glassInset)
                .zelefinLiquidGlassCircle()
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Profile")
        .navigationDestination(isPresented: $showSettings) {
            SettingsView()
        }
        .task(id: session.avatarURL) {
            await loadAvatar()
        }
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
