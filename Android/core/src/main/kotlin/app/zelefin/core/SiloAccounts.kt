package app.zelefin.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The Silo-native sign-in behind a Jellyfin-compatible session. Silo's own API is used only for
 * the account, its household profiles, and the profile picture; everything else stays on Jellyfin.
 */
@Serializable
data class SiloLink(
    val nativeUrl: String,
    val refreshToken: String,
    val accessToken: String? = null,
    /** Epoch milliseconds. */
    val accessExpiresAt: Long? = null,
    val accountId: String,
    val accountName: String,
    val role: String? = null,
    val profileId: String,
    val profileName: String,
    val isPrimaryProfile: Boolean = false,
    val profileHasPin: Boolean = false,
    val profileToken: String? = null,
    val profileAvatarUrl: String? = null,
    /** Silo's avatar reference, e.g. `preset:dicebear:identicon:pepper-pebble`. */
    val profileAvatar: String? = null,
    /** `none`, `preset`, or `upload`. */
    val profileAvatarSource: String? = null,
) {
    val tokens: SiloTokens get() = SiloTokens(accessToken.orEmpty(), refreshToken, accessExpiresAt)

    val account: SiloAccount get() = SiloAccount(id = accountId, username = accountName, role = role)

    fun withTokens(tokens: SiloTokens): SiloLink =
        copy(accessToken = tokens.accessToken, refreshToken = tokens.refreshToken, accessExpiresAt = tokens.expiresAt)

    fun withProfile(profile: SiloProfile): SiloLink = copy(
        profileName = profile.name,
        isPrimaryProfile = profile.isPrimary,
        profileHasPin = profile.hasPin,
        profileAvatarUrl = profile.avatarUrl,
        profileAvatar = profile.avatar,
        profileAvatarSource = profile.avatarSource,
    )

    /** The current profile as far as the saved link knows it. */
    val profile: SiloProfile
        get() = SiloProfile(
            id = profileId,
            name = profileName,
            avatarUrl = profileAvatarUrl?.let(SiloAvatarUrl::displayable),
            avatar = profileAvatar,
            avatarSource = profileAvatarSource,
            hasPin = profileHasPin,
            isPrimary = isPrimaryProfile,
        )
}

data class SiloTokens(
    val accessToken: String,
    val refreshToken: String,
    /** Epoch milliseconds; null when Silo did not say. */
    val expiresAt: Long? = null,
) {
    /** Refreshes a little early so a request never leaves with a token about to lapse. */
    fun isExpired(nowMillis: Long): Boolean =
        accessToken.isBlank() || (expiresAt != null && nowMillis >= expiresAt - 30_000)
}

data class SiloAccount(
    val id: String,
    val username: String,
    val email: String? = null,
    val role: String? = null,
    val permissions: List<String> = emptyList(),
    val downloadAllowed: Boolean = false,
    val passwordChangeRequired: Boolean = false,
)

data class SiloSignIn(val tokens: SiloTokens, val account: SiloAccount)

data class SiloProfile(
    val id: String,
    val name: String,
    /** Absolute, resolved against Silo's address, and never SVG. */
    val avatarUrl: String? = null,
    val avatar: String? = null,
    val avatarSource: String? = null,
    val hasPin: Boolean = false,
    val isChild: Boolean = false,
    val isPrimary: Boolean = false,
)

data class SiloProfileCollection(
    val items: List<SiloProfile>,
    val avatarUploadEnabled: Boolean,
)

data class SiloPinVerification(
    val valid: Boolean,
    val profileToken: String? = null,
    val expiresAt: String? = null,
)

