package app.zelefin.client.cast

import android.content.Context
import android.net.Uri
import androidx.appcompat.view.ContextThemeWrapper
import androidx.mediarouter.app.MediaRouteChooserDialog
import androidx.mediarouter.app.MediaRouteControllerDialog
import androidx.mediarouter.media.MediaRouter
import app.zelefin.client.R
import app.zelefin.client.ui.findActivity
import app.zelefin.core.MediaItem
import app.zelefin.core.PlaybackPlan
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadOptions
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.images.WebImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference

object ZelefinCast {
    private val cached = AtomicReference<CastContext?>()

    fun warmup(context: Context) {
        val app = context.applicationContext
        runCatching {
            CastContext.getSharedInstance(app, Executors.newSingleThreadExecutor())
                .addOnSuccessListener { cached.compareAndSet(null, it) }
        }
    }

    fun context(context: Context): CastContext? {
        cached.get()?.let { return it }
        val instance = runCatching { CastContext.getSharedInstance(context.applicationContext) }.getOrNull()
        if (instance != null) cached.compareAndSet(null, instance)
        return instance
    }

    fun session(context: Context): CastSession? =
        runCatching { context(context)?.sessionManager?.currentCastSession }.getOrNull()

    fun isConnected(context: Context): Boolean = session(context)?.isConnected == true

    fun remote(context: Context): RemoteMediaClient? = session(context)?.remoteMediaClient

    fun load(context: Context, plan: PlaybackPlan, artworkUrl: String?) {
        val client = remote(context) ?: return
        val metadata = MediaMetadata(
            if (plan.item.seriesName != null) MediaMetadata.MEDIA_TYPE_TV_SHOW else MediaMetadata.MEDIA_TYPE_MOVIE,
        ).apply {
            putString(MediaMetadata.KEY_TITLE, plan.item.name)
            plan.item.seriesName?.let { putString(MediaMetadata.KEY_SERIES_TITLE, it) }
            artworkUrl?.let { addImage(WebImage(Uri.parse(it))) }
        }
        val info = MediaInfo.Builder(castableUrl(plan))
            .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
            .setContentType(contentType(plan))
            .setMetadata(metadata)
            .build()
        val options = MediaLoadOptions.Builder()
            .setAutoplay(true)
            .setPlayPosition((plan.startTimeSeconds * 1000).toLong().coerceAtLeast(0))
            .build()
        runCatching { client.load(info, options) }
    }

    fun play(context: Context) { remote(context)?.play() }
    fun pause(context: Context) { remote(context)?.pause() }
    fun stop(context: Context) { remote(context)?.stop() }
    fun seek(context: Context, seconds: Double) {
        remote(context)?.seek((seconds * 1000).toLong().coerceAtLeast(0))
    }
    fun setVolume(context: Context, level: Double) {
        session(context)?.volume = level.coerceIn(0.0, 1.0)
    }

    fun showChooser(context: Context) {
        val activity = context.findActivity() ?: return
        val cast = context(activity) ?: return
        val selector = runCatching { cast.mergedSelector }.getOrNull() ?: return
        val themed = ContextThemeWrapper(activity, R.style.Theme_Zelefin_CastDialog)
        val router = MediaRouter.getInstance(activity)
        val selected = router.selectedRoute
        val connected = !selected.isDefaultOrBluetooth && selected.matchesSelector(selector)
        runCatching {
            if (connected) {
                MediaRouteControllerDialog(themed).show()
            } else {
                MediaRouteChooserDialog(themed).apply { routeSelector = selector }.show()
            }
        }
    }

    fun titleFor(item: MediaItem): String = item.seriesName?.let { "$it — ${item.name}" } ?: item.name

    private fun castableUrl(plan: PlaybackPlan): String {
        val url = plan.streamUrl
        val token = plan.headers.entries.firstOrNull { it.key.equals("X-Emby-Token", true) || it.key.equals("X-MediaBrowser-Token", true) }?.value
        if (token.isNullOrBlank() || url.contains("api_key=") || url.contains("ApiKey=")) return url
        val join = if (url.contains("?")) "&" else "?"
        return url + join + "api_key=" + token
    }

    private fun contentType(plan: PlaybackPlan): String {
        val container = plan.container?.lowercase().orEmpty()
        return when {
            container.contains("mp4") || container.contains("m4v") -> "video/mp4"
            container.contains("webm") -> "video/webm"
            plan.streamUrl.contains(".m3u8") -> "application/x-mpegURL"
            else -> "video/x-matroska"
        }
    }
}
