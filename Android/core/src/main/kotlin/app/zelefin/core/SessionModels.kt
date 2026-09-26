package app.zelefin.core

import kotlinx.serialization.Serializable

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
    val backend: MediaBackend = MediaBackend.Jellyfin,
    val refreshToken: String? = null,
    val profileId: String? = null,
    val profileToken: String? = null,
    val profileName: String? = null,
    val userRole: String? = null,
    val isPrimaryProfile: Boolean = false,
) {
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

    val usesSilo: Boolean get() = backend == MediaBackend.Silo
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
}

@Serializable
data class GatewaySecrets(
    val clientId: String = "",
    val clientSecret: String = "",
) {
    val isConfigured: Boolean get() = clientId.isNotBlank() && clientSecret.isNotBlank()
}

data class QuickConnectHandshake(val code: String, val secret: String) {
    val groupedCode: String
        get() {
            val trimmed = code.trim()
            if (trimmed.length != 6) return trimmed
            return "${trimmed.take(3)}  ${trimmed.drop(3)}"
        }
}

@Serializable
data class HouseholdProfile(
    val id: String,
    val name: String,
    val avatarUrl: String? = null,
    val hasPin: Boolean = false,
    val isChild: Boolean = false,
    val isPrimary: Boolean = false,
)

data class SiloPendingSignIn(
    val serverUrl: String,
    val accessToken: String,
    val refreshToken: String?,
    val userId: String,
    val userName: String,
    val deviceId: String,
    val serverName: String?,
    val serverVersion: String?,
    val userRole: String?,
    val profiles: List<HouseholdProfile>,
) {
    val needsProfileChoice: Boolean get() = profiles.size != 1 || profiles.any { it.hasPin }

    val singleUnlockedProfile: HouseholdProfile?
        get() = profiles.singleOrNull()?.takeIf { !it.hasPin }
}
