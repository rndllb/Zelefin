package app.zelefin.client.emby

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.EmbyJson
import app.zelefin.core.EmbyPublicInfo
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.KSerializer
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/** Query values; lists are joined with [separator], nulls and empty lists are left out. */
internal class EmbyQuery(private val separator: String = ",") {
    private val items = mutableListOf<Pair<String, String>>()

    operator fun set(name: String, value: Any?) {
        val text = when (value) {
            null -> return
            is Collection<*> -> value.filterNotNull().joinToString(separator).ifEmpty { return }
            else -> value.toString()
        }
        items += name to text
    }

    fun pipe(name: String, values: Collection<String>) {
        if (values.isNotEmpty()) items += name to values.joinToString("|")
    }

    fun entries(): List<Pair<String, String>> = items.toList()
}

internal fun embyQuery(build: EmbyQuery.() -> Unit): List<Pair<String, String>> = EmbyQuery().apply(build).entries()

/**
 * Emby's REST API over OkHttp. API calls carry `X-Emby-Token`; media URLs carry `api_key`
 * because the players and image loader cannot add headers to every request.
 */
class EmbyApi(
    val baseUrl: String,
    @Volatile var accessToken: String?,
    val deviceId: String,
    private val deviceName: String,
    private val version: String,
) {
    val authorization: String
        get() = "MediaBrowser Client=\"Zelefin\", Device=\"${quoted(deviceName)}\", DeviceId=\"${quoted(deviceId)}\", Version=\"${quoted(version)}\""

    class Reply(val status: Int, val body: String) {
        val ok: Boolean get() = status in 200..299
    }

    suspend fun <T> get(path: String, serializer: KSerializer<T>, query: List<Pair<String, String>> = emptyList()): T =
        decode(expect(send("GET", path, query)), serializer)

    suspend fun <T> post(path: String, serializer: KSerializer<T>, query: List<Pair<String, String>> = emptyList(), json: String? = null): T =
        decode(expect(send("POST", path, query, json)), serializer)

    suspend fun execute(request: EmbyRequest): Reply = send(request.method, request.path, request.query, request.json)

    suspend fun send(
        method: String,
        path: String,
        query: List<Pair<String, String>> = emptyList(),
        json: String? = null,
        client: OkHttpClient = GatewayHttp.client,
    ): Reply = withContext(Dispatchers.IO) {
        val request = request(path, query)
            .method(method, json?.toRequestBody(JsonType) ?: if (method == "GET" || method == "DELETE") null else ByteArray(0).toRequestBody(null))
            .build()
        client.newCall(request).execute().use { response ->
            val text = response.body?.string().orEmpty()
            val headers = response.headers.names().associateWith { response.header(it).orEmpty() }
            if (AccessGateway.isChallenge(response.code, headers, text)) throw ZelefinException.accessGateway()
            Reply(response.code, text)
        }
    }

    fun request(path: String, query: List<Pair<String, String>> = emptyList()): Request.Builder {
        val builder = Request.Builder()
            .url(url(path, query, token = false))
            .header("Accept", "application/json")
            .header("X-Emby-Authorization", authorization)
        accessToken?.takeIf { it.isNotBlank() }?.let { builder.header("X-Emby-Token", it) }
        return builder
    }

    /** An absolute URL; [token] adds `api_key` for media the player or image loader fetches. */
    fun url(path: String, query: List<Pair<String, String>> = emptyList(), token: Boolean = true): String =
        httpUrl(path, query, token).toString()

    private fun httpUrl(path: String, query: List<Pair<String, String>>, token: Boolean): HttpUrl {
        val joined = ServerUrl.join(baseUrl, path)?.toHttpUrlOrNull() ?: throw ZelefinException.invalidServerUrl()
        return joined.newBuilder().apply {
            query.forEach { (name, value) -> addQueryParameter(name, value) }
            if (token) accessToken?.takeIf { it.isNotBlank() }?.let { addQueryParameter("api_key", it) }
        }.build()
    }

    private fun expect(reply: Reply): Reply {
        if (reply.ok) return reply
        throw ZelefinException.server(
            when (reply.status) {
                401 -> "Emby did not accept this sign-in. Sign in again."
                403 -> "Emby does not allow this account to do that."
                404 -> "Emby could not find that."
                in 500..599 -> "Emby had a problem (${reply.status}). Try again."
                else -> "Emby answered HTTP ${reply.status}."
            },
        )
    }

    private fun <T> decode(reply: Reply, serializer: KSerializer<T>): T =
        runCatching { EmbyJson.parser.decodeFromString(serializer, reply.body) }
            .getOrElse { throw ZelefinException.server("Emby sent a reply Zelefin could not read.") }

    /** OkHttp refuses header values outside printable ASCII, and device names often carry curly quotes or emoji. */
    private fun quoted(value: String): String =
        value.replace('’', '\'').filter { it in ' '..'~' && it != '"' }.trim().ifEmpty { "Android" }

    companion object {
        private val JsonType = "application/json".toMediaType()

        private val probeClient: OkHttpClient by lazy {
            GatewayHttp.client.newBuilder().callTimeout(10, TimeUnit.SECONDS).build()
        }

        /** `/System/Info/Public`, or null when the address does not answer with it. */
        suspend fun publicInfo(baseUrl: String): EmbyPublicInfo? = withContext(Dispatchers.IO) {
            val url = ServerUrl.join(baseUrl, "/System/Info/Public") ?: return@withContext null
            val request = Request.Builder().url(url).header("Accept", "application/json").get().build()
            val body = runCatching {
                probeClient.newCall(request).execute().use { response ->
                    if (!response.isSuccessful) null else response.body?.string()
                }
            }.getOrNull() ?: return@withContext null
            runCatching { EmbyJson.parser.decodeFromString(EmbyPublicInfo.serializer(), body) }.getOrNull()
        }
    }
}
