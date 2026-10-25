package app.zelefin.client.emby

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.EmbyJson
import app.zelefin.core.TickClock
import java.net.URI
import java.net.URLEncoder
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.longOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener

/** What Emby's session socket asks of this device. */
sealed interface EmbySocketEvent {
    /** The server drops the socket unless a KeepAlive arrives within [seconds]. */
    data class KeepAlive(val seconds: Int) : EmbySocketEvent

    data class Play(val itemIds: List<String>, val startIndex: Int, val startSeconds: Double, val command: String) : EmbySocketEvent {
        val itemId: String? get() = itemIds.getOrNull(startIndex) ?: itemIds.firstOrNull()
    }

    data class Playstate(val command: String, val seekSeconds: Double?) : EmbySocketEvent

    data class Message(val header: String, val text: String, val timeoutMs: Int?) : EmbySocketEvent

    data class Command(val name: String, val arguments: Map<String, String>) : EmbySocketEvent

    data class UserDataChanged(val itemIds: List<String>) : EmbySocketEvent
}

object EmbySocketMessages {
    const val KeepAlive = """{"MessageType":"KeepAlive"}"""

    fun url(baseUrl: String, token: String, deviceId: String): String? {
        val parsed = runCatching { URI(baseUrl) }.getOrNull() ?: return null
        val scheme = when (parsed.scheme?.lowercase()) {
            "https" -> "wss"
            "http" -> "ws"
            else -> return null
        }
        val host = parsed.host ?: return null
        val port = if (parsed.port != -1) ":${parsed.port}" else ""
        val path = parsed.rawPath.orEmpty().trimEnd('/') + "/embywebsocket"
        return "$scheme://$host$port$path?api_key=${encode(token)}&deviceId=${encode(deviceId)}"
    }

    fun parse(text: String): EmbySocketEvent? {
        val root = runCatching { EmbyJson.parser.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return null
        val data = root["Data"]
        return when ((root["MessageType"] as? JsonPrimitive)?.contentOrNull) {
            "ForceKeepAlive" -> keepAliveEvent((data as? JsonPrimitive)?.intOrNull)
            "Play" -> (data as? JsonObject)?.let { play ->
                val ids = play.strings("ItemIds")
                if (ids.isEmpty()) return null
                EmbySocketEvent.Play(
                    itemIds = ids,
                    startIndex = play.int("StartIndex") ?: 0,
                    startSeconds = TickClock.seconds(play.long("StartPositionTicks") ?: 0L),
                    command = play.text("PlayCommand") ?: "PlayNow",
                )
            }
            "Playstate" -> (data as? JsonObject)?.let { state ->
                val command = state.text("Command") ?: return null
                EmbySocketEvent.Playstate(command, state.long("SeekPositionTicks")?.let(TickClock::seconds))
            }
            "GeneralCommand" -> (data as? JsonObject)?.let(::command)
            "DisplayMessage" -> (data as? JsonObject)?.let { message(it) }
            "UserDataChanged" -> {
                val changes = ((data as? JsonObject)?.get("UserDataList") as? JsonArray).orEmpty()
                EmbySocketEvent.UserDataChanged(changes.mapNotNull { (it as? JsonObject)?.text("ItemId") })
            }
            else -> null
        }
    }

    private fun keepAliveEvent(seconds: Int?) = EmbySocketEvent.KeepAlive(seconds?.takeIf { it > 0 } ?: 60)

    private fun command(data: JsonObject): EmbySocketEvent? {
        val name = data.text("Name") ?: return null
        val arguments = data["Arguments"] as? JsonObject ?: JsonObject(emptyMap())
        if (name.equals("DisplayMessage", ignoreCase = true)) return message(arguments)
        return EmbySocketEvent.Command(name, arguments.mapNotNull { (key, value) -> (value as? JsonPrimitive)?.contentOrNull?.let { key to it } }.toMap())
    }

    private fun message(arguments: JsonObject): EmbySocketEvent? {
        val header = arguments.text("Header")
        val text = arguments.text("Text")
        if (header == null && text == null) return null
        return EmbySocketEvent.Message(header ?: "Message", text ?: header.orEmpty(), arguments.int("TimeoutMs"))
    }

    private fun JsonObject.text(key: String): String? = (this[key] as? JsonPrimitive)?.contentOrNull?.trim()?.ifEmpty { null }

    private fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.let { it.intOrNull ?: it.contentOrNull?.toIntOrNull() }

    private fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.let { it.longOrNull ?: it.contentOrNull?.toLongOrNull() }

    private fun JsonObject.strings(key: String): List<String> =
        (this[key] as? JsonArray).orEmpty().mapNotNull { (it as? JsonPrimitive)?.contentOrNull?.takeIf { id -> id.isNotBlank() } }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
}

/**
 * Emby's `/embywebsocket`, which delivers remote control and messages to this device. It reconnects
 * with backoff, and reports capabilities each time it opens so other clients can control this phone.
 */
class EmbySocket(private val scope: CoroutineScope) {
    private var job: Job? = null

    fun connect(library: EmbyLibrary, onEvent: (EmbySocketEvent) -> Unit) {
        disconnect()
        val token = library.api.accessToken?.takeIf { it.isNotBlank() } ?: return
        val url = EmbySocketMessages.url(library.serverUrl, token, library.api.deviceId) ?: return
        job = scope.launch {
            var backoffSeconds = 5L
            while (isActive) {
                val closed = CompletableDeferred<Unit>()
                var keepAliveSeconds = 30L
                val socket = client.newWebSocket(
                    Request.Builder().url(url).header("X-Emby-Authorization", library.api.authorization).build(),
                    object : WebSocketListener() {
                        override fun onOpen(webSocket: WebSocket, response: Response) {
                            backoffSeconds = 5L
                            scope.launch { runCatching { library.advertiseSessionCapabilities() } }
                        }

                        override fun onMessage(webSocket: WebSocket, text: String) {
                            when (val event = EmbySocketMessages.parse(text) ?: return) {
                                is EmbySocketEvent.KeepAlive -> keepAliveSeconds = (event.seconds / 2L).coerceAtLeast(5L)
                                else -> scope.launch { onEvent(event) }
                            }
                        }

                        override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                            webSocket.close(1000, null)
                        }

                        override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                            closed.complete(Unit)
                        }

                        override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                            closed.complete(Unit)
                        }
                    },
                )
                val keepAlive = launch {
                    while (isActive) {
                        delay(keepAliveSeconds * 1000)
                        socket.send(EmbySocketMessages.KeepAlive)
                    }
                }
                try {
                    closed.await()
                } finally {
                    keepAlive.cancel()
                    socket.cancel()
                }
                delay(backoffSeconds * 1000)
                backoffSeconds = (backoffSeconds * 2).coerceAtMost(60L)
            }
        }
    }

    fun disconnect() {
        job?.cancel()
        job = null
    }

    private companion object {
        val client: OkHttpClient by lazy {
            GatewayHttp.client.newBuilder()
                .readTimeout(0, TimeUnit.MILLISECONDS)
                .pingInterval(30, TimeUnit.SECONDS)
                .build()
        }
    }
}
