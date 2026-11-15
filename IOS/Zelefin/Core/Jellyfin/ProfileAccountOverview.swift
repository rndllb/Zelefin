import Foundation
import JellyfinAPI

/// Read-only facts about the signed-in account for the Profile screen.
struct ProfileAccountOverview: Equatable, Sendable {
    struct Capability: Identifiable, Equatable, Sendable {
        let id: String
        let title: String
        let isAllowed: Bool
    }

    var displayName: String
    var role: String
    var hasPassword: Bool
    var lastLogin: Date?
    var lastActivity: Date?
    var librariesSummary: String
    var maxRatingLabel: String
    var unratedLabel: String
    var accessScheduleLabel: String
    var limitsFooter: String
    var capabilities: [Capability]
    var audioLanguageLabel: String
    var playDefaultAudio: Bool
    var subtitleLanguageLabel: String
    var subtitleModeLabel: String
    var autoPlayNextEpisode: Bool
    var rememberAudio: Bool
    var rememberSubtitles: Bool
    var hideWatchedInLatest: Bool

    static func make(
        user: UserDto,
        libraries: [MediaLibrary],
        ratingNames: [Int: String]
    ) -> ProfileAccountOverview {
        let policy = user.policy
        let configuration = user.configuration ?? UserConfiguration()
        let name = user.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let blocked = Set(policy?.blockUnratedItems ?? [])
        let maxRating = policy?.maxParentalRating
        let schedules = policy?.accessSchedules ?? []
        let enableAllFolders = policy?.enableAllFolders ?? true
        let enabledFolderIDs = Set(policy?.enabledFolders ?? [])

        let librariesSummary: String
        if enableAllFolders {
            librariesSummary = "All libraries"
        } else {
            let names = libraries
                .filter { enabledFolderIDs.contains($0.id) }
                .map(\.name)
                .filter { !$0.isEmpty }
            librariesSummary = names.isEmpty ? "No libraries" : names.joined(separator: ", ")
        }

        let maxRatingLabel: String
        if let maxRating {
            maxRatingLabel = ratingNames[maxRating] ?? "Level \(maxRating)"
        } else {
            maxRatingLabel = "None"
        }

        let unratedLabel = blocked.isEmpty
            ? "Shown"
            : blocked.map(\.settingsTitle).sorted().joined(separator: ", ") + " blocked"

        let accessScheduleLabel: String
        if schedules.isEmpty {
            accessScheduleLabel = "Any time"
        } else {
            accessScheduleLabel = "\(schedules.count) window\(schedules.count == 1 ? "" : "s")"
        }

        let hasLimits = maxRating != nil || !blocked.isEmpty || !schedules.isEmpty
        let limitsFooter = hasLimits
            ? "These limits come from the server account. An administrator can change them."
            : "No content limits apply to this account."

        let syncPlayAllowed: Bool = {
            guard let access = policy?.syncPlayAccess else { return false }
            switch access {
            case .createAndJoinGroups, .joinGroups:
                return true
            case .none:
                return false
            @unknown default:
                return false
            }
        }()

        let capabilities: [Capability] = [
            .init(id: "playback", title: "Play media", isAllowed: policy?.enableMediaPlayback ?? true),
            .init(id: "download", title: "Download", isAllowed: policy?.enableContentDownloading ?? false),
            .init(id: "subtitles", title: "Search for subtitles", isAllowed: policy?.enableSubtitleManagement == true),
            .init(id: "syncplay", title: "Watch together", isAllowed: syncPlayAllowed),
            .init(id: "remote", title: "Remote access", isAllowed: policy?.enableRemoteAccess ?? true),
            .init(id: "livetv", title: "Live TV", isAllowed: policy?.enableLiveTvAccess ?? false),
            .init(id: "video-transcode", title: "Video transcoding", isAllowed: policy?.enableVideoPlaybackTranscoding ?? true),
            .init(id: "audio-transcode", title: "Audio transcoding", isAllowed: policy?.enableAudioPlaybackTranscoding ?? true),
            .init(id: "remux", title: "Remuxing", isAllowed: policy?.enablePlaybackRemuxing ?? true),
            .init(
                id: "force-remote-transcode",
                title: "Always transcode remote streams",
                isAllowed: policy?.isForceRemoteSourceTranscoding ?? false
            ),
            .init(id: "public-share", title: "Public sharing", isAllowed: policy?.enablePublicSharing ?? false),
            .init(id: "collections", title: "Manage collections", isAllowed: policy?.enableCollectionManagement == true),
            .init(id: "delete", title: "Delete media", isAllowed: policy?.enableContentDeletion ?? false)
        ]

        return ProfileAccountOverview(
            displayName: name.isEmpty ? "Account" : name,
            role: policy?.isAdministrator == true ? "Administrator" : "User",
            hasPassword: user.hasPassword ?? true,
            lastLogin: user.lastLoginDate,
            lastActivity: user.lastActivityDate,
            librariesSummary: librariesSummary,
            maxRatingLabel: maxRatingLabel,
            unratedLabel: unratedLabel,
            accessScheduleLabel: accessScheduleLabel,
            limitsFooter: limitsFooter,
            capabilities: capabilities,
            audioLanguageLabel: PlaybackLanguage.displayName(
                for: ServerLanguageCode.fromServer(configuration.audioLanguagePreference)
            ),
            playDefaultAudio: configuration.isPlayDefaultAudioTrack ?? false,
            subtitleLanguageLabel: {
                let code = ServerLanguageCode.fromServer(configuration.subtitleLanguagePreference)
                return code.isEmpty ? "Default" : PlaybackLanguage.displayName(for: code)
            }(),
            subtitleModeLabel: (configuration.subtitleMode ?? .default).title,
            autoPlayNextEpisode: configuration.enableNextEpisodeAutoPlay ?? true,
            rememberAudio: configuration.isRememberAudioSelections ?? true,
            rememberSubtitles: configuration.isRememberSubtitleSelections ?? true,
            hideWatchedInLatest: configuration.isHidePlayedInLatest ?? false
        )
    }
}

enum ProfileAccountFormatting {
    static func absolute(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
