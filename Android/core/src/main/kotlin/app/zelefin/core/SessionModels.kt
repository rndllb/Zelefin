package app.zelefin.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** Which API an account talks to. Silo's Jellyfin-compatible API counts as [Jellyfin]. */
@Serializable
enum class ServerKind { Jellyfin, Emby }

@Serializable
data class SavedSession(
    val serverUrl: String,
    val accessToken: String,
    val userId: String,
    val userName: String,
    val deviceId: String,
    val userImageTag: String? = null,
    val serverVersion: String? = null,
    val serverName: String? = null,
    /** Silo's Jellyfin-compatible API; see [SiloCompat] for what it leaves out. */
    val isSiloServer: Boolean = false,
    /** Present when signed in through Silo's own sign-in and household profiles. */
    val siloLink: SiloLink? = null,
    val serverKind: ServerKind = ServerKind.Jellyfin,
) {
    val isEmbyServer: Boolean get() = serverKind == ServerKind.Emby

    /** A Jellyfin server proper: SyncPlay, server plugins, backups, and branding. */
    val hasJellyfinExtras: Boolean get() = serverKind == ServerKind.Jellyfin && !isSiloServer

    /** Admin tools, item editing, playlists, collections, likes, and remote control: Jellyfin and Emby, not Silo. */
    val hasServerTools: Boolean get() = !isSiloServer

    val serverTypeName: String
        get() = when {
            isEmbyServer -> "Emby"
            isSiloServer -> "Silo"
            else -> "Jellyfin"
        }

    val accountId: String
        get() {
            val host = serverUrl.substringAfter("://").substringBefore("/").substringBefore(":").lowercase()
            return "$host|$userId"
        }

    val displayServer: String
        get() {
            val name = serverName?.trim().orEmpty()
            if (name.isNotEmpty()) return name
            return serverUrl.substringAfter("://").substringBefore("/")
        }

    companion object {
        /** Silo's Jellyfin-compatible API names a profile's user `username#profile`; only the profile is shown. Matches iOS. */
        fun displayName(raw: String, isSiloServer: Boolean): String {
            if (!isSiloServer || '#' !in raw) return raw
            return raw.substringAfterLast('#').trim().ifEmpty { raw }
        }
    }
}

@Serializable
data class SavedAccountBox(
    val accounts: List<SavedSession> = emptyList(),
    val currentId: String = "",
) {
    val current: SavedSession?
        get() = accounts.firstOrNull { it.accountId == currentId } ?: accounts.firstOrNull()

    fun upsert(session: SavedSession, select: Boolean = true): SavedAccountBox {
        val next = accounts.toMutableList()
        val index = next.indexOfFirst { it.accountId == session.accountId }
        if (index >= 0) next[index] = session else next += session
        return copy(accounts = next, currentId = if (select) session.accountId else currentId)
    }

    /** Puts [session] where [accountId] was (a profile switch) and selects it, dropping any older copy of it. */
    fun replacing(accountId: String, session: SavedSession): SavedAccountBox {
        val next = accounts.filterNot { it.accountId == session.accountId && it.accountId != accountId }.toMutableList()
        val index = next.indexOfFirst { it.accountId == accountId }
        if (index >= 0) next[index] = session else next += session
        return SavedAccountBox(accounts = next, currentId = session.accountId)
    }
}

@Serializable
data class GatewaySecrets(
    val clientId: String = "",
    val clientSecret: String = "",
) {
    val isConfigured: Boolean get() = clientId.isNotBlank() && clientSecret.isNotBlank()
}

/**
 * Saved accounts as read from disk. [droppedSilo] counts sign-ins made through the removed
 * Silo-native backend; their tokens only worked on Silo's own API, so they are discarded.
 */
data class LoadedAccounts(
    val box: SavedAccountBox?,
    val droppedSilo: Int = 0,
    val droppedCurrent: Boolean = false,
)

object SavedAccountsCodec {
    const val SiloSignInAgainMessage = "Silo now signs in through its Jellyfin-compatible API. Sign in again."

    private val json = Json {
        ignoreUnknownKeys = true
        coerceInputValues = true
    }

    fun decode(raw: String): LoadedAccounts {
        val root = runCatching { json.parseToJsonElement(raw) as? JsonObject }.getOrNull() ?: return LoadedAccounts(null)
        val currentId = (root["currentId"] as? JsonPrimitive)?.contentOrNull.orEmpty()
        var dropped = 0
        var droppedCurrent = false
        val accounts = (root["accounts"] as? JsonArray).orEmpty().mapNotNull { element ->
            val entry = element as? JsonObject ?: return@mapNotNull null
            val session = runCatching { json.decodeFromJsonElement(SavedSession.serializer(), entry) }.getOrNull()
            if (isLegacySilo(entry)) {
                dropped += 1
                if (session != null && session.accountId == currentId) droppedCurrent = true
                return@mapNotNull null
            }
            session?.let { it.copy(userName = SavedSession.displayName(it.userName, it.isSiloServer)) }
        }
        return LoadedAccounts(SavedAccountBox(accounts, currentId), dropped, droppedCurrent)
    }

    fun encode(box: SavedAccountBox): String = json.encodeToString(SavedAccountBox.serializer(), box)

    private fun isLegacySilo(entry: JsonObject): Boolean =
        (entry["backend"] as? JsonPrimitive)?.contentOrNull?.trim().equals("Silo", ignoreCase = true)
}

/**
 * Silo answers as "Jellyfin Server"; its fixed branding disclaimer is the only anonymous tell.
 * Its Jellyfin API leaves out server administration, item editing, SyncPlay, playlists,
 * remote control, Live TV, user-data ratings, collection editing, and server plugins.
 */
object SiloCompat {
    fun isSiloDisclaimer(loginDisclaimer: String?): Boolean =
        loginDisclaimer?.contains("silo", ignoreCase = true) == true
}

data class QuickConnectHandshake(val code: String, val secret: String) {
    val groupedCode: String
        get() {
            val trimmed = code.trim()
            if (trimmed.length != 6) return trimmed
            return "${trimmed.take(3)}  ${trimmed.drop(3)}"
        }
}
