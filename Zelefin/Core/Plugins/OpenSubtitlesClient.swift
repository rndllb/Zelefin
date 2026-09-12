import Foundation
import Get
import JellyfinAPI

enum JellyfinPluginCatalog {
    static func activeNames(client: JellyfinClient) async -> [String] {
        guard let plugins = try? await client.send(Paths.getPlugins).value else { return [] }
        return plugins.compactMap { plugin in
            switch plugin.status {
            case .disabled, .deleted, .malfunctioned:
                return nil
            default:
                return plugin.name
            }
        }
    }
}

enum OpenSubtitlesPlugin {
    static func isInstalled(names: [String]) -> Bool {
        names.contains { name in
            let compact = name.lowercased().filter(\.isLetter)
            return compact.contains("opensubtitles")
        }
    }
}

enum RemoteSubtitleOffer {
    /// Jellyfin lets administrators and users with Edit Subtitles manage remote subtitles.
    static func canManageSubtitles(isAdministrator: Bool, enableSubtitleManagement: Bool) -> Bool {
        isAdministrator || enableSubtitleManagement
    }

    /// `/Plugins` is often admin-only. An empty list is not proof Open Subtitles is missing.
    static func pluginAvailable(
        listed: Bool,
        catalogNames: [String],
        canManageSubtitles: Bool,
        canListPlugins: Bool
    ) -> Bool {
        if listed { return true }
        if !catalogNames.isEmpty { return false }
        if canListPlugins { return false }
        return canManageSubtitles
    }

    static func shouldShowAddSubtitles(
        canManageSubtitles: Bool,
        pluginAvailable: Bool,
        supportsRemote: Bool
    ) -> Bool {
        canManageSubtitles && pluginAvailable && supportsRemote
    }
}

enum SubtitleCatalogRefresh {
    static let itemIDKey = "itemID"

    static func shouldRefreshDetail(
        detailItemID: String,
        episodeIDs: [String],
        savedItemID: String
    ) -> Bool {
        savedItemID == detailItemID || episodeIDs.contains(savedItemID)
    }

    static func postSaved(itemID: String) {
        NotificationCenter.default.post(
            name: .zelefinSubtitlesSaved,
            object: nil,
            userInfo: [itemIDKey: itemID]
        )
    }
}

extension Notification.Name {
    static let zelefinSubtitlesSaved = Notification.Name("zelefin.subtitlesSaved")
}

struct SubtitleSearchLanguage: Hashable, Identifiable, Sendable {
    let code: String
    let name: String

    var id: String { code }

    static let choices: [SubtitleSearchLanguage] = {
        let codes = [
            "en", "es", "fr", "de", "it", "pt", "nl", "sv", "nb", "da", "fi",
            "pl", "cs", "hu", "ro", "el", "tr", "ru", "uk", "ar", "he", "hi",
            "ja", "ko", "zh",
        ]
        var seen = Set<String>()
        var list: [SubtitleSearchLanguage] = []
        for code in preferredCodes + codes {
            let normalized = code.lowercased()
            guard seen.insert(normalized).inserted else { continue }
            list.append(SubtitleSearchLanguage(code: normalized, name: displayName(for: normalized)))
        }
        return list
    }()

    static var preferred: SubtitleSearchLanguage {
        choices.first ?? SubtitleSearchLanguage(code: "en", name: "English")
    }

    private static var preferredCodes: [String] {
        Locale.preferredLanguages.compactMap { identifier in
            Locale(identifier: identifier).language.languageCode?.identifier
        }
    }

    private static func displayName(for code: String) -> String {
        let name = Locale.current.localizedString(forLanguageCode: code)
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return code.uppercased()
        }
        return trimmed.localizedCapitalized
    }
}

