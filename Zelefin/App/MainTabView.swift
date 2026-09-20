import SwiftUI
import UIKit

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @Environment(PlusEntitlement.self) private var plus
    @AppStorage(AppTab.customizationStorageKey) private var tabCustomization = AppTab.defaultCustomization()
    @AppStorage(AppTab.orderStorageKey) private var tabOrderRaw = AppTab.defaultOrderRaw
    @AppStorage(AppTab.hiddenDefaultsAppliedKey) private var hiddenDefaultsApplied = false
    @AppStorage(AppTab.favoritesHiddenDefaultKey) private var favoritesHiddenDefaultApplied = false
    @AppStorage(AppTab.liveTVHiddenDefaultKey) private var liveTVHiddenDefaultApplied = false

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
                .customizationID(tab.customizationID)
                .customizationBehavior(tab.canHide ? .automatic : .reorderable, for: .sidebar, .tabBar)
            }

            Tab("Search", systemImage: "magnifyingglass", role: .search) {
                NavigationStack {
                    SearchView()
                }
                .zelefinSidebarLayout()
            }
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
        .onAppear { applyHiddenTabDefaultsIfNeeded() }
        .background(.clear)
    }

    private var tabCustomizationBinding: Binding<TabViewCustomization> {
        Binding(
            get: { tabCustomization },
            set: { newValue in
                guard plus.require(.interface) else { return }
                tabCustomization = newValue
            }
        )
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

    private var visibleTabs: [AppTab] {
        var ordered = AppTab.ordered(from: tabOrderRaw)
        if session.usesSilo {
            ordered.removeAll { $0 == .liveTV }
        }
        if UIDevice.current.userInterfaceIdiom == .pad {
            return ordered
        }
        return ordered.filter { tab in
            !tab.canHide || tabCustomization[sidebarVisibility: tab.customizationID] != .hidden
        }
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

enum ProfileSheet: String, Identifiable {
    case profile
    case sessions
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
        Task { @MainActor in
            await waitUntilNoModal()
            NotificationCenter.default.post(name: .zelefinProfileSheet, object: destination)
        }
    }

    static func dismiss() {
        NotificationCenter.default.post(name: .zelefinProfileSheet, object: nil)
    }

    static func replace(with destination: ProfileSheet) {
        dismiss()
        show(destination)
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
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(50))
            if !hasPresentedViewController {
                try? await Task.sleep(for: .milliseconds(300))
                return
            }
        }
    }

    private static var hasPresentedViewController: Bool {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .contains { !$0.isHidden && isPresenting(from: $0.rootViewController) }
    }

    private static func isPresenting(from controller: UIViewController?) -> Bool {
        guard let controller else { return false }
        if controller.presentedViewController != nil { return true }
        return controller.children.contains { isPresenting(from: $0) }
    }
}

struct ProfileMenu: View {
    @Environment(SessionStore.self) private var session
    private var plus: PlusEntitlement { PlusEntitlement.shared }
    var diameter: CGFloat = 45
    var showsName = false

    /// Thin glass outline; photo fills most of the circle.
    private var glassInset: CGFloat { max(3, (diameter * 0.08).rounded()) }
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
                    householdProfiles: session.householdProfiles,
                    currentProfileID: session.session?.profileID,
                    usesSilo: session.usesSilo,
                    onProfile: { ProfilePresentation.show(.profile) },
                    onSessions: session.usesSilo
                        ? nil
                        : {
                            guard plus.require(.sessions) else { return }
                            ProfilePresentation.show(.sessions)
                        },
                    onScheduledTasks: session.isAdministrator
                        ? {
                            guard plus.require(.adminTools) else { return }
                            ProfilePresentation.show(.scheduledTasks)
                        }
                        : nil,
                    onAddUser: {
                        guard plus.require(.extraAccounts) else { return }
                        ProfilePresentation.show(.addUser)
                    },
                    onSettings: { ProfilePresentation.show(.settings) },
                    onSignOut: { Task { await session.signOut() } },
                    onSwitchTo: { account in
                        Task { await session.switchTo(account) }
                    },
                    onSwitchToProfile: { profile in
                        Task { await switchHouseholdProfile(profile) }
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
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        } else {
            avatarBadge
        }
    }

    private var avatarBadge: some View {
        UserAvatarView(url: session.avatarURL, diameter: photoDiameter)
            .padding(glassInset)
            .zelefinLiquidGlassCircle(interactive: false)
            .contentShape(Circle())
    }

    private func switchHouseholdProfile(_ profile: SiloHouseholdProfile) async {
        var pin: String?
        if profile.hasPin {
            pin = await ProfilePresentation.promptPIN(named: profile.name)
            let trimmed = pin?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            pin = trimmed
        }
        do {
            try await session.applySiloProfile(profile, pin: pin)
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
    var householdProfiles: [SiloHouseholdProfile]
    var currentProfileID: String?
    var usesSilo: Bool
    var onProfile: () -> Void
    var onSessions: (() -> Void)?
    var onScheduledTasks: (() -> Void)?
    var onAddUser: () -> Void
    var onSettings: () -> Void
    var onSignOut: () -> Void
    var onSwitchTo: (SavedSession) -> Void
    var onSwitchToProfile: (SiloHouseholdProfile) -> Void

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
        context.coordinator.installMenu(on: button)
        return button
    }

    func updateUIView(_ button: ProfileMenuHitButton, context: Context) {
        context.coordinator.parent = self
        button.accessibilityLabel = accessibilityLabel
        context.coordinator.installMenu(on: button)
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

        func installMenu(on button: UIButton) {
            var rows: [UIMenuElement] = [
                Self.action("Profile", "person.crop.circle") { [parent] in
                    parent.onProfile()
                }
            ]
            if parent.usesSilo {
                let switchProfile = parent.onSwitchToProfile
                let others = parent.householdProfiles.filter { $0.id != parent.currentProfileID }
                if !others.isEmpty {
                    let items = others.map { profile in
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
            }
            if let onSessions = parent.onSessions {
                rows.append(
                    Self.action("Sessions", "play.tv") {
                        onSessions()
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
                        title: parent.usesSilo ? "Switch Account" : "Switch User",
                        image: UIImage(systemName: "person.2"),
                        children: users
                    )
                )
            }
            rows.append(contentsOf: [
                Self.action(parent.usesSilo ? "Add Account" : "Add User", "person.badge.plus") { [parent] in
                    parent.onAddUser()
                },
                Self.action("Settings", "gearshape") { [parent] in
                    parent.onSettings()
                }
            ])
            button.menu = UIMenu(children: [
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
            ])
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
        Task { @MainActor in
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
            case .scheduledTasks:
                if session.usesSilo {
                    SiloTasksView()
                        .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
                } else {
                    ScheduledTasksView()
                        .profileSheetToolbar("Done") { ProfilePresentation.dismiss() }
                }
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
