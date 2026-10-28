package app.zelefin.client

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.ui.CaptionStyleCompat
import androidx.media3.ui.CaptionStyleCompat.EDGE_TYPE_DROP_SHADOW
import androidx.media3.ui.CaptionStyleCompat.EDGE_TYPE_NONE
import androidx.media3.ui.CaptionStyleCompat.EDGE_TYPE_OUTLINE
import androidx.media3.ui.PlayerView
import kotlin.math.abs
import kotlin.math.roundToInt

/** Text-subtitle look and timing stored on this device. */
object SubtitleAppearance {
    /** Image subtitle codecs, as mpv, Media3 and Jellyfin name them (hdmv_pgs_subtitle, application/pgs, dvdsub). */
    fun isPictureCodec(codec: String?): Boolean {
        val name = codec?.lowercase() ?: return false
        return listOf("pgs", "dvd_sub", "dvdsub", "vobsub", "dvb_sub", "dvbsub", "xsub").any { it in name }
    }

    const val SIZE = "subtitle-size"
    const val COLOR = "subtitle-color"
    const val BACKGROUND = "subtitle-background"
    const val BRIGHTNESS = "subtitle-brightness"
    const val POSITION = "subtitle-position"
    const val SYNC = "subtitle-sync-seconds"

    const val SIZE_SMALL = "small"
    const val SIZE_MEDIUM = "medium"
    const val SIZE_LARGE = "large"
    const val SIZE_EXTRA = "extraLarge"

    const val COLOR_WHITE = "white"
    const val COLOR_YELLOW = "yellow"
    const val COLOR_CYAN = "cyan"
    const val COLOR_GREEN = "green"
    const val COLOR_MAGENTA = "magenta"

    const val BACK_NONE = "none"
    const val BACK_SHADOW = "dropShadow"
    const val BACK_OUTLINE = "outline"
    const val BACK_HIGHLIGHT = "highlight"

    val sizes = listOf(SIZE_SMALL, SIZE_MEDIUM, SIZE_LARGE, SIZE_EXTRA)
    val colors = listOf(COLOR_WHITE, COLOR_YELLOW, COLOR_CYAN, COLOR_GREEN, COLOR_MAGENTA)
    val backgrounds = listOf(BACK_NONE, BACK_SHADOW, BACK_OUTLINE, BACK_HIGHLIGHT)

    data class Snapshot(
        val size: String = SIZE_MEDIUM,
        val color: String = COLOR_WHITE,
        val background: String = BACK_SHADOW,
        val brightness: Int = 100,
        val positionLift: Int = 0,
        val syncSeconds: Double = 0.0,
    ) {
        val sizeScale: Float = when (size) {
            SIZE_SMALL -> 0.78f
            SIZE_LARGE -> 1.28f
            SIZE_EXTRA -> 1.58f
            else -> 1f
        }

        val fractionalTextSize: Float = 0.0533f * sizeScale
        val bottomPadding: Float = 0.08f + (positionLift / 100f) * 0.28f
        val mpvFontSize: Int = (34 * sizeScale).roundToInt().coerceIn(22, 56)
        val mpvMarginY: Int = (24 + positionLift * 1.4).roundToInt()
        val isDefault: Boolean =
            size == SIZE_MEDIUM &&
                color == COLOR_WHITE &&
                background == BACK_SHADOW &&
                brightness >= 99 &&
                positionLift == 0

        fun sizeTitle(): String = sizeTitle(size)
        fun colorTitle(): String = colorTitle(color)
        fun backgroundTitle(): String = backgroundTitle(background)
        fun positionTitle(): String = if (positionLift > 0) "Raised" else "Default"
        fun syncTitle(): String = syncTitle(syncSeconds)

        fun foregroundArgb(): Int {
            val base = when (color) {
                COLOR_YELLOW -> Color.rgb(255, 235, 51)
                COLOR_CYAN -> Color.rgb(89, 235, 255)
                COLOR_GREEN -> Color.rgb(115, 242, 115)
                COLOR_MAGENTA -> Color.rgb(255, 115, 217)
                else -> Color.WHITE
            }
            val alpha = (brightness.coerceIn(10, 100) * 255 / 100)
            return Color.argb(alpha, Color.red(base), Color.green(base), Color.blue(base))
        }

        fun windowArgb(): Int = if (background == BACK_HIGHLIGHT) {
            Color.argb((brightness.coerceIn(10, 100) * 158 / 100), 0, 0, 0)
        } else {
            Color.TRANSPARENT
        }

        fun edgeType(): Int = when (background) {
            BACK_OUTLINE -> EDGE_TYPE_OUTLINE
            BACK_SHADOW -> EDGE_TYPE_DROP_SHADOW
            else -> EDGE_TYPE_NONE
        }

        fun mpvColor(): String = argbHex(foregroundArgb())
        fun mpvBackColor(): String = if (background == BACK_HIGHLIGHT) argbHex(windowArgb()) else "#00000000"
        fun mpvBorderSize(): String = if (background == BACK_OUTLINE) "2.5" else "0"
        fun mpvShadowOffset(): String = if (background == BACK_SHADOW) "2.4" else "0"
    }

