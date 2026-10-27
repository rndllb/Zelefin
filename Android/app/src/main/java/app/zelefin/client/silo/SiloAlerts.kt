package app.zelefin.client.silo

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** What a Silo webhook can alert about. Silo only notifies about shows a profile follows and its requests. */
data class SiloAlertCategory(val id: String, val title: String, val flags: List<String>) {
    companion object {
        val all = listOf(
            SiloAlertCategory("favorites", "New Episodes of Favorites", listOf("notify_favorites")),
            SiloAlertCategory("watchlist", "New Episodes on Your Watchlist", listOf("notify_watchlist")),
            SiloAlertCategory("watching", "New Episodes of Shows You're Watching", listOf("notify_continue_watching", "notify_next_up")),
            SiloAlertCategory("requests", "Request Updates", listOf("notify_requests")),
        )
        val defaultIds = all.map { it.id }.toSet()

        /** Every Silo flag, on or off, for the chosen categories. */
        fun flags(ids: Set<String>): Map<String, Boolean> =
            all.flatMap { category -> category.flags.map { it to (category.id in ids) } }.toMap()
    }
}

/** This phone's Silo alerts for one account: the push service's hook and the webhook on the profile. */
@Serializable
data class SiloAlertRegistration(
    val hookId: String,
    val token: String,
    val webhookId: String? = null,
    val categoryIds: List<String> = emptyList(),
) {
    companion object {
        private const val PREFS = "zelefin.silo.alerts"
        private val json = Json { ignoreUnknownKeys = true }

        /** Accounts with a registration saved on this phone, including ones since signed out. */
        fun savedAccountIds(context: Context): Set<String> =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).all.keys

        fun saved(context: Context, accountId: String): SiloAlertRegistration? =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(accountId, null)
                ?.let { runCatching { json.decodeFromString<SiloAlertRegistration>(it) }.getOrNull() }

        fun save(context: Context, accountId: String, registration: SiloAlertRegistration?) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().apply {
                if (registration == null) remove(accountId) else putString(accountId, json.encodeToString(registration))
            }.apply()
        }
    }
}
