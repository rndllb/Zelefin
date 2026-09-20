import Foundation
import Observation
import StoreKit

enum PlusProductID: String, CaseIterable, Sendable {
    case annual = "app.zelefin.plus.annual"
    case lifetime = "app.zelefin.plus.lifetime"

    var title: String {
        switch self {
        case .annual: "Annual"
        case .lifetime: "Lifetime"
        }
    }

    var subtitle: String {
        switch self {
        case .annual: "7-day free trial"
        case .lifetime: "Pay once"
        }
    }

    var fallbackPrice: String {
        switch self {
        case .annual: "$9.99/year"
        case .lifetime: "$24.99"
        }
    }
}

enum PlusDebugOverride: String, CaseIterable, Identifiable, Sendable {
    case store
    case free
    case trial
    case plus
    case lifetime

    static let storageKey = "zelefin.plus.debug-override"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .store: "Fake Store"
        case .free: "Locked"
        case .trial: "Trial"
        case .plus: "Annual"
        case .lifetime: "Lifetime"
        }
    }
}

enum PlusStatus: Equatable, Sendable {
    case locked
    case trial
    case plus
    case lifetime

    var isUnlocked: Bool { self != .locked }

    var settingsLabel: String {
        switch self {
        case .locked: "Not included"
        case .trial: "Free trial"
        case .plus: "Annual"
        case .lifetime: "Lifetime"
        }
    }
}

enum PlusFeature: String, CaseIterable, Identifiable, Hashable, Sendable {
    case downloads
    case extraAccounts
    case interface
    case liveTV
    case sessions
    case syncPlay
    case adminTools

    var id: String { rawValue }

    var paywallTitle: String {
        switch self {
        case .downloads: "Downloads"
        case .extraAccounts: "Extra Accounts"
        case .interface: "Home and Tabs"
        case .liveTV: "Live TV"
        case .sessions: "Sessions"
        case .syncPlay: "SyncPlay"
        case .adminTools: "Admin Tools"
        }
    }

    /// Live TV, Sessions, and SyncPlay are provided by the Jellyfin server, not
    /// Zelefin, so the copy says so. A few features read differently between the
    /// two backends, hence the `usesSilo` flag.
    func paywallMessage(usesSilo: Bool) -> String {
        switch self {
        case .downloads:
            "Save titles on this iPhone or iPad to watch without a network. Titles already on this device still play."
        case .extraAccounts:
            usesSilo
                ? "Keep more than one Silo account on this device."
                : "Keep more than one Jellyfin user on this device."
        case .interface:
            "Reorder Home rows, turn extra rows on, and customize tabs. Without Plus, Home is Featured, Continue Watching, and recently added movies and shows."
        case .liveTV:
            "Watch the live TV from your Jellyfin server — On Now, the guide, channels, and recordings."
        case .sessions:
            "See what’s playing on your Jellyfin server and send playback to another device."
        case .syncPlay:
            "Watch in sync with other people on your Jellyfin server."
        case .adminTools:
            usesSilo
                ? "Users, invitations, sessions, libraries, transcode nodes, and server logs."
                : "Users, scheduled tasks, activity, backups, branding, and library scans."
        }
    }

    /// Features worth advertising on the paywall for the active backend. Live TV,
    /// Sessions, and SyncPlay are Jellyfin-only, so they are left off the Silo
    /// paywall where they can't be used.
    static func included(usesSilo: Bool) -> [PlusFeature] {
        usesSilo
            ? [.downloads, .extraAccounts, .interface, .adminTools]
            : allCases
    }

    var systemImage: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .extraAccounts: "person.badge.plus"
        case .interface: "rectangle.3.group"
        case .liveTV: "dot.radiowaves.left.and.right"
        case .sessions: "play.tv"
        case .syncPlay: "person.2.wave.2"
        case .adminTools: "wrench.and.screwdriver"
        }
    }

    var lockTitle: String { paywallTitle }

    var lockMessage: String {
        "Zelefin Plus includes \(paywallTitle). Sign in, browse, and Play stay free."
    }
}