data class SiloConnectInfo(
    val jellyfinEnabled: Boolean,
    val pendingRestart: Boolean,
    val publicUrl: String?,
    val serverName: String?,
    val passwordLoginAvailable: Boolean,
) {
    /** Why Zelefin cannot reach Silo's Jellyfin-compatible API yet; null when it can. */
    val blocker: String?
        get() = when {
            !jellyfinEnabled -> TurnOnJellyfinMessage
            pendingRestart -> RestartMessage
            jellyfinUrl == null -> PublicAddressMessage
            else -> null
        }

    val jellyfinUrl: String?
        get() = publicUrl?.trim()?.takeIf { it.isNotEmpty() }?.let { runCatching { ServerUrl.normalize(it) }.getOrNull() }

    fun requireJellyfinUrl(): String {
        blocker?.let { throw ZelefinException.server(it) }
        return jellyfinUrl ?: throw ZelefinException.server(PublicAddressMessage)
    }

    companion object {
        const val TurnOnJellyfinMessage = "Turn on Silo's Jellyfin-compatible API in its admin settings, then sign in again."
        const val RestartMessage = "Restart Silo to finish turning on its Jellyfin-compatible API, then sign in again."
        const val PublicAddressMessage = "Set the public address in Silo's Jellyfin compatibility settings, then sign in again."
    }
}

/** Silo's v2 JSON is snake_case and ids are opaque strings. */
object SiloJson {
    fun isSetupStatus(text: String): Boolean {
        val root = LenientJson.objectOrNull(text) ?: return false
        return root.containsKey("needs_setup") || root.containsKey("wizard_completed")
    }

    fun needsSetup(text: String): Boolean = LenientJson.objectOrNull(text)?.bool("needs_setup") == true

    fun isHealth(text: String): Boolean = LenientJson.objectOrNull(text)?.containsKey("status") == true

    fun signIn(text: String, nowMillis: Long): SiloSignIn? {
        val root = LenientJson.objectOrNull(text) ?: return null
        val tokens = tokens(root, nowMillis) ?: return null
        val user = root.obj("user") ?: return null
        val account = account(user) ?: return null
        return SiloSignIn(tokens, account)
    }

    fun refreshed(text: String, nowMillis: Long): SiloTokens? =
        LenientJson.objectOrNull(text)?.let { tokens(it, nowMillis) }

    fun profiles(text: String, baseUrl: String): SiloProfileCollection? {
        val root = LenientJson.objectOrNull(text) ?: return null
        val items = root.objects("items").mapNotNull { profile(it, baseUrl) }
        return SiloProfileCollection(items, avatarUploadEnabled = root.bool("avatar_upload_enabled") ?: false)
    }

    fun profile(text: String, baseUrl: String): SiloProfile? =
        LenientJson.objectOrNull(text)?.let { profile(it, baseUrl) }

    fun profile(json: JsonObject, baseUrl: String): SiloProfile? {
        val id = json.str("id") ?: return null
        return SiloProfile(
            id = id,
            name = json.str("name") ?: "Profile",
            avatarUrl = json.str("avatar_url")?.let { avatarUrl(baseUrl, it) },
            avatar = json.str("avatar"),
            avatarSource = json.str("avatar_source")?.lowercase(),
            hasPin = json.bool("has_pin") == true,
            isChild = json.bool("is_child") == true,
            isPrimary = json.bool("is_primary") == true,
        )
    }

    fun pinVerification(text: String): SiloPinVerification? {
        val root = LenientJson.objectOrNull(text) ?: return null
        val valid = root.bool("valid") ?: return null
        return SiloPinVerification(valid, root.str("profile_token"), root.str("expires_at"))
    }

    fun connectInfo(text: String): SiloConnectInfo? {
        val root = LenientJson.objectOrNull(text) ?: return null
        val jellyfin = root.obj("jellyfin") ?: return null
        return SiloConnectInfo(
            jellyfinEnabled = jellyfin.bool("enabled") == true,
            pendingRestart = jellyfin.bool("pending_restart") == true,
            publicUrl = jellyfin.str("public_url"),
            serverName = jellyfin.str("server_name"),
            passwordLoginAvailable = root.obj("account")?.bool("password_login_available") == true,
        )
    }

    fun handoffStatus(text: String): String? = LenientJson.objectOrNull(text)?.str("status")?.lowercase()

