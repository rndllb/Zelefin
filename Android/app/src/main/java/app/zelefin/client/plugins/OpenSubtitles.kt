package app.zelefin.client.plugins

import android.os.LocaleList
import app.zelefin.core.MediaKind
import app.zelefin.core.ZelefinException
import java.text.NumberFormat
import java.util.Locale
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

object OpenSubtitlesPlugin {
    fun isInstalled(names: List<String>): Boolean = names.any { name ->
        name.lowercase().filter { it.isLetter() }.contains("opensubtitles")
    }
}

object RemoteSubtitleOffer {
    /** Jellyfin lets administrators and users with Edit Subtitles manage remote subtitles. */
    fun canManageSubtitles(isAdministrator: Boolean, enableSubtitleManagement: Boolean): Boolean =
        isAdministrator || enableSubtitleManagement

    /** `/Plugins` is often admin-only. An empty list is not proof Open Subtitles is missing. */
    fun pluginAvailable(
        listed: Boolean,
        catalogNames: List<String>,
        canManageSubtitles: Boolean,
        canListPlugins: Boolean,
    ): Boolean {
        if (listed) return true
        if (catalogNames.isNotEmpty()) return false
        if (canListPlugins) return false
        return canManageSubtitles
    }

    fun shouldShowAddSubtitles(canManageSubtitles: Boolean, pluginAvailable: Boolean, supportsRemote: Boolean): Boolean =
        canManageSubtitles && pluginAvailable && supportsRemote

    fun supportsRemoteSubtitles(kind: MediaKind): Boolean = kind == MediaKind.Movie || kind == MediaKind.Episode
}

object SubtitleCatalogRefresh {
    fun shouldRefreshDetail(detailItemId: String, episodeIds: List<String>, savedItemId: String): Boolean =
        savedItemId == detailItemId || episodeIds.contains(savedItemId)
}

data class SubtitleSearchLanguage(val code: String, val name: String) {
    companion object {
        private val baseCodes = listOf(
            "en", "es", "fr", "de", "it", "pt", "nl", "sv", "nb", "da", "fi",
            "pl", "cs", "hu", "ro", "el", "tr", "ru", "uk", "ar", "he", "hi",
            "ja", "ko", "zh",
        )

        /** Device languages first, then the fixed iOS list; ISO 639-1 codes as sent by iOS. */
        val choices: List<SubtitleSearchLanguage> by lazy {
            val seen = mutableSetOf<String>()
            (preferredCodes() + baseCodes).mapNotNull { raw ->
                val code = raw.lowercase()
                if (code.isEmpty() || !seen.add(code)) null else SubtitleSearchLanguage(code, displayName(code))
            }
        }

        /** Stored subtitle preference when it is one of [choices]; otherwise the first choice. */
        fun preferred(storedCode: String?): SubtitleSearchLanguage {
            val stored = storedCode?.trim()?.lowercase()
            choices.firstOrNull { it.code == stored }?.let { return it }
            return choices.firstOrNull() ?: SubtitleSearchLanguage("en", "English")
        }

        private fun preferredCodes(): List<String> {
            val locales = LocaleList.getDefault()
            return (0 until locales.size()).mapNotNull { index ->
                locales[index]?.language?.let(::normalizeLanguage)?.takeIf { it.isNotEmpty() }
            }
        }

        // Java still reports some legacy ISO codes for Hebrew, Yiddish, and Indonesian.
        private fun normalizeLanguage(code: String): String = when (code) {
            "iw" -> "he"
            "ji" -> "yi"
            "in" -> "id"
            else -> code
        }

        private fun displayName(code: String): String {
            val current = Locale.getDefault()
            val name = Locale(code).getDisplayLanguage(current).trim()
            if (name.isEmpty() || name.equals(code, ignoreCase = true)) return code.uppercase()
            return name.split(" ").joinToString(" ") { word ->
                word.replaceFirstChar { if (it.isLowerCase()) it.titlecase(current) else it.toString() }
            }
        }
    }
}

data class RemoteSubtitle(
    val id: String,
    val name: String?,
    val providerName: String?,
    val language: String?,
    val format: String?,
    val author: String?,
    val comment: String?,
    val dateCreated: String?,
    val communityRating: Double?,
    val frameRate: Double?,
    val downloadCount: Int?,
    val isHashMatch: Boolean?,
    val isAiTranslated: Boolean?,
    val isMachineTranslated: Boolean?,
    val isForced: Boolean?,
    val isHearingImpaired: Boolean?,
) {
    val title: String get() = name?.trim()?.takeIf { it.isNotEmpty() } ?: "Subtitle"

    val hashMatch: Boolean get() = isHashMatch == true

    val detail: String
        get() {
            val parts = mutableListOf<String>()
            providerName?.takeIf { it.isNotEmpty() }?.let(parts::add)
            format?.takeIf { it.isNotEmpty() }?.let { parts += it.uppercase() }
            if (isHashMatch == true) parts += "Hash match"
            if (isHearingImpaired == true) parts += "SDH"
            if (isForced == true) parts += "Forced"
            if (isMachineTranslated == true || isAiTranslated == true) parts += "Translated"
            downloadCount?.takeIf { it > 0 }?.let { parts += "${NumberFormat.getInstance().format(it)} downloads" }
            return parts.joinToString(" · ")
        }

    companion object {
        /** Jellyfin `RemoteSubtitleInfo`; null when the id is missing or blank. */
        fun parse(obj: JsonObject): RemoteSubtitle? {
            val id = PluginJson.string(obj, "Id") ?: return null
            return RemoteSubtitle(
                id = id,
                name = PluginJson.string(obj, "Name"),
                providerName = PluginJson.string(obj, "ProviderName"),
                language = PluginJson.string(obj, "ThreeLetterISOLanguageName"),
                format = PluginJson.string(obj, "Format"),
                author = PluginJson.string(obj, "Author"),
                comment = PluginJson.string(obj, "Comment"),
                dateCreated = PluginJson.string(obj, "DateCreated"),
                communityRating = PluginJson.double(obj, "CommunityRating"),
                frameRate = PluginJson.double(obj, "FrameRate"),
                downloadCount = PluginJson.int(obj, "DownloadCount"),
                isHashMatch = PluginJson.bool(obj, "IsHashMatch"),
                isAiTranslated = PluginJson.bool(obj, "AiTranslated", "IsAiTranslated"),
                isMachineTranslated = PluginJson.bool(obj, "MachineTranslated", "IsMachineTranslated"),
                isForced = PluginJson.bool(obj, "Forced", "IsForced"),
                isHearingImpaired = PluginJson.bool(obj, "HearingImpaired", "IsHearingImpaired"),
            )
        }
    }
}