    fun current(context: Context): Snapshot {
        val prefs = context.getSharedPreferences(PlaybackPreferences.NAME, Context.MODE_PRIVATE)
        return Snapshot(
            size = resolvedSize(prefs.getString(SIZE, SIZE_MEDIUM)),
            color = resolvedColor(prefs.getString(COLOR, COLOR_WHITE)),
            background = resolvedBackground(prefs.getString(BACKGROUND, BACK_SHADOW)),
            brightness = prefs.getInt(BRIGHTNESS, 100).coerceIn(10, 100),
            positionLift = prefs.getInt(POSITION, 0).coerceIn(0, 100),
            syncSeconds = snappedSync(prefs.getFloat(SYNC, 0f).toDouble()),
        )
    }

    fun setSize(context: Context, value: String) = write(context) { putString(SIZE, resolvedSize(value)) }
    fun setColor(context: Context, value: String) = write(context) { putString(COLOR, resolvedColor(value)) }
    fun setBackground(context: Context, value: String) = write(context) { putString(BACKGROUND, resolvedBackground(value)) }
    fun setBrightness(context: Context, value: Int) = write(context) { putInt(BRIGHTNESS, value.coerceIn(10, 100)) }
    fun setPositionLift(context: Context, value: Int) = write(context) { putInt(POSITION, value.coerceIn(0, 100)) }
    fun setPosition(context: Context, raised: Boolean) = setPositionLift(context, if (raised) 45 else 0)
    fun setSyncSeconds(context: Context, value: Double) = write(context) { putFloat(SYNC, snappedSync(value).toFloat()) }

    fun snappedSync(value: Double): Double {
        val clamped = value.coerceIn(-10.0, 10.0)
        return (clamped / 0.25).roundToInt() * 0.25
    }

    fun sizeTitle(value: String): String = when (resolvedSize(value)) {
        SIZE_SMALL -> "Small"
        SIZE_LARGE -> "Large"
        SIZE_EXTRA -> "Extra Large"
        else -> "Medium"
    }

    fun colorTitle(value: String): String = when (resolvedColor(value)) {
        COLOR_YELLOW -> "Yellow"
        COLOR_CYAN -> "Cyan"
        COLOR_GREEN -> "Green"
        COLOR_MAGENTA -> "Magenta"
        else -> "White"
    }

    fun backgroundTitle(value: String): String = when (resolvedBackground(value)) {
        BACK_NONE -> "None"
        BACK_OUTLINE -> "Outline"
        BACK_HIGHLIGHT -> "Highlight"
        else -> "Drop Shadow"
    }

    fun syncTitle(seconds: Double): String {
        val value = snappedSync(seconds)
        if (abs(value) < 0.001) return "In Sync"
        val whole = value == value.toInt().toDouble()
        val body = if (whole) "${value.toInt()}" else {
            val text = String.format("%.2f", value)
            text.replace(Regex("0+$"), "").removeSuffix(".")
        }
        return if (value > 0) "+$body s" else "$body s"
    }

    @OptIn(UnstableApi::class)
    fun applyTo(view: PlayerView, style: Snapshot = current(view.context), fill: Boolean = false, controlsTop: Float? = null) {
        val video = view.player?.videoSize
        val videoWidth = if (video != null && video.width > 0) {
            video.width * video.pixelWidthHeightRatio
        } else {
            0f
        }
        val videoHeight = video?.height?.toFloat() ?: 0f
        val placed = SubtitlePictureLayout.placement(
            viewWidth = view.width,
            viewHeight = view.height,
            videoWidth = videoWidth,
            videoHeight = videoHeight,
            fill = fill,
            style = style,
            controlsTop = controlsTop,
        )
        view.subtitleView?.apply {
            setStyle(
                CaptionStyleCompat(
                    style.foregroundArgb(),
                    style.windowArgb(),
                    Color.TRANSPARENT,
                    style.edgeType(),
                    Color.BLACK,
                    Typeface.DEFAULT_BOLD,
                ),
            )
            setFractionalTextSize(placed.fractionalTextSize)
            setBottomPaddingFraction(placed.bottomPaddingFraction)
            setApplyEmbeddedStyles(false)
            setApplyEmbeddedFontSizes(false)
        }
    }

    private fun resolvedSize(raw: String?): String = if (raw in sizes) raw!! else SIZE_MEDIUM
    private fun resolvedColor(raw: String?): String = if (raw in colors) raw!! else COLOR_WHITE
    private fun resolvedBackground(raw: String?): String = if (raw in backgrounds) raw!! else BACK_SHADOW

    private fun argbHex(color: Int): String = String.format("#%08X", color)

    private fun write(context: Context, edit: android.content.SharedPreferences.Editor.() -> Unit) {
        context.getSharedPreferences(PlaybackPreferences.NAME, Context.MODE_PRIVATE).edit().apply(edit).apply()
    }
}
