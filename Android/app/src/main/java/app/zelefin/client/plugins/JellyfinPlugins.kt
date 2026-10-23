package app.zelefin.client.plugins

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.ServerUrl
import app.zelefin.core.LenientJson
import app.zelefin.core.ZelefinException
import java.net.URLEncoder
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class JellyfinPluginState(
    val introSkipper: Boolean = false,
    val openSubtitles: Boolean = false,
    val enhanced: Boolean = false,
    val enhancedRemoveContinueWatching: Boolean = false,
    val companion: Boolean = false,
    val names: List<String> = emptyList(),
)

object JellyfinPlugins {
    /** Names of plugins from `GET /Plugins` that are not Disabled, Deleted, or Malfunctioned. Empty on failure. */
    suspend fun activeNames(baseUrl: String, accessToken: String): List<String> {
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", "/Plugins") ?: return emptyList()
        if (!response.isSuccess) return emptyList()
        val rows = PluginJson.parse(response.body) as? JsonArray ?: return emptyList()
        return rows.mapNotNull { row ->
            val plugin = row as? JsonObject ?: return@mapNotNull null
            val status = PluginJson.string(plugin, "Status")?.lowercase()
            if (status == "disabled" || status == "deleted" || status == "malfunctioned") return@mapNotNull null
            PluginJson.string(plugin, "Name")
        }
    }

    /** `(Policy.IsAdministrator, Policy.EnableSubtitleManagement)` from `GET /Users/{userId}`; `(false, false)` on failure. */
    suspend fun userPolicy(baseUrl: String, accessToken: String, userId: String): Pair<Boolean, Boolean> {
        if (userId.isBlank()) return false to false
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", "/Users/${PluginHttp.segment(userId)}")
            ?: return false to false
        if (!response.isSuccess) return false to false
        val user = PluginJson.obj(response.body) ?: return false to false
        val policy = PluginJson.value(user, "Policy") as? JsonObject ?: return false to false
        val isAdmin = PluginJson.bool(policy, "IsAdministrator") ?: false
        val subtitles = PluginJson.bool(policy, "EnableSubtitleManagement") ?: false
        return isAdmin to subtitles
    }

    /**
     * Mirrors iOS `SessionStore.detectPlugins()`. [canManageSubtitles] should be
     * `RemoteSubtitleOffer.canManageSubtitles(isAdmin, enableSubtitleManagement)`.
     */
    suspend fun detect(
        baseUrl: String,
        token: String,
        userId: String,
        isAdmin: Boolean,
        canManageSubtitles: Boolean,
    ): JellyfinPluginState {
        val names = activeNames(baseUrl, token)
        val introSkipper = IntroSkipperPlugin.isInstalled(names)
        val openSubtitles = RemoteSubtitleOffer.pluginAvailable(
            listed = OpenSubtitlesPlugin.isInstalled(names),
            catalogNames = names,
            canManageSubtitles = canManageSubtitles,
            canListPlugins = isAdmin,
        )
        val enhancedClient = JellyfinEnhancedClient(baseUrl, token, userId)
        val enhanced = JellyfinEnhancedPlugin.isInstalled(names) || enhancedClient.isReachable()
        val removeContinueWatching = enhanced && enhancedClient.removeContinueWatchingEnabled()
        val companion = ZelefinCompanionPlugin.isInstalled(names) ||
            ZelefinCompanionClient(baseUrl, token).config() != null
        return JellyfinPluginState(
            introSkipper = introSkipper,
            openSubtitles = openSubtitles,
            enhanced = enhanced,
            enhancedRemoveContinueWatching = removeContinueWatching,
            companion = companion,
            names = names,
        )
    }
}

/**
 * Mirrors iOS `ZelefinPluginInstaller`: adds the Zelefin catalog to Jellyfin's plugin
 * repositories when missing, installs the plugin from it, and can restart the server so it loads.
 * Every call needs an administrator token.
 */
class ZelefinPluginInstaller(private val baseUrl: String, private val accessToken: String) {
    suspend fun install() {
        ensureRepository()
        val path = "/Packages/Installed/${PluginHttp.segment(PACKAGE_NAME)}" +
            "?assemblyGuid=$ASSEMBLY_GUID&repositoryUrl=${PluginHttp.segment(REPOSITORY_URL)}"
        val response = PluginHttp.send(baseUrl, accessToken, "POST", path)
        if (!response.isSuccess) throw ZelefinException.server(failureMessage(response, "Jellyfin could not install the Zelefin plugin"))
    }

    suspend fun restartServer() {
        val response = PluginHttp.send(baseUrl, accessToken, "POST", "/System/Restart")
        if (!response.isSuccess) throw ZelefinException.server(failureMessage(response, "Jellyfin could not restart"))
    }

    private suspend fun ensureRepository() {
        val response = PluginHttp.send(baseUrl, accessToken, "GET", "/Repositories")
        if (!response.isSuccess) throw ZelefinException.server(failureMessage(response, "Jellyfin could not list its plugin catalogs"))
        val current = PluginJson.parse(response.body) as? JsonArray ?: JsonArray(emptyList())
        val present = current.any { row ->
            (row as? JsonObject)?.let { PluginJson.string(it, "Url") }?.let(::normalize) == normalize(REPOSITORY_URL)
        }
        if (present) return
        val next = JsonArray(
            current + JsonObject(
                mapOf(
                    "Name" to JsonPrimitive(REPOSITORY_NAME),
                    "Url" to JsonPrimitive(REPOSITORY_URL),
                    "Enabled" to JsonPrimitive(true),
                ),
            ),
        )
        val saved = PluginHttp.send(baseUrl, accessToken, "POST", "/Repositories", jsonBody = next.toString())
        if (!saved.isSuccess) throw ZelefinException.server(failureMessage(saved, "Jellyfin could not add the Zelefin catalog"))
    }