enum PlusStatusResolver: Sendable {
    static func status(
        isReviewDemo: Bool,
        debugOverride: PlusDebugOverride?,
        hasLifetime: Bool,
        hasAnnual: Bool,
        annualIsTrial: Bool
    ) -> PlusStatus {
        if isReviewDemo { return .lifetime }
        if let debugOverride {
            switch debugOverride {
            case .store:
                break
            case .free:
                return .locked
            case .trial:
                return .trial
            case .plus:
                return .plus
            case .lifetime:
                return .lifetime
            }
        }
        if hasLifetime { return .lifetime }
        if hasAnnual { return annualIsTrial ? .trial : .plus }
        return .locked
    }
}

@MainActor
@Observable
final class PlusEntitlement {
    static let shared = PlusEntitlement()

    var status: PlusStatus = .locked
    var requestedFeature: PlusFeature?
    var products: [Product] = []
    var isReviewDemo = false {
        didSet { applyStatus() }
    }
    var purchaseError: String?
    var isPurchasing = false
    var debugOverride: PlusDebugOverride {
        didSet {
            guard oldValue != debugOverride else { return }
            UserDefaults.standard.set(debugOverride.rawValue, forKey: PlusDebugOverride.storageKey)
            applyStatus()
        }
    }

    var isUnlocked: Bool { status.isUnlocked }

    private var hasLifetime = false
    private var hasAnnual = false
    private var annualIsTrial = false
    private var updatesTask: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: PlusDebugOverride.storageKey) ?? ""
        debugOverride = PlusDebugOverride(rawValue: raw) ?? .free
        applyStatus()
    }

    func start() async {
        updatesTask?.cancel()
        updatesTask = Task { await listenForTransactions() }
        await loadProducts()
        await refreshFromStore()
    }

    @discardableResult
    func require(_ feature: PlusFeature) -> Bool {
        if isUnlocked { return true }
        requestedFeature = feature
        return false
    }

    func request(_ feature: PlusFeature) {
        requestedFeature = feature
    }

    func priceLabel(for id: PlusProductID) -> String {
        guard let product = storeProduct(id) else { return id.fallbackPrice }
        switch id {
        case .annual: return "\(product.displayPrice)/year"
        case .lifetime: return product.displayPrice
        }
    }

    func purchase(_ id: PlusProductID) async {
        if storeProduct(id) == nil {
            await loadProducts()
        }
        guard let product = storeProduct(id) else {
            purchaseError = "Couldn’t load \(id.title) from the App Store yet."
            return
        }
        await purchase(product)
    }

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshFromStore()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    func restore() async {
        purchaseError = nil
        do {
            try await AppStore.sync()
            await refreshFromStore()
            if !isUnlocked {
                purchaseError = "No Plus purchase is on this Apple Account."
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func loadProducts() async {
        do {
            let loaded = try await Product.products(for: PlusProductID.allCases.map(\.rawValue))
            products = loaded.sorted { lhs, rhs in
                if lhs.id == PlusProductID.annual.rawValue { return true }
                if rhs.id == PlusProductID.annual.rawValue { return false }
                return lhs.id < rhs.id
            }
        } catch {
            products = []
        }
    }

    private func storeProduct(_ id: PlusProductID) -> Product? {
        products.first { $0.id == id.rawValue }
    }

    private func refreshFromStore() async {
        var lifetime = false
        var annual = false
        var trial = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            switch transaction.productID {
            case PlusProductID.lifetime.rawValue:
                lifetime = true
            case PlusProductID.annual.rawValue:
                annual = true
                if transaction.offer?.type == .introductory {
                    trial = true
                }
            default:
                break
            }
        }
        hasLifetime = lifetime
        hasAnnual = annual
        annualIsTrial = trial
        applyStatus()
    }

    private func applyStatus() {
        let override: PlusDebugOverride?
        #if DEBUG
        override = debugOverride
        #else
        override = nil
        #endif
        status = PlusStatusResolver.status(
            isReviewDemo: isReviewDemo,
            debugOverride: override,
            hasLifetime: hasLifetime,
            hasAnnual: hasAnnual,
            annualIsTrial: annualIsTrial
        )
    }

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard let transaction = try? checkVerified(result) else { continue }
            await transaction.finish()
            await refreshFromStore()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }
}