    fun avatarUrl(baseUrl: String, raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty() || trimmed.startsWith("//")) return null
        return ServerUrl.resolve(baseUrl, trimmed)?.let(SiloAvatarUrl::displayable)
    }

    private fun tokens(json: JsonObject, nowMillis: Long): SiloTokens? {
        val access = json.str("access_token") ?: return null
        val refresh = json.str("refresh_token") ?: return null
        val expiresIn = json.dbl("expires_in")?.takeIf { it > 0 }
        return SiloTokens(access, refresh, expiresIn?.let { nowMillis + (it * 1000).toLong() })
    }

    private fun account(json: JsonObject): SiloAccount? {
        val id = json.str("id") ?: return null
        val username = json.str("username") ?: return null
        return SiloAccount(
            id = id,
            username = username,
            email = json.str("email"),
            role = json.str("role")?.lowercase(),
            permissions = json.arr("permissions").orEmpty().mapNotNull { (it as? JsonPrimitive)?.content?.trim()?.ifEmpty { null } },
            downloadAllowed = json.bool("download_allowed") == true,
            passwordChangeRequired = json.bool("password_change_required") == true,
        )
    }
}

/** RFC 7807 problem details from Silo, turned into one readable sentence. */
object SiloProblem {
    fun detail(body: String?): String? {
        val root = body?.let(LenientJson::objectOrNull) ?: return null
        root.str("detail")?.let { return it }
        root.objects("errors").firstNotNullOfOrNull { it.str("detail") }?.let { return it }
        return root.str("title")
    }

    fun message(body: String?, status: Int, fallback: String? = null): String =
        detail(body) ?: fallback ?: when (status) {
            401 -> "Silo did not accept this sign-in."
            403 -> "Silo does not allow this account to do that."
            404 -> "Silo could not find that."
            429 -> "Too many tries. Wait a moment, then try again."
            in 500..599 -> "Silo had a problem ($status). Try again."
            else -> "Silo answered $status."
        }
}

/**
 * Silo hands Zelefin its Jellyfin-compatible address as configured. Signing in at an outside address
 * while that one points at the home network works at home and nowhere else, so the picker says so.
 */
object SiloAddressCheck {
    fun remoteWarning(nativeUrl: String, jellyfinUrl: String): String? {
        val native = host(nativeUrl) ?: return null
        val jellyfin = host(jellyfinUrl) ?: return null
        if (isHomeNetworkHost(native) || !isHomeNetworkHost(jellyfin)) return null
        return "You signed in to Silo at $native, but Silo gives Zelefin $jellyfin for its Jellyfin-compatible API, " +
            "which only works on your home network. To use Zelefin away from home, proxy or tunnel that address too " +
            "(or give it a public IP), then set it as the Jellyfin-compatible public URL in Silo's admin settings."
    }

    /** Private, loopback, and link-local addresses, plus names that only resolve at home. */
    fun isHomeNetworkHost(host: String): Boolean {
        val name = host.trim().trim('[', ']').lowercase()
        if (name == "localhost" || name.endsWith(".local") || name.endsWith(".lan") || name.endsWith(".home.arpa") || name.endsWith(".internal")) {
            return true
        }
        if (!name.contains('.') && !name.contains(':')) return true
        val octets = name.split('.').map { it.toIntOrNull() }
        if (octets.size == 4 && octets.all { it != null && it in 0..255 }) {
            val (a, b) = octets[0]!! to octets[1]!!
            return a == 10 || a == 127 || (a == 172 && b in 16..31) || (a == 192 && b == 168) || (a == 169 && b == 254)
        }
        if (name.contains(':')) {
            return name == "::1" || name.startsWith("fc") || name.startsWith("fd") || name.startsWith("fe80")
        }
        return false
    }

    private fun host(url: String): String? =
        runCatching { java.net.URI(url.trim()).host }.getOrNull()?.takeIf { it.isNotBlank() }
}
