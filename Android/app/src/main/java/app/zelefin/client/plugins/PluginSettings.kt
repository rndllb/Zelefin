package app.zelefin.client.plugins

import android.content.Context
import android.content.SharedPreferences
import app.zelefin.core.ZelefinException
import kotlin.coroutines.cancellation.CancellationException

class PluginSettings(context: Context) {
    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    private val secrets: SharedPreferences =
        context.applicationContext.getSharedPreferences(SECRETS_NAME, Context.MODE_PRIVATE)

    /** The Seerr address exactly as the user typed it. */
    var seerrUrl: String
        get() = prefs.getString(SEERR_URL_KEY, null).orEmpty()
        set(value) = prefs.edit().putString(SEERR_URL_KEY, value).apply()

    /** [seerrUrl] with a scheme and no trailing slash, or null when unset. */
    val normalizedSeerrUrl: String?
        get() = normalizeSeerrUrl(seerrUrl)

    var seerrSession: SeerrSession?
        get() = SeerrSession.fromJson(secrets.getString(SEERR_SESSION_KEY, null))
            ?.takeIf { it.cookieValue.isNotEmpty() }
        set(value) {
            secrets.edit().apply {
                if (value != null) putString(SEERR_SESSION_KEY, value.toJson()) else remove(SEERR_SESSION_KEY)
                remove(LEGACY_API_KEY)
            }.apply()
        }

    var seerrCredentials: SeerrCredentials?
        get() = SeerrCredentials.fromJson(secrets.getString(SEERR_CREDENTIALS_KEY, null))
        set(value) {
            secrets.edit().apply {
                if (value != null) putString(SEERR_CREDENTIALS_KEY, value.toJson()) else remove(SEERR_CREDENTIALS_KEY)
            }.apply()
        }

    var seerrOwnerAccountId: String?
        get() = prefs.getString(SEERR_OWNER_KEY, null)?.trim()?.takeIf { it.isNotEmpty() }
        set(value) {
            prefs.edit().apply {
                if (value.isNullOrBlank()) remove(SEERR_OWNER_KEY) else putString(SEERR_OWNER_KEY, value)
            }.apply()
        }

    val isSeerrConfigured: Boolean
        get() = normalizedSeerrUrl != null && seerrSession != null

    fun rememberSignIn(session: SeerrSession, username: String, password: String, ownerAccountId: String?) {
        seerrSession = session
        seerrCredentials = SeerrCredentials(username, password)
        seerrOwnerAccountId = ownerAccountId
    }

    fun clearSeerrSession() {
        seerrSession = null
        seerrCredentials = null
        seerrOwnerAccountId = null
    }

    /** Confirms the stored cookie, or signs in again with the saved password. Network failures keep the session. */
    suspend fun refreshUser(): SeerrUser? {
        val client = seerrClient() ?: return null
        return try {
            client.currentUser().also { user ->
                seerrSession = seerrSession?.copy(displayName = user.displayLabel)
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Throwable) {
            if (!error.isSeerrUnauthorized) return null
            reauthenticate()
        }
    }

    private suspend fun reauthenticate(): SeerrUser? {
        val url = normalizedSeerrUrl
        val credentials = seerrCredentials
        if (url == null || credentials == null) {
            clearSeerrSession()
            return null
        }
        return try {
            val signedIn = SeerrClient.signIn(url, credentials.username, credentials.password)
            seerrSession = signedIn
            runCatching { SeerrClient(url, signedIn).currentUser() }.getOrNull()?.also { user ->
                seerrSession = signedIn.copy(displayName = user.displayLabel)
            }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (error: Throwable) {
            if (error.isSeerrUnauthorized) clearSeerrSession()
            null
        }
    }

    fun seerrClient(): SeerrClient? {
        val url = normalizedSeerrUrl ?: return null
        val session = seerrSession ?: return null
        return SeerrClient(url, session)
    }

    var siloRequestSource: SiloRequestSource
        get() = SiloRequestSource.fromRaw(prefs.getString(SILO_REQUEST_SOURCE_KEY, null)) ?: SiloRequestSource.Seerr
        set(value) = prefs.edit().putString(SILO_REQUEST_SOURCE_KEY, value.raw).apply()

    var autoSkipIntro: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_INTRO_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_INTRO_KEY, value).apply()

    var autoSkipCredits: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_CREDITS_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_CREDITS_KEY, value).apply()

    companion object {
        const val PREFS_NAME = "zelefin.plugins"
        const val SECRETS_NAME = "zelefin.secrets"
        const val SEERR_URL_KEY = "zelefin.seerr.url"
        const val SILO_REQUEST_SOURCE_KEY = "zelefin.silo.request-source"
        const val AUTO_SKIP_INTRO_KEY = "zelefin.playback.auto-skip-intro"
        const val AUTO_SKIP_CREDITS_KEY = "zelefin.playback.auto-skip-credits"
        private const val SEERR_SESSION_KEY = "seerr-session"
        private const val SEERR_CREDENTIALS_KEY = "seerr-credentials"
        private const val SEERR_OWNER_KEY = "zelefin.seerr.owner"
        private const val LEGACY_API_KEY = "seerr-api-key"

        fun normalizeSeerrUrl(raw: String): String? {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return null
            val bare = trimmed.trimEnd('/')
            return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) bare else "https://$bare"
        }

        /** Keep Seerr across relaunch and app updates. Drop it only when a different Jellyfin user is applied. */
        fun shouldClearSession(switchingFrom: String?, to: String, ownerAccountId: String? = null): Boolean {
            if (switchingFrom != null && switchingFrom != to) return true
            if (ownerAccountId != null && ownerAccountId != to) return true
            return false
        }
    }
}

internal val Throwable.isSeerrUnauthorized: Boolean
    get() = this is ZelefinException && code == ZelefinException.Code.SeerrUnauthorized
