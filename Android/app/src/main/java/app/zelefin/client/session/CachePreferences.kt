package app.zelefin.client.session

import android.content.Context

/** Same keys as iOS `CachePreferences`. */
object CachePreferences {
    const val AUTO_REFRESH_IMAGES = "zelefin.cache.auto-refresh-missing-images"
    const val AUTO_REFRESH_METADATA = "zelefin.cache.auto-refresh-missing-metadata"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("zelefin.cache", Context.MODE_PRIVATE)

    fun autoRefreshMissingImages(context: Context): Boolean =
        prefs(context).getBoolean(AUTO_REFRESH_IMAGES, false)

    fun setAutoRefreshMissingImages(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(AUTO_REFRESH_IMAGES, enabled).apply()
    }

    fun autoRefreshMissingMetadata(context: Context): Boolean =
        prefs(context).getBoolean(AUTO_REFRESH_METADATA, false)

    fun setAutoRefreshMissingMetadata(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(AUTO_REFRESH_METADATA, enabled).apply()
    }
}