struct RemoteSubtitleMatch: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detail: String
    let isHashMatch: Bool

    init(id: String, title: String, detail: String, isHashMatch: Bool) {
        self.id = id
        self.title = title
        self.detail = detail
        self.isHashMatch = isHashMatch
    }

    init?(_ info: RemoteSubtitleInfo) {
        let subtitleID = info.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !subtitleID.isEmpty else { return nil }
        id = subtitleID
        let release = info.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        title = release.isEmpty ? "Subtitle" : release
        isHashMatch = info.isHashMatch == true
        detail = Self.detailLine(from: info)
    }

    private static func detailLine(from info: RemoteSubtitleInfo) -> String {
        var parts: [String] = []
        if let provider = info.providerName, !provider.isEmpty {
            parts.append(provider)
        }
        if let format = info.format, !format.isEmpty {
            parts.append(format.uppercased())
        }
        if info.isHashMatch == true {
            parts.append("Hash match")
        }
        if info.isHearingImpaired == true {
            parts.append("SDH")
        }
        if info.isForced == true {
            parts.append("Forced")
        }
        if info.isMachineTranslated == true || info.isAiTranslated == true {
            parts.append("Translated")
        }
        if let count = info.downloadCount, count > 0 {
            parts.append("\(count.formatted()) downloads")
        }
        return parts.joined(separator: " · ")
    }
}

struct OpenSubtitlesClient: Sendable {
    private let client: JellyfinClient

    init(client: JellyfinClient) {
        self.client = client
    }

    func isInstalled() async -> Bool {
        OpenSubtitlesPlugin.isInstalled(names: await JellyfinPluginCatalog.activeNames(client: client))
    }

    func search(itemID: String, language: String, perfectMatch: Bool) async throws -> [RemoteSubtitleMatch] {
        do {
            let results = try await client.send(
                Paths.searchRemoteSubtitles(
                    itemID: itemID,
                    language: language,
                    isPerfectMatch: perfectMatch ? true : nil
                )
            ).value
            return results.compactMap(RemoteSubtitleMatch.init)
        } catch let APIError.unacceptableStatusCode(status) where status == 401 || status == 403 {
            throw ZelefinError.server("This account cannot search subtitles on this server.")
        } catch let APIError.unacceptableStatusCode(status) where status == 404 {
            throw ZelefinError.server("Jellyfin could not find this title.")
        }
    }

    func download(itemID: String, subtitleID: String, userID: String) async throws {
        let before = await subtitleKeys(itemID: itemID, userID: userID)
        do {
            _ = try await client.send(
                Paths.downloadRemoteSubtitles(itemID: itemID, subtitleID: subtitleID)
            )
        } catch let APIError.unacceptableStatusCode(status) where status == 401 || status == 403 {
            throw ZelefinError.server("This account cannot download subtitles on this server.")
        } catch let APIError.unacceptableStatusCode(status) where status == 404 {
            throw ZelefinError.server("Jellyfin could not download that subtitle.")
        }
        await refreshItem(itemID: itemID)
        guard !userID.isEmpty else { return }
        await waitForSubtitleChange(itemID: itemID, userID: userID, from: before)
    }

    private func refreshItem(itemID: String) async {
        _ = try? await client.send(
            Paths.refreshItem(
                itemID: itemID,
                parameters: .init(
                    metadataRefreshMode: .validationOnly,
                    imageRefreshMode: MetadataRefreshMode.none
                )
            )
        )
    }

    private func waitForSubtitleChange(itemID: String, userID: String, from baseline: [String]) async {
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(400))
            let next = await subtitleKeys(itemID: itemID, userID: userID)
            if next != baseline {
                return
            }
        }
    }

    func subtitleKeys(itemID: String, userID: String) async -> [String] {
        let result = try? await client.send(
            Paths.getItems(
                parameters: .init(
                    userID: userID.isEmpty ? nil : userID,
                    limit: 1,
                    fields: [.mediaStreams, .mediaSources],
                    ids: [itemID],
                    enableTotalRecordCount: false,
                    enableImages: false
                )
            )
        ).value
        let item = result?.items?.first
        let streams = item?.mediaStreams ?? item?.mediaSources?.first?.mediaStreams ?? []
        return streams.compactMap { stream in
            guard stream.type == .subtitle, let index = stream.index else { return nil }
            return "\(index)|\(stream.codec ?? "")|\(stream.isExternal == true)"
        }
    }
}
