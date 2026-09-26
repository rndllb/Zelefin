package app.zelefin.client.plugins

import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

object ZelefinCompanionPlugin {
    fun isInstalled(names: List<String>): Boolean = names.any { name ->
        val compact = name.lowercase().filter { it.isLetter() }
        compact == "zelefin" || compact.contains("jellyfinpluginzelefin")
    }
}

data class CompanionConfig(val notificationsReady: Boolean = false)

/** Mirrors iOS `ZelefinCompanionClient`; Android registers a Firebase token with `platform: android`. */
class ZelefinCompanionClient(private val baseUrl: String, private val accessToken: String) {
    /** `GET /Zelefin/config`; null when the plugin is missing or the response is not a config object. */
    suspend fun config(): CompanionConfig? {
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "GET", "/Zelefin/config") ?: return null
        if (!response.isSuccess) return null
        return parseConfig(response.body)
    }

    suspend fun isAvailable(): Boolean = config() != null

    /** `POST /Zelefin/device`. True when the plugin stored the token. */
    suspend fun registerDevice(token: String, deviceId: String, platform: String): Boolean {
        val body = buildJsonObject {
            put("token", token)
            put("deviceId", deviceId)
            put("platform", platform)
        }.toString()
        return PluginHttp.sendOrNull(baseUrl, accessToken, "POST", "/Zelefin/device", body)?.isSuccess == true
    }

    /** `DELETE /Zelefin/device/{deviceId}`. */
    suspend fun deleteDevice(deviceId: String): Boolean =
        PluginHttp.sendOrNull(baseUrl, accessToken, "DELETE", "/Zelefin/device/${PluginHttp.segment(deviceId)}")?.isSuccess == true

    /** `POST /Zelefin/notification/test`. Null when sent, otherwise the plugin's reason. */
    suspend fun sendTest(): String? {
        val response = PluginHttp.sendOrNull(baseUrl, accessToken, "POST", "/Zelefin/notification/test")
            ?: return "Could not reach the server."
        if (!response.isSuccess) return "The server could not send a test alert (${response.status})."
        val obj = PluginJson.obj(response.body) ?: return null
        if (PluginJson.bool(obj, "ok") == true) return null
        return PluginJson.string(obj, "error") ?: "The server could not send a test alert."
    }

    companion object {
        fun parseConfig(body: String): CompanionConfig? {
            val obj = PluginJson.obj(body) ?: return null
            val raw = obj["notificationsReady"] as? JsonPrimitive ?: return null
            val ready = raw.takeUnless { it.isString }?.booleanOrNull ?: return null
            return CompanionConfig(notificationsReady = ready)
        }
    }
}
