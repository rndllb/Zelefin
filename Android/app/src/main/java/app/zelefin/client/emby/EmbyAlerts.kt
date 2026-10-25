package app.zelefin.client.emby

import android.content.Context
import app.zelefin.core.EmbyJson
import app.zelefin.core.ZelefinException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive

/** A group of Emby notification events that Settings → Notifications turns on or off together. */
data class EmbyAlertCategory(val id: String, val title: String, val events: List<String>) {
    companion object {
        val all = listOf(
            EmbyAlertCategory("library", "New Media", listOf("library.new")),
            EmbyAlertCategory("playback", "Playback", listOf("playback.start", "playback.stop")),
            EmbyAlertCategory("livetv", "Live TV Recordings", listOf("livetv.recordingstarted", "livetv.recordingended", "livetv.recordingerror")),
            EmbyAlertCategory("users", "Sign-ins", listOf("user.authenticated", "user.authenticationfailed", "user.lockedout")),
            EmbyAlertCategory("tasks", "Scheduled Tasks", listOf("scheduledtasks.completed", "scheduledtasks.failed")),
            EmbyAlertCategory(
                "server",
                "Server Updates and Backups",
                listOf("system.updateavailable", "system.updated", "system.serverrestartrequired", "system.backupcompleted", "system.backupfailed"),
            ),
        )
        val defaultIds = setOf("library", "livetv")
    }
}

/** This phone's Emby alerts for one account: the push service's hook and the matching Emby notification. */
@Serializable
data class EmbyAlertRegistration(
    val hookId: String,
    val url: String,
    val token: String,
    val entryId: String? = null,
    val categoryIds: List<String> = emptyList(),
) {
    val events: List<String>
        get() = EmbyAlertCategory.all.filter { it.id in categoryIds }.flatMap { it.events }

    companion object {
        private const val PREFS = "zelefin.emby.alerts"
        private val json = Json { ignoreUnknownKeys = true }

        fun saved(context: Context, accountId: String): EmbyAlertRegistration? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(accountId, null)
                ?.let { runCatching { json.decodeFromString<EmbyAlertRegistration>(it) }.getOrNull() }

        fun save(context: Context, accountId: String, registration: EmbyAlertRegistration?) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (registration == null) remove(accountId) else putString(accountId, json.encodeToString(registration))
            }.apply()
        }
    }
}

/** Emby only lets administrators add notifications for this user; an admin adds [url] by hand. */
class EmbyAlertsNotAllowed(val url: String) : Exception(
    "This Emby server only lets administrators add notifications. Ask an admin to add this phone's address in Emby under Settings → Notifications → Webhooks.",
)

private const val WebhookNotifier = "webhooknotifications"

/** Whether this server can send webhooks (Emby's Webhooks notifier, part of Emby Premiere). */
suspend fun EmbyLibrary.offersWebhooks(): Boolean = runCatching {
    val reply = api.send("GET", "/Notifications/Services", listOf("UserId" to user))
    reply.ok && (EmbyJson.parser.parseToJsonElement(reply.body) as? JsonArray).orEmpty()
        .any { (it as? JsonObject)?.text("Id") == WebhookNotifier }
}.getOrDefault(false)

/** Event ids this user may subscribe to. Emby leaves out what the account is not allowed to see. */
suspend fun EmbyLibrary.availableAlertEvents(): Set<String> = runCatching {
    val reply = api.send("GET", "/Notifications/Types", listOf("UserId" to user))
    if (!reply.ok) return@runCatching emptySet()
    (EmbyJson.parser.parseToJsonElement(reply.body) as? JsonArray).orEmpty().flatMap { category ->
        ((category as? JsonObject)?.get("Events") as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.text("Id") }
    }.toSet()
}.getOrDefault(emptySet())

/** Adds or updates this user's webhook notification and returns its Emby id. */
suspend fun EmbyLibrary.saveAlertWebhook(entryId: String?, url: String, events: List<String>, name: String): String {
    val base = webhookEntry(entryId)
    val existingId = base.text("Id")
    val entry = JsonObject(
        base + mapOf(
            "UserId" to JsonPrimitive(user),
            "FriendlyName" to JsonPrimitive(name),
            "Enabled" to JsonPrimitive(true),
            "EventIds" to JsonArray(events.map(::JsonPrimitive)),
            "Options" to webhookOptions(url),
        ),
    )
    val reply = api.send("POST", "/Notifications/Services/Configured", json = entry.toString())
    if (reply.status == 401 || reply.status == 403) throw EmbyAlertsNotAllowed(url)
    if (!reply.ok) throw ZelefinException.server("Emby could not save the notification (HTTP ${reply.status}).")
    if (existingId != null) return existingId
    return configuredWebhooks().firstOrNull { (it["Options"] as? JsonObject)?.text("Url") == url }?.text("Id")
        ?: throw ZelefinException.server("Emby saved the notification but did not list it. Try again.")
}

suspend fun EmbyLibrary.deleteAlertWebhook(entryId: String) {
    runCatching { api.send("DELETE", "/Notifications/Services/Configured", listOf("Id" to entryId, "UserId" to user)) }
}

/** Emby sends its test event through the webhook, and the push service turns it into an alert. */
suspend fun EmbyLibrary.testAlertWebhook(url: String, events: List<String>) {
    val entry = JsonObject(
        webhookEntry(null) + mapOf(
            "UserId" to JsonPrimitive(user),
            "EventIds" to JsonArray(events.map(::JsonPrimitive)),
            "Options" to webhookOptions(url),
        ),
    )
    val reply = api.send("POST", "/Notifications/Services/Test", json = entry.toString())
    if (!reply.ok) throw ZelefinException.server("Emby could not send the test (HTTP ${reply.status}).")
}

private fun webhookOptions(url: String) =
    JsonObject(mapOf("Url" to JsonPrimitive(url), "EnableMultipartFormData" to JsonPrimitive("false")))

/** The saved entry when Emby still has it, else a new one from Emby's defaults (without an `Id`). */
private suspend fun EmbyLibrary.webhookEntry(entryId: String?): JsonObject {
    if (entryId != null) configuredWebhooks().firstOrNull { it.text("Id") == entryId }?.let { return it }
    val reply = api.send("GET", "/Notifications/Services/Defaults", listOf("UserId" to user, "NotifierKey" to WebhookNotifier))
    if (!reply.ok) throw ZelefinException.server("Emby did not offer a webhook notification (HTTP ${reply.status}).")
    return EmbyJson.parser.parseToJsonElement(reply.body) as? JsonObject ?: JsonObject(emptyMap())
}

private suspend fun EmbyLibrary.configuredWebhooks(): List<JsonObject> {
    val reply = api.send("GET", "/Notifications/Services/Configured", listOf("UserId" to user))
    if (!reply.ok) return emptyList()
    return (EmbyJson.parser.parseToJsonElement(reply.body) as? JsonArray).orEmpty().mapNotNull { it as? JsonObject }
}

private fun JsonObject.text(key: String): String? =
    (this[key] as? JsonElement)?.let { runCatching { it.jsonPrimitive.contentOrNull }.getOrNull() }?.takeIf { it.isNotBlank() }
