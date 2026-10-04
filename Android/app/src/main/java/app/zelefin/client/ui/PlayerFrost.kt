package app.zelefin.client.ui

import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.SurfaceView
import androidx.compose.foundation.border
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt
import kotlinx.coroutines.delay

/**
 * Haze only samples what Compose draws, and the video is a SurfaceView it can't see.
 * The player grabs a tiny copy of the current frame instead, and each control paints that copy
 * blurred behind itself, so the controls frost the picture like the dock frosts the app.
 */
internal object PlayerFrost {
    private val buffers = arrayOfNulls<Bitmap>(2)
    private var next = 0
    private var copying = false
    private val main = Handler(Looper.getMainLooper())

    var frame by mutableStateOf<ImageBitmap?>(null)
        private set
    var bounds by mutableStateOf(Rect.Zero)
        private set
    var version by mutableIntStateOf(0)
        private set

    fun capture(surface: SurfaceView) {
        if (copying || !surface.holder.surface.isValid || surface.width <= 0 || surface.height <= 0) return
        val width = (surface.width / Downscale).coerceAtLeast(8)
        val height = (surface.height / Downscale).coerceAtLeast(8)
        val bitmap = buffers[next]?.takeIf { it.width == width && it.height == height }
            ?: Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also { buffers[next] = it }
        copying = true
        val copied = runCatching {
            PixelCopy.request(surface, bitmap, { result ->
                copying = false
                if (result != PixelCopy.SUCCESS || surface.width <= 0) return@request
                val location = IntArray(2)
                surface.getLocationInWindow(location)
                bounds = Rect(
                    location[0].toFloat(),
                    location[1].toFloat(),
                    (location[0] + surface.width).toFloat(),
                    (location[1] + surface.height).toFloat(),
                )
                frame = bitmap.asImageBitmap()
                next = 1 - next
                version += 1
            }, main)
        }
        if (copied.isFailure) copying = false
    }

    fun clear() {
        frame = null
        buffers.fill(null)
    }

    private const val Downscale = 10
}

/** Keeps [PlayerFrost] fed while any frosted control is on screen. */
@Composable
internal fun PlayerFrostCapture(surface: SurfaceView?, active: Boolean, playing: Boolean) {
    LaunchedEffect(surface, active, playing) {
        if (surface == null || !active) return@LaunchedEffect
        while (true) {
            PlayerFrost.capture(surface)
            delay(if (playing) 66 else 400)
        }
    }
}

private val FrostTint = Color(0x5228282A)
private val FrostStroke = Color.White.copy(alpha = 0.22f)
private val FrostBlur = 14.dp

/** Frosted glass for controls drawn over video. */
@Composable
internal fun Modifier.playerGlass(shape: Shape): Modifier {
    var origin by remember { mutableStateOf(Offset.Zero) }
    val layer = rememberGraphicsLayer()
    return this
        .shadow(6.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.10f), spotColor = Color.Black.copy(alpha = 0.16f))
        .onGloballyPositioned { origin = it.positionInWindow() }
        .clip(shape)
        .drawBehind {
            PlayerFrost.version
            val frame = PlayerFrost.frame
            val bounds = PlayerFrost.bounds
            if (frame != null && bounds.width > 0f) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val radius = FrostBlur.toPx()
                    layer.renderEffect = BlurEffect(radius, radius, TileMode.Clamp)
                }
                layer.record {
                    drawImage(
                        image = frame,
                        srcOffset = IntOffset.Zero,
                        srcSize = IntSize(frame.width, frame.height),
                        dstOffset = IntOffset((bounds.left - origin.x).roundToInt(), (bounds.top - origin.y).roundToInt()),
                        dstSize = IntSize(bounds.width.roundToInt(), bounds.height.roundToInt()),
                        filterQuality = FilterQuality.Low,
                    )
                }
                drawLayer(layer)
            }
            drawRect(FrostTint)
        }
        .border(0.8.dp, FrostStroke, shape)
}