    private fun normalize(url: String) = url.trim().trimEnd('/').lowercase()

    private fun failureMessage(response: PluginResponse, prefix: String): String = when (response.status) {
        401, 403 -> "$prefix. Sign in as a Jellyfin administrator."
        else -> "$prefix (HTTP ${response.status})."
    }

    companion object {
        const val REPOSITORY_NAME = "Zelefin"
        const val REPOSITORY_URL = "https://raw.githubusercontent.com/rndllb/Zelefin-Plugin/main/manifest.json"
        const val PACKAGE_NAME = "Zelefin"
        const val ASSEMBLY_GUID = "b18e5910-21dd-49fe-a150-bb21ec3755e8"
    }
}

internal class PluginResponse(val status: Int, val body: String, val headers: Map<String, String>) {
    val isSuccess: Boolean get() = status in 200..299
    val isGatewayChallenge: Boolean get() = AccessGateway.isChallenge(status, headers, body)
}

internal object PluginHttp {
    private val jsonType = "application/json".toMediaType()

    fun segment(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    suspend fun send(
        baseUrl: String,
        accessToken: String,
        method: String,
        path: String,
        jsonBody: String? = null,
    ): PluginResponse = withContext(Dispatchers.IO) {
        val url = ServerUrl.join(baseUrl, path) ?: throw ZelefinException.invalidServerUrl()
        val body = when {
            jsonBody != null -> jsonBody.toRequestBody(jsonType)
            method == "POST" || method == "PUT" -> ByteArray(0).toRequestBody(null)
            else -> null
        }
        val request = Request.Builder()
            .url(url)
            .method(method, body)
            .header("Accept", "application/json")
            .header("Cache-Control", "no-cache")
            .apply {
                if (accessToken.isNotEmpty()) {
                    header("Authorization", "MediaBrowser Token=\"$accessToken\"")
                    header("X-Emby-Token", accessToken)
                }
            }
            .build()
        GatewayHttp.client.newCall(request).execute().use { response ->
            val headers = response.headers.names().associateWith { response.header(it).orEmpty() }
            PluginResponse(response.code, response.body?.string().orEmpty(), headers)
        }
    }

    suspend fun sendOrNull(
        baseUrl: String,
        accessToken: String,
        method: String,
        path: String,
        jsonBody: String? = null,
    ): PluginResponse? = try {
        send(baseUrl, accessToken, method, path, jsonBody)
    } catch (cancel: CancellationException) {
        throw cancel
    } catch (_: Exception) {
        null
    }
}

/** Case-insensitive JSON readers matching iOS `JellyfinEnhancedJSON` (PascalCase and camelCase keys). */
internal object PluginJson {
    fun parse(text: String): JsonElement? = runCatching { LenientJson.parse(text) }.getOrNull()

    fun obj(text: String): JsonObject? = parse(text) as? JsonObject

    fun value(obj: JsonObject, vararg keys: String): JsonElement? {
        for (key in keys) {
            obj[key]?.takeUnless { it is JsonNull }?.let { return it }
            obj.entries.firstOrNull { it.key.equals(key, ignoreCase = true) }
                ?.value?.takeUnless { it is JsonNull }?.let { return it }
        }
        return null
    }

    fun string(obj: JsonObject, vararg keys: String): String? {
        for (key in keys) {
            val primitive = value(obj, key) as? JsonPrimitive ?: continue
            if (!primitive.isString) continue
            primitive.content.trim().takeIf { it.isNotEmpty() }?.let { return it }
        }
        return null
    }

    fun int(obj: JsonObject, vararg keys: String): Int? {
        for (key in keys) {
            val primitive = value(obj, key) as? JsonPrimitive ?: continue
            if (primitive.isString) {
                primitive.content.trim().toIntOrNull()?.let { return it }
                continue
            }
            primitive.longOrNull?.let { return it.toInt() }
            primitive.doubleOrNull?.let { return it.toInt() }
        }
        return null
    }

    fun long(obj: JsonObject, vararg keys: String): Long? {
        for (key in keys) {
            val primitive = value(obj, key) as? JsonPrimitive ?: continue
            if (primitive.isString) {
                primitive.content.trim().toLongOrNull()?.let { return it }
                continue
            }
            primitive.longOrNull?.let { return it }
            primitive.doubleOrNull?.let { return it.toLong() }
        }
        return null
    }

    fun double(obj: JsonObject, vararg keys: String): Double? {
        for (key in keys) {
            val primitive = value(obj, key) as? JsonPrimitive ?: continue
            if (primitive.isString) continue
            primitive.doubleOrNull?.let { return it }
        }
        return null
    }

    fun bool(obj: JsonObject, vararg keys: String): Boolean? {
        for (key in keys) {
            val primitive = value(obj, key) as? JsonPrimitive ?: continue
            if (primitive.isString) continue
            primitive.booleanOrNull?.let { return it }
            primitive.doubleOrNull?.let { return it != 0.0 }
        }
        return null
    }

    fun stringList(obj: JsonObject, vararg keys: String): List<String> {
        for (key in keys) {
            val array = value(obj, key) as? JsonArray ?: continue
            return array.mapNotNull { element ->
                (element as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.takeIf { it.isNotEmpty() }
            }
        }
        return emptyList()
    }
}
