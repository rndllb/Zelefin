package app.zelefin.client.ui

import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.BifIndex
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.TrickplayInfo
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request

/** BIF frames shaped as one-thumbnail trickplay tiles, so the timeline preview shows them unchanged. */
internal class BifPreviews(private val index: BifIndex, val info: TrickplayInfo) {
    fun frame(seconds: Double): ByteArray? = index.frameAt(seconds)
}

/** Null until the file arrives, and for good when the server has no thumbnails for the title. */
@Composable
internal fun rememberBifPreviews(plan: PlaybackPlan): BifPreviews? {
    val url = plan.bifUrl?.takeIf { plan.trickplay == null && !plan.streamUrl.startsWith("file:") }
    val previews by produceState<BifPreviews?>(null, url) {
        value = url?.let { withContext(Dispatchers.IO) { loadBif(it, plan.headers) } }
    }
    return previews
}

private fun loadBif(url: String, headers: Map<String, String>): BifPreviews? {
    val request = Request.Builder().url(url).apply { headers.forEach { (name, value) -> header(name, value) } }.build()
    val bytes = runCatching {
        GatewayHttp.playback.newCall(request).execute().use { if (it.isSuccessful) it.body?.bytes() else null }
    }.getOrNull() ?: return null
    val index = BifIndex.parse(bytes) ?: return null
    val first = index.frame(0) ?: return null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(first, 0, first.size, bounds)
    val width = bounds.outWidth.takeIf { it > 0 } ?: 320
    val height = bounds.outHeight.takeIf { it > 0 } ?: 180
    return BifPreviews(
        index,
        TrickplayInfo(
            width = width,
            interval = index.intervalSeconds,
            thumbnailCount = index.frameCount,
            tileWidth = 1,
            tileHeight = 1,
            thumbnailWidth = width,
            thumbnailHeight = height,
            mediaSourceId = null,
        ),
    )
}