class OpenSubtitlesClient(
    private val baseUrl: String,
    private val accessToken: String,
    private val userId: String,
) {
    suspend fun isInstalled(): Boolean = OpenSubtitlesPlugin.isInstalled(JellyfinPlugins.activeNames(baseUrl, accessToken))

    /** [language] is passed through to Jellyfin, which accepts ISO 639-1 (iOS) or 639-2 codes. */
    suspend fun search(itemId: String, language: String, perfectMatch: Boolean?): List<RemoteSubtitle> {
        val path = buildString {
            append("/Items/${PluginHttp.segment(itemId)}/RemoteSearch/Subtitles/${PluginHttp.segment(language)}")
            if (perfectMatch == true) append("?isPerfectMatch=true")
        }
        val response = PluginHttp.send(baseUrl, accessToken, "GET", path)
        if (response.isGatewayChallenge) throw ZelefinException.accessGateway()
        when (response.status) {
            401, 403 -> throw ZelefinException.server("This account cannot search subtitles on this server.")
            404 -> throw ZelefinException.server("Jellyfin could not find this title.")
        }
        if (!response.isSuccess) throw ZelefinException.server("The server returned ${response.status}.")
        val rows = PluginJson.parse(response.body) as? JsonArray ?: return emptyList()
        return rows.mapNotNull { (it as? JsonObject)?.let(RemoteSubtitle::parse) }
    }

    /** Downloads onto the server, refreshes the item, then polls up to 20×400ms for the subtitle streams to change. */
    suspend fun download(itemId: String, subtitleId: String) {
        val before = subtitleKeys(itemId)
        val path = "/Items/${PluginHttp.segment(itemId)}/RemoteSearch/Subtitles/${PluginHttp.segment(subtitleId)}"
        val response = PluginHttp.send(baseUrl, accessToken, "POST", path)
        if (response.isGatewayChallenge) throw ZelefinException.accessGateway()
        when (response.status) {
            401, 403 -> throw ZelefinException.server("This account cannot download subtitles on this server.")
            404 -> throw ZelefinException.server("Jellyfin could not download that subtitle.")
        }
        if (!response.isSuccess) throw ZelefinException.server("The server returned ${response.status}.")
        refreshItem(itemId)
        if (userId.isEmpty()) return
        waitForSubtitleChange(itemId, before)
    }

    /** `index|codec|isExternal` for each subtitle stream on the item. */
    suspend fun subtitleKeys(itemId: String): List<String> {
        val query = buildList {
            if (userId.isNotEmpty()) add("userId=${PluginHttp.segment(userId)}")
            add("limit=1")
            add("fields=MediaStreams,MediaSources")
            add("ids=${PluginHttp.segment(itemId)}")
            add("enableTotalRecordCount=false")
            add("enableImages=false")
        }.joinToString("&")
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", "/Items?$query") ?: return emptyList()
        if (!response.isSuccess) return emptyList()
        val root = PluginJson.obj(response.body) ?: return emptyList()
        val item = (PluginJson.value(root, "Items") as? JsonArray)?.firstOrNull() as? JsonObject ?: return emptyList()
        val streams = PluginJson.value(item, "MediaStreams") as? JsonArray
            ?: ((PluginJson.value(item, "MediaSources") as? JsonArray)?.firstOrNull() as? JsonObject)
                ?.let { PluginJson.value(it, "MediaStreams") as? JsonArray }
            ?: return emptyList()
        return streams.mapNotNull { element ->
            val stream = element as? JsonObject ?: return@mapNotNull null
            if (!PluginJson.string(stream, "Type").equals("Subtitle", ignoreCase = true)) return@mapNotNull null
            val index = PluginJson.int(stream, "Index") ?: return@mapNotNull null
            val codec = PluginJson.string(stream, "Codec").orEmpty()
            val external = PluginJson.bool(stream, "IsExternal") == true
            "$index|$codec|$external"
        }
    }

    private suspend fun refreshItem(itemId: String) {
        PluginHttp.sendOrNull(
            baseUrl,
            accessToken,
            "POST",
            "/Items/${PluginHttp.segment(itemId)}/Refresh?metadataRefreshMode=ValidationOnly&imageRefreshMode=None",
        )
    }

    private suspend fun waitForSubtitleChange(itemId: String, baseline: List<String>) {
        repeat(20) {
            delay(400)
            if (subtitleKeys(itemId) != baseline) return
        }
    }
}
