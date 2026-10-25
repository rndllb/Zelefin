package app.zelefin.client.push

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.ZelefinException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Zelefin's push service hands each phone a private webhook address for Emby or Silo to post to. */
object PushHookRelay {
    enum class Service(val path: String) { Emby("emby"), Silo("silo") }

    data class Hook(val hookId: String, val url: String)

    private const val BASE = "https://push.zelefin.app"
    private val jsonType = "application/json".toMediaType()

    suspend fun register(service: Service, token: String, label: String? = null): Hook {
        val body = send("POST", "/${service.path}/v1/hooks", registration(token, label = label))
            ?: throw ZelefinException.server("Zelefin's push service could not save this phone. Try again in a moment.")
        val reply = runCatching { Json.parseToJsonElement(body) as? JsonObject }.getOrNull()
        val hookId = (reply?.get("hookId") as? JsonPrimitive)?.contentOrNull
        val url = (reply?.get("url") as? JsonPrimitive)?.contentOrNull
        if (hookId.isNullOrBlank() || url.isNullOrBlank()) {
            throw ZelefinException.server("Zelefin's push service did not answer. Try again in a moment.")
        }
        return Hook(hookId, url)
    }

    /** False when the push service no longer knows the hook, so the caller registers again. */
    suspend fun update(service: Service, hookId: String, token: String, signingSecret: String? = null): Boolean =
        send("PUT", "/${service.path}/v1/hooks/$hookId", registration(token, signingSecret = signingSecret)) != null

    suspend fun remove(service: Service, hookId: String) {
        send("DELETE", "/${service.path}/v1/hooks/$hookId", null)
    }

    private fun registration(token: String, label: String? = null, signingSecret: String? = null): String {
        val fields = mutableMapOf("platform" to JsonPrimitive("android"), "token" to JsonPrimitive(token))
        label?.let { fields["label"] = JsonPrimitive(it) }
        signingSecret?.let { fields["signingSecret"] = JsonPrimitive(it) }
        return JsonObject(fields).toString()
    }

    private suspend fun send(method: String, path: String, json: String?): String? = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("$BASE$path")
            .method(method, json?.toRequestBody(jsonType))
            .build()
        runCatching {
            GatewayHttp.client.newCall(request).execute().use { response ->
                if (response.isSuccessful) response.body?.string().orEmpty() else null
            }
        }.getOrNull()
    }
}
