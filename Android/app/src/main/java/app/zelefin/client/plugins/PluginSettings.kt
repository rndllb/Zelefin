package app.zelefin.client.plugins

import android.content.Context
import android.content.SharedPreferences

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

    val isSeerrConfigured: Boolean
        get() = normalizedSeerrUrl != null && seerrSession != null

    fun clearSeerrSession() {
        seerrSession = null
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
        private const val LEGACY_API_KEY = "seerr-api-key"

        fun normalizeSeerrUrl(raw: String): String? {
            val trimmed = raw.trim()
            if (trimmed.isEmpty()) return null
            val bare = trimmed.trimEnd('/')
            return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) bare else "https://$bare"
        }

        /** Keep Seerr across relaunch. Drop it only when a different Jellyfin user is applied. */
        fun shouldClearSession(switchingFrom: String?, to: String): Boolean {
            switchingFrom ?: return false
            return switchingFrom != to
        }
    }
}
