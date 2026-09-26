import Foundation
import Observation

@MainActor
@Observable
final class DeepLinkStore {
    var presentedItemID: String?
    var errorMessage: String?
    var browserFallbackURL: URL?
    private var pending: URL?
    private var pendingItemID: String?

    var presentedItem: DeepLinkItem? {
        get { presentedItemID.map(DeepLinkItem.init) }
        set { presentedItemID = newValue?.id }
    }

    func openLibraryItem(_ itemID: String, session: SessionStore) {
        let trimmed = itemID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if session.isSignedIn {
            presentedItemID = trimmed
        } else {
            pendingItemID = trimmed
        }
    }

    func handle(_ url: URL, session: SessionStore) async {
        guard TitleShare.parse(url) != nil else { return }
        if !session.isSignedIn {
            pending = url
            return
        }
        await open(url, session: session)
    }

    func flushPending(session: SessionStore) async {
        if session.isSignedIn, let pendingItemID {
            presentedItemID = pendingItemID
            self.pendingItemID = nil
        }
        guard let pending else { return }
        self.pending = nil
        await handle(pending, session: session)
    }

    func dismissPresentedItem() {
        presentedItemID = nil
    }

    func clearError() {
        errorMessage = nil
        browserFallbackURL = nil
    }

    private func open(_ url: URL, session: SessionStore) async {
        guard let incoming = TitleShare.parse(url) else { return }
        let key = TitleShare.fingerprint(incoming.serverURL)
        if let current = session.session, TitleShare.fingerprint(current.serverURL) == key {
            presentedItemID = incoming.itemID
            return
        }
        if let account = session.accounts.first(where: { TitleShare.fingerprint($0.serverURL) == key }) {
            await session.switchTo(account)
            presentedItemID = incoming.itemID
            return
        }
        let host = incoming.serverURL.host ?? "another server"
        errorMessage = "This title is on \(host). Sign in to that server to open it in Zelefin."
        browserFallbackURL = TitleShare.jellyfinDetailsURL(
            serverURL: incoming.serverURL,
            itemID: incoming.itemID
        )
    }
}

struct DeepLinkItem: Identifiable, Hashable {
    var id: String
}
