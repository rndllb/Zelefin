package app.zelefin.client.silo

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.SiloAvatarPresets
import app.zelefin.core.SiloConnectInfo
import app.zelefin.core.SiloJson
import app.zelefin.core.SiloPinVerification
import app.zelefin.core.SiloProblem
import app.zelefin.core.SiloProfile
import app.zelefin.core.SiloProfileCollection
import app.zelefin.core.SiloSignIn
import app.zelefin.core.SiloTokens
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * Silo's native v2 API, used only for sign-in, household profiles, the Jellyfin handoff, and
 * profile pictures. [onTokens] gets the previous and new pair after every refresh so they can be saved.
 */
class SiloAccountClient(
    val baseUrl: String,
    tokens: SiloTokens? = null,
    private val onTokens: (previous: SiloTokens?, next: SiloTokens) -> Unit = { _, _ -> },
) {
    @Volatile
    var tokens: SiloTokens? = tokens
        private set

    private val refreshLock = Mutex()

    suspend fun login(username: String, password: String): SiloSignIn {
        val body = buildJsonObject {
            put("username", username)
            put("password", password)
        }.toString()
        val reply = send(request("/api/v2/auth/login").post(body.toRequestBody(JsonType)))
        if (!reply.ok) {
            throw ZelefinException.server(
                SiloProblem.message(reply.body, reply.status, if (reply.status == 401) "Silo did not accept that username or password." else null),
            )
        }
        val signIn = SiloJson.signIn(reply.body, now()) ?: throw ZelefinException.server("Silo sent a sign-in reply Zelefin could not read.")
        tokens = signIn.tokens
        if (signIn.account.passwordChangeRequired) {
            throw ZelefinException.server("Silo needs a new password for this account. Change it in Silo, then sign in again.")
        }
        return signIn
    }

    suspend fun profiles(): SiloProfileCollection {
        val reply = expect(authorized("/api/v2/profiles") { it.get() }, "Silo could not list the profiles.")
        return SiloJson.profiles(reply.body, baseUrl) ?: throw ZelefinException.server("Silo sent a profile list Zelefin could not read.")
    }

    suspend fun verifyPin(profileId: String, pin: String): SiloPinVerification {
        val body = buildJsonObject { put("pin", pin) }.toString()
        val reply = authorized("/api/v2/profiles/${segment(profileId)}/verify-pin") { it.post(body.toRequestBody(JsonType)) }
        if (!reply.ok) {
            throw ZelefinException.server(
                SiloProblem.message(reply.body, reply.status, if (reply.status in 400..499 && reply.status != 429) WrongPin else null),
            )
        }
        return SiloJson.pinVerification(reply.body) ?: throw ZelefinException.server("Silo sent a PIN reply Zelefin could not read.")
    }

    suspend fun connectInfo(): SiloConnectInfo {
        val reply = expect(authorized("/api/v2/compat/connect-info") { it.get() }, "Silo could not share its Jellyfin-compatible address.")
        return SiloJson.connectInfo(reply.body) ?: throw ZelefinException.server("Silo sent connection details Zelefin could not read.")
    }

    /** Approves a Jellyfin Quick Connect [code] as [profileId], so that Jellyfin session belongs to the profile. */
    suspend fun approveHandoff(code: String, profileId: String, profileToken: String?) {
        val body = buildJsonObject { put("code", code) }.toString()
        val reply = expect(
            authorized("/api/v2/auth/device/approve-handoff") { builder ->
                builder.post(body.toRequestBody(JsonType)).profile(profileId, profileToken)
            },
            "Silo could not sign this profile in.",
        )
        if (SiloJson.handoffStatus(reply.body) != "approved") {
            throw ZelefinException.server("Silo did not approve the sign-in for this profile.")
        }
    }

    suspend fun uploadAvatar(profileId: String, profileToken: String?, jpeg: ByteArray): SiloProfile {
        val form = MultipartBody.Builder()
            .setType(MultipartBody.FORM)
            .addFormDataPart("avatar", "avatar.jpg", jpeg.toRequestBody("image/jpeg".toMediaType()))
            .build()
        val reply = authorized("/api/v2/profiles/${segment(profileId)}/avatar") { it.put(form).profile(profileId, profileToken) }
        if (!reply.ok) {
            throw ZelefinException.server(SiloProblem.message(reply.body, reply.status, if (reply.status == 413) "Choose a smaller photo." else null))
        }
        return SiloJson.profile(reply.body, baseUrl) ?: throw ZelefinException.server("Silo sent a profile Zelefin could not read.")
    }

    /** Sets a premade avatar, or clears the preset when [presetId] is null. */
    suspend fun setAvatarPreset(profileId: String, profileToken: String?, presetId: String?): SiloProfile {
        val body = SiloAvatarPresets.patchBody(presetId)
        val reply = expect(
            authorized("/api/v2/profiles/${segment(profileId)}") { it.patch(body.toRequestBody(JsonType)).profile(profileId, profileToken) },
            "Silo could not change the picture.",
        )
        return SiloJson.profile(reply.body, baseUrl) ?: throw ZelefinException.server("Silo sent a profile Zelefin could not read.")
    }

    suspend fun deleteAvatar(profileId: String, profileToken: String?) {
        expect(
            authorized("/api/v2/profiles/${segment(profileId)}/avatar") { it.delete().profile(profileId, profileToken) },
            "Silo could not remove the photo.",
        )
    }

    suspend fun logout() {
        if (tokens == null) return
        authorized("/api/v2/auth/logout") { it.post(ByteArray(0).toRequestBody(null)) }
    }

    /** Sends with the bearer token, refreshing it once on 401 and retrying. */
    private suspend fun authorized(path: String, build: (Request.Builder) -> Request.Builder): Reply {
        val access = currentAccess()
        val first = send(build(request(path)).header("Authorization", "Bearer $access"))
        if (first.status != 401) return first
        val renewed = refresh(stale = access)
        return send(build(request(path)).header("Authorization", "Bearer $renewed"))
    }

    private suspend fun currentAccess(): String {
        val current = tokens ?: throw ZelefinException.siloSignInExpired()
        if (!current.isExpired(now())) return current.accessToken
        return refresh(stale = current.accessToken)
    }

    private suspend fun refresh(stale: String): String = refreshLock.withLock {
        val current = tokens ?: throw ZelefinException.siloSignInExpired()
        if (current.accessToken != stale && !current.isExpired(now())) return@withLock current.accessToken
        if (current.refreshToken.isBlank()) throw ZelefinException.siloSignInExpired()
        val body = buildJsonObject { put("refresh_token", current.refreshToken) }.toString()
        val reply = send(request("/api/v2/auth/refresh").post(body.toRequestBody(JsonType)))
        if (reply.status in 400..499) throw ZelefinException.siloSignInExpired()
        if (!reply.ok) throw ZelefinException.server(SiloProblem.message(reply.body, reply.status))
        val next = SiloJson.refreshed(reply.body, now()) ?: throw ZelefinException.siloSignInExpired()
        tokens = next
        onTokens(current, next)
        next.accessToken
    }

    private fun expect(reply: Reply, fallback: String): Reply {
        if (reply.ok) return reply
        throw ZelefinException.server(SiloProblem.message(reply.body, reply.status, fallback.takeIf { reply.status !in setOf(401, 403, 429) }))
    }

    private fun request(path: String): Request.Builder {
        val url = ServerUrl.join(baseUrl, path) ?: throw ZelefinException.invalidServerUrl()
        return Request.Builder().url(url).header("Accept", AcceptJson)
    }

    private fun Request.Builder.profile(profileId: String, profileToken: String?): Request.Builder = apply {
        header("X-Profile-Id", profileId)
        profileToken?.takeIf { it.isNotBlank() }?.let { header("X-Profile-Token", it) }
    }

    private suspend fun send(builder: Request.Builder): Reply = withContext(Dispatchers.IO) {
        execute(GatewayHttp.client, builder.build())
    }

    private class Reply(val status: Int, val body: String) {
        val ok: Boolean get() = status in 200..299
    }

    companion object {
        private val JsonType = "application/json".toMediaType()
        private const val AcceptJson = "application/json, application/problem+json"
        private const val WrongPin = "That PIN is not right. Try again."

        private val probeClient: OkHttpClient by lazy {
            GatewayHttp.client.newBuilder().callTimeout(10, TimeUnit.SECONDS).build()
        }

        /**
         * True when [baseUrl] is Silo's own (native) address rather than its Jellyfin-compatible one.
         * Unreachable or unknown answers count as not Silo, so Jellyfin sign-in reports the real error.
         */
        suspend fun isSiloAddress(baseUrl: String): Boolean = withContext(Dispatchers.IO) {
            fun probe(path: String): Reply? {
                val url = ServerUrl.join(baseUrl, path) ?: return null
                return runCatching { execute(probeClient, Request.Builder().url(url).header("Accept", AcceptJson).get().build()) }.getOrNull()
            }
            val setup = probe("/api/v2/system/setup") ?: return@withContext false
            if (setup.ok && SiloJson.isSetupStatus(setup.body)) return@withContext true
            val health = probe("/api/v1/health") ?: return@withContext false
            health.ok && SiloJson.isHealth(health.body)
        }

        private fun execute(client: OkHttpClient, request: Request): Reply =
            client.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                val headers = response.headers.names().associateWith { response.header(it).orEmpty() }
                if (AccessGateway.isChallenge(response.code, headers, text)) throw ZelefinException.accessGateway()
                Reply(response.code, text)
            }

        private fun segment(id: String): String = URLEncoder.encode(id, "UTF-8").replace("+", "%20")

        private fun now(): Long = System.currentTimeMillis()
    }
}
