package app.zelefin.client.plugins

import android.content.Context
import android.content.SharedPreferences
import app.zelefin.core.ServerUrl
import app.zelefin.core.ZelefinException
import java.io.IOException
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

    /** Seerr or Ombi. Both use the address, username, and password above. */
    var requestService: RequestService
        get() = RequestService.from(prefs.getString(REQUEST_SERVICE_KEY, null))
        set(value) = prefs.edit().putString(REQUEST_SERVICE_KEY, value.raw).apply()

    var ombiSession: OmbiSession?
        get() = OmbiSession.fromJson(secrets.getString(OMBI_SESSION_KEY, null))?.takeIf { it.token.isNotEmpty() }
        set(value) {
            secrets.edit().apply {
                if (value != null) putString(OMBI_SESSION_KEY, value.toJson()) else remove(OMBI_SESSION_KEY)
            }.apply()
        }

    /** The signed-in name on the chosen request server. */
    val requestDisplayName: String?
        get() = when (requestService) {
            RequestService.Seerr -> seerrSession?.displayName
            RequestService.Ombi -> ombiSession?.displayName
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
        get() = normalizedSeerrUrl != null && requestDisplayName != null

    fun rememberSignIn(session: SeerrSession, username: String, password: String, ownerAccountId: String?) {
        seerrSession = session
        seerrCredentials = SeerrCredentials(username, password)
        seerrOwnerAccountId = ownerAccountId
    }

    /** Signs in to the chosen request server and keeps the password for signing in again later. Returns the name it signed in as. */
    suspend fun signIn(url: String, username: String, password: String, ownerAccountId: String?): String {
        val candidates = ServerUrl.candidates(url)
        if (candidates.isEmpty()) throw ZelefinException.server("Enter your ${requestService.title} address.")
        for ((index, candidate) in candidates.withIndex()) {
            try {
                val name = signInAt(candidate, username, password, ownerAccountId)
                seerrUrl = candidate
                return name
            } catch (error: IOException) {
                if (index == candidates.lastIndex) throw error
            }
        }
        throw ZelefinException.server("Enter your ${requestService.title} address.")
    }

    private suspend fun signInAt(normalized: String, username: String, password: String, ownerAccountId: String?): String =
        when (requestService) {
            RequestService.Seerr -> {
                val signedIn = SeerrClient.signIn(normalized, username, password)
                rememberSignIn(signedIn, username, password, ownerAccountId)
                val user = runCatching { SeerrClient(normalized, signedIn).currentUser() }.getOrNull()
                user?.displayLabel?.also { seerrSession = signedIn.copy(displayName = it) } ?: signedIn.displayName
            }
            RequestService.Ombi -> {
                val signedIn = OmbiClient.signIn(normalized, username, password)
                seerrSession = null
                ombiSession = signedIn
                seerrCredentials = SeerrCredentials(username, password)
                seerrOwnerAccountId = ownerAccountId
                signedIn.displayName
            }
        }

    fun clearSeerrSession() {
        seerrSession = null
        ombiSession = null
        seerrCredentials = null
        seerrOwnerAccountId = null
    }

    /** Confirms the stored session, or signs in again with the saved password. Network failures keep the session. */
    suspend fun refreshUser(): SeerrUser? {
        val client = requestClient() ?: return null
        return try {
            client.currentUser().also { user ->
                when (requestService) {
                    RequestService.Seerr -> seerrSession = seerrSession?.copy(displayName = user.displayLabel)
                    RequestService.Ombi -> ombiSession = ombiSession?.copy(displayName = user.displayLabel)
                }
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
        if (requestService == RequestService.Ombi) {
            return try {
                val signedIn = OmbiClient.signIn(url, credentials.username, credentials.password)
                ombiSession = signedIn
                runCatching { OmbiClient(url, signedIn).currentUser() }.getOrNull()
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (error: Throwable) {
                if (error.isSeerrUnauthorized) clearSeerrSession()
                null
            }
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
        if (requestService != RequestService.Seerr) return null
        val url = normalizedSeerrUrl ?: return null
        val session = seerrSession ?: return null
        return SeerrClient(url, session)
    }

    /** The chosen request server's client, or null when signed out. */
    fun requestClient(): RequestCatalog? {
        val url = normalizedSeerrUrl ?: return null
        return when (requestService) {
            RequestService.Seerr -> seerrSession?.let { SeerrRequestCatalog(SeerrClient(url, it)) }
            RequestService.Ombi -> ombiSession?.let { OmbiClient(url, it) }
        }
    }

    var autoSkipIntro: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_INTRO_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_INTRO_KEY, value).apply()

    var autoSkipCredits: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_CREDITS_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_CREDITS_KEY, value).apply()

    var autoSkipRecap: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_RECAP_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_RECAP_KEY, value).apply()

    var autoSkipPreview: Boolean
        get() = prefs.getBoolean(AUTO_SKIP_PREVIEW_KEY, false)
        set(value) = prefs.edit().putBoolean(AUTO_SKIP_PREVIEW_KEY, value).apply()

    /** Ask TheIntroDB for skip times when the server has none for a title. On unless turned off. */
    var usesTheIntroDB: Boolean
        get() = prefs.getBoolean(THEINTRODB_KEY, true)
        set(value) = prefs.edit().putBoolean(THEINTRODB_KEY, value).apply()

    companion object {
        const val PREFS_NAME = "zelefin.plugins"
        const val SECRETS_NAME = "zelefin.secrets"
        const val SEERR_URL_KEY = "zelefin.seerr.url"
        const val AUTO_SKIP_INTRO_KEY = "zelefin.playback.auto-skip-intro"
        const val AUTO_SKIP_CREDITS_KEY = "zelefin.playback.auto-skip-credits"
        const val AUTO_SKIP_RECAP_KEY = "zelefin.playback.auto-skip-recap"
        const val AUTO_SKIP_PREVIEW_KEY = "zelefin.playback.auto-skip-preview"
        const val THEINTRODB_KEY = "zelefin.playback.theintrodb"
        private const val SEERR_SESSION_KEY = "seerr-session"
        private const val SEERR_CREDENTIALS_KEY = "seerr-credentials"
        private const val SEERR_OWNER_KEY = "zelefin.seerr.owner"
        private const val REQUEST_SERVICE_KEY = "zelefin.requests.service"
        private const val OMBI_SESSION_KEY = "ombi-session"
        private const val LEGACY_API_KEY = "seerr-api-key"

        /** The address cleaned the way the sign-in screen cleans a server address. */
        fun normalizeSeerrUrl(raw: String): String? = ServerUrl.candidates(raw).firstOrNull()

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
