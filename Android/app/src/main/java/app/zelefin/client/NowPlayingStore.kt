package app.zelefin.client

import android.content.Context
import app.zelefin.core.MediaItem
import kotlinx.serialization.json.Json

/** Last title played, per account, so the mini player is back after a cold start. Same key as iOS. */
class NowPlayingStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.now-playing", Context.MODE_PRIVATE)

    fun load(accountId: String): MediaItem? {
        val raw = prefs.getString(key(accountId), null) ?: return null
        return runCatching { json.decodeFromString(MediaItem.serializer(), raw) }.getOrNull()
    }

    fun save(item: MediaItem?, accountId: String) {
        val edit = prefs.edit()
        if (item == null) {
            edit.remove(key(accountId))
        } else {
            edit.putString(key(accountId), json.encodeToString(MediaItem.serializer(), item))
        }
        edit.apply()
    }

    private fun key(accountId: String) = "zelefin.now-playing.$accountId"

    private companion object {
        val json = Json { ignoreUnknownKeys = true }
    }
}
