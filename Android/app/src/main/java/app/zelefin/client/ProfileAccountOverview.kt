package app.zelefin.client

import app.zelefin.client.jellyfin.settingsTitle
import java.time.Duration
import java.time.Instant
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import org.jellyfin.sdk.model.api.SyncPlayUserAccessType
import org.jellyfin.sdk.model.api.UnratedItem
import org.jellyfin.sdk.model.api.UserDto

/**
 * Read-only facts about the signed-in account for the Profile screen.
 * Mirrors iOS `ProfileAccountOverview`.
 */
data class ProfileAccountOverview(
    val displayName: String,
    val role: String,
    val hasPassword: Boolean,
    val lastLoginLabel: String,
    val lastActivityLabel: String,
    val librariesSummary: String,
    val maxRatingLabel: String,
    val unratedLabel: String,
    val accessScheduleLabel: String,
    val limitsFooter: String,
    val capabilities: List<Capability>,
    val audioLanguageLabel: String,
    val playDefaultAudio: Boolean,
    val subtitleLanguageLabel: String,
    val subtitleModeLabel: String,
    val autoPlayNextEpisode: Boolean,
    val rememberAudio: Boolean,
    val rememberSubtitles: Boolean,
    val hideWatchedInLatest: Boolean,
) {
    data class Capability(val id: String, val title: String, val isAllowed: Boolean)

    companion object {
        fun fromJellyfin(user: UserDto, libraries: List<LibraryRoom>, ratingNames: Map<Int, String>): ProfileAccountOverview {
            val policy = user.policy
            val configuration = user.configuration
            val blocked = policy?.blockUnratedItems.orEmpty()
            val schedules = policy?.accessSchedules.orEmpty()
            val enableAll = policy?.enableAllFolders ?: true
            val enabled = policy?.enabledFolders.orEmpty().map { it.toString() }.toSet()
            val syncPlay = when (policy?.syncPlayAccess) {
                SyncPlayUserAccessType.CREATE_AND_JOIN_GROUPS, SyncPlayUserAccessType.JOIN_GROUPS -> true
                else -> false
            }
            val audioCode = ServerLanguageCode.fromServer(configuration?.audioLanguagePreference)
            val subtitleCode = ServerLanguageCode.fromServer(configuration?.subtitleLanguagePreference)
            return assemble(
                name = user.name,
                hasPassword = user.hasPassword,
                lastLogin = user.lastLoginDate as? LocalDateTime,
                lastActivity = user.lastActivityDate as? LocalDateTime,
                isAdministrator = policy?.isAdministrator == true,
                enableAllFolders = enableAll,
                enabledFolderIds = enabled,
                libraries = libraries,
                maxRating = policy?.maxParentalRating,
                ratingNames = ratingNames,
                blockedTitles = blocked.map { it.settingsTitle },
                scheduleCount = schedules.size,
                playMedia = policy?.enableMediaPlayback ?: true,
                download = policy?.enableContentDownloading ?: false,
                subtitles = policy?.enableSubtitleManagement == true,
                syncPlay = syncPlay,
                remote = policy?.enableRemoteAccess ?: true,
                liveTv = policy?.enableLiveTvAccess ?: false,
                videoTranscode = policy?.enableVideoPlaybackTranscoding ?: true,
                audioTranscode = policy?.enableAudioPlaybackTranscoding ?: true,
                remux = policy?.enablePlaybackRemuxing ?: true,
                forceRemoteTranscode = policy?.forceRemoteSourceTranscoding ?: false,
                publicShare = policy?.enablePublicSharing ?: false,
                collections = policy?.enableCollectionManagement == true,
                delete = policy?.enableContentDeletion ?: false,
                audioLanguageLabel = PlaybackLanguage.displayName(audioCode),
                playDefaultAudio = configuration?.playDefaultAudioTrack ?: false,
                subtitleLanguageLabel = if (subtitleCode.isEmpty()) "Default" else PlaybackLanguage.displayName(subtitleCode),
                subtitleModeLabel = configuration?.subtitleMode?.title ?: "Default",
                autoPlayNextEpisode = configuration?.enableNextEpisodeAutoPlay ?: true,
                rememberAudio = configuration?.rememberAudioSelections ?: true,
                rememberSubtitles = configuration?.rememberSubtitleSelections ?: true,
                hideWatchedInLatest = configuration?.hidePlayedInLatest ?: false,
            )
        }

        fun embyIsAdministrator(user: JsonObject): Boolean {
            val policy = user["Policy"] as? JsonObject ?: return false
            return (policy["IsAdministrator"] as? JsonPrimitive)?.contentOrNull == "true"
        }

        fun fromEmby(user: JsonObject, libraries: List<LibraryRoom>, ratingNames: Map<Int, String>): ProfileAccountOverview {
            val policy = user["Policy"] as? JsonObject
            val configuration = user["Configuration"] as? JsonObject
            val blocked = policy.strings("BlockUnratedItems").mapNotNull { raw ->
                UnratedItem.entries.firstOrNull { it.serialName.equals(raw, ignoreCase = true) }?.settingsTitle
            }
            val sync = policy.text("SyncPlayAccess")
            val audioCode = ServerLanguageCode.fromServer(configuration.text("AudioLanguagePreference"))
            val subtitleCode = ServerLanguageCode.fromServer(configuration.text("SubtitleLanguagePreference"))
            val mode = configuration.text("SubtitleMode")
            return assemble(
                name = user.text("Name"),
                hasPassword = user.bool("HasPassword", default = true),
                lastLogin = parseDate(user.text("LastLoginDate")),
                lastActivity = parseDate(user.text("LastActivityDate")),
                isAdministrator = policy.bool("IsAdministrator", default = false),
                enableAllFolders = policy.bool("EnableAllFolders", default = true),
                enabledFolderIds = policy.strings("EnabledFolders").toSet(),
                libraries = libraries,
                maxRating = (policy?.get("MaxParentalRating") as? JsonPrimitive)?.intOrNull,
                ratingNames = ratingNames,
                blockedTitles = blocked,
                scheduleCount = (policy?.get("AccessSchedules") as? JsonArray)?.size ?: 0,
                playMedia = policy.bool("EnableMediaPlayback", default = true),
                download = policy.bool("EnableContentDownloading", default = false),
                subtitles = policy.bool("EnableSubtitleManagement", default = false),
                syncPlay = sync.equals("CreateAndJoinGroups", ignoreCase = true) || sync.equals("JoinGroups", ignoreCase = true),
                remote = policy.bool("EnableRemoteAccess", default = true),
                liveTv = policy.bool("EnableLiveTvAccess", default = false),
                videoTranscode = policy.bool("EnableVideoPlaybackTranscoding", default = true),
                audioTranscode = policy.bool("EnableAudioPlaybackTranscoding", default = true),
                remux = policy.bool("EnablePlaybackRemuxing", default = true),
                forceRemoteTranscode = policy.bool("ForceRemoteSourceTranscoding", default = false),
                publicShare = policy.bool("EnablePublicSharing", default = false),
                collections = policy.bool("EnableCollectionManagement", default = false),
                delete = policy.bool("EnableContentDeletion", default = false),
                audioLanguageLabel = PlaybackLanguage.displayName(audioCode),
                playDefaultAudio = configuration.bool("PlayDefaultAudioTrack", default = false),
                subtitleLanguageLabel = if (subtitleCode.isEmpty()) "Default" else PlaybackLanguage.displayName(subtitleCode),
                subtitleModeLabel = when (mode?.lowercase()) {
                    "smart" -> "Smart"
                    "always" -> "Always"
                    "onlyforced" -> "Only Forced"
                    "none" -> "None"
                    else -> "Default"
                },
                autoPlayNextEpisode = configuration.bool("EnableNextEpisodeAutoPlay", default = true),
                rememberAudio = configuration.bool("RememberAudioSelections", default = true),
                rememberSubtitles = configuration.bool("RememberSubtitleSelections", default = true),
                hideWatchedInLatest = configuration.bool("HidePlayedInLatest", default = false),
            )
        }

        private fun assemble(
            name: String?,
            hasPassword: Boolean,
            lastLogin: LocalDateTime?,
            lastActivity: LocalDateTime?,
            isAdministrator: Boolean,
            enableAllFolders: Boolean,
            enabledFolderIds: Set<String>,
            libraries: List<LibraryRoom>,
            maxRating: Int?,
            ratingNames: Map<Int, String>,
            blockedTitles: List<String>,
            scheduleCount: Int,
            playMedia: Boolean,
            download: Boolean,
            subtitles: Boolean,
            syncPlay: Boolean,
            remote: Boolean,
            liveTv: Boolean,
            videoTranscode: Boolean,
            audioTranscode: Boolean,
            remux: Boolean,
            forceRemoteTranscode: Boolean,
            publicShare: Boolean,
            collections: Boolean,
            delete: Boolean,
            audioLanguageLabel: String,
            playDefaultAudio: Boolean,
            subtitleLanguageLabel: String,
            subtitleModeLabel: String,
            autoPlayNextEpisode: Boolean,
            rememberAudio: Boolean,
            rememberSubtitles: Boolean,
            hideWatchedInLatest: Boolean,
        ): ProfileAccountOverview {
            val librariesSummary = if (enableAllFolders) {
                "All libraries"
            } else {
                val names = libraries.filter { enabledFolderIds.contains(it.id) }.map { it.name }.filter { it.isNotEmpty() }
                if (names.isEmpty()) "No libraries" else names.joinToString(", ")
            }
            val maxRatingLabel = if (maxRating == null) "None" else ratingNames[maxRating] ?: "Level $maxRating"
            val unratedLabel = if (blockedTitles.isEmpty()) "Shown" else blockedTitles.sorted().joinToString(", ") + " blocked"
            val accessScheduleLabel = if (scheduleCount == 0) "Any time" else "$scheduleCount window${if (scheduleCount == 1) "" else "s"}"
            val hasLimits = maxRating != null || blockedTitles.isNotEmpty() || scheduleCount > 0
            return ProfileAccountOverview(
                displayName = name?.trim()?.ifEmpty { null } ?: "Account",
                role = if (isAdministrator) "Administrator" else "User",
                hasPassword = hasPassword,
                lastLoginLabel = absolute(lastLogin),
                lastActivityLabel = relative(lastActivity),
                librariesSummary = librariesSummary,
                maxRatingLabel = maxRatingLabel,
                unratedLabel = unratedLabel,
                accessScheduleLabel = accessScheduleLabel,
                limitsFooter = if (hasLimits) {
                    "These limits come from the server account. An administrator can change them."
                } else {
                    "No content limits apply to this account."
                },
                capabilities = listOf(
                    Capability("playback", "Play media", playMedia),
                    Capability("download", "Download", download),
                    Capability("subtitles", "Search for subtitles", subtitles),
                    Capability("syncplay", "Watch together", syncPlay),
                    Capability("remote", "Remote access", remote),
                    Capability("livetv", "Live TV", liveTv),
                    Capability("video-transcode", "Video transcoding", videoTranscode),
                    Capability("audio-transcode", "Audio transcoding", audioTranscode),
                    Capability("remux", "Remuxing", remux),
                    Capability("force-remote-transcode", "Always transcode remote streams", forceRemoteTranscode),
                    Capability("public-share", "Public sharing", publicShare),
                    Capability("collections", "Manage collections", collections),
                    Capability("delete", "Delete media", delete),
                ),
                audioLanguageLabel = audioLanguageLabel,
                playDefaultAudio = playDefaultAudio,
                subtitleLanguageLabel = subtitleLanguageLabel,
                subtitleModeLabel = subtitleModeLabel,
                autoPlayNextEpisode = autoPlayNextEpisode,
                rememberAudio = rememberAudio,
                rememberSubtitles = rememberSubtitles,
                hideWatchedInLatest = hideWatchedInLatest,
            )
        }

        private fun absolute(date: LocalDateTime?): String {
            date ?: return "—"
            return runCatching { date.format(absoluteFormat) }.getOrElse { "—" }
        }

        private fun relative(date: LocalDateTime?): String {
            date ?: return "—"
            val seconds = Duration.between(date, LocalDateTime.now()).seconds
            val formatter = android.icu.text.RelativeDateTimeFormatter.getInstance(
                android.icu.util.ULocale.getDefault(),
                null,
                android.icu.text.RelativeDateTimeFormatter.Style.LONG,
                android.icu.text.DisplayContext.CAPITALIZATION_NONE,
            )
            val past = seconds >= 0
            val abs = kotlin.math.abs(seconds)
            if (abs < 45) {
                return formatter.format(
                    android.icu.text.RelativeDateTimeFormatter.Direction.PLAIN,
                    android.icu.text.RelativeDateTimeFormatter.AbsoluteUnit.NOW,
                )
            }
            val direction = if (past) {
                android.icu.text.RelativeDateTimeFormatter.Direction.LAST
            } else {
                android.icu.text.RelativeDateTimeFormatter.Direction.NEXT
            }
            val (quantity, unit) = when {
                abs < 3_600 -> abs.coerceAtLeast(60) / 60 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.MINUTES
                abs < 86_400 -> abs / 3_600 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.HOURS
                abs < 604_800 -> abs / 86_400 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.DAYS
                abs < 2_592_000 -> abs / 604_800 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.WEEKS
                abs < 31_536_000 -> abs / 2_592_000 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.MONTHS
                else -> abs / 31_536_000 to android.icu.text.RelativeDateTimeFormatter.RelativeUnit.YEARS
            }
            return formatter.format(quantity.toDouble().coerceAtLeast(1.0), direction, unit)
        }

        private fun parseDate(raw: String?): LocalDateTime? {
            val text = raw?.trim()?.takeIf { it.isNotEmpty() } ?: return null
            return runCatching { OffsetDateTime.parse(text).toLocalDateTime() }.getOrNull()
                ?: runCatching { Instant.parse(text).atZone(ZoneId.systemDefault()).toLocalDateTime() }.getOrNull()
                ?: runCatching { LocalDateTime.parse(text) }.getOrNull()
        }

        private fun JsonObject?.bool(key: String, default: Boolean): Boolean {
            val primitive = this?.get(key) as? JsonPrimitive ?: return default
            return primitive.contentOrNull?.toBooleanStrictOrNull() ?: default
        }

        private fun JsonObject?.text(key: String): String? =
            (this?.get(key) as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }

        private fun JsonObject?.strings(key: String): List<String> =
            (this?.get(key) as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { value -> value.isNotBlank() } }

        private val absoluteFormat: DateTimeFormatter =
            DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).withLocale(Locale.getDefault())
    }
}
