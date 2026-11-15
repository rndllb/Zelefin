package app.zelefin.client

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** Places captions on the fitted video picture, not in letterbox bars. */
object SubtitlePictureLayout {
    data class Placement(
        val pictureHeight: Float,
        val letterboxBottom: Float,
        val fractionalTextSize: Float,
        val bottomPaddingFraction: Float,
        val mpvSubPos: Int,
        val mpvFontSize: Int,
        /** `sub-scale` for mpv. Fill/panscan zooms the picture, so this is shrunk by that zoom. */
        val mpvSubScale: Float,
    )

    fun placement(
        viewWidth: Int,
        viewHeight: Int,
        videoWidth: Float,
        videoHeight: Float,
        fill: Boolean,
        style: SubtitleAppearance.Snapshot,
        /** Top of the visible progress bar in view pixels; captions that would sit under it rise above it. */
        controlsTop: Float? = null,
    ): Placement {
        if (viewWidth <= 0 || viewHeight <= 0) {
            return fallback(style)
        }
        val viewW = viewWidth.toFloat()
        val viewH = viewHeight.toFloat()
        val picture = pictureSize(
            viewWidth = viewW,
            viewHeight = viewH,
            videoWidth = videoWidth,
            videoHeight = videoHeight,
            fill = fill,
        )
        val letterboxBottom = ((viewH - picture.height) / 2f).coerceAtLeast(0f)
        val lift = (style.positionLift / 100f).coerceIn(0f, 1f)
        // Use the on-screen picture height so fill's cropped edges do not pull the inset off-screen.
        val visiblePictureHeight = min(picture.height, viewH)
        val inset = visiblePictureHeight * (0.06f + 0.32f * lift)
        val placedBottom = (letterboxBottom + inset).coerceIn(0f, viewH * 0.48f)
        val bottom = controlsTop?.let { maxOf(placedBottom, viewH - it) }?.coerceAtMost(viewH * 0.7f) ?: placedBottom
        // Cap to the window so a panscan crop cannot leave the baseline below the visible edge.
        val line = minOf(picture.bottom - inset, viewH, controlsTop ?: Float.MAX_VALUE)
        val shortSide = min(viewW, viewH)
        val fontPx = (0.0533f * style.sizeScale * shortSide).coerceAtMost(visiblePictureHeight * 0.16f)
        val videoScale = (shortSide / visiblePictureHeight.coerceAtLeast(1f)).coerceIn(1f, 2.4f)
        val zoom = fillZoom(viewW, viewH, videoWidth, videoHeight).takeIf { fill } ?: 1f
        return Placement(
            pictureHeight = picture.height,
            letterboxBottom = letterboxBottom,
            fractionalTextSize = (fontPx / viewH).coerceIn(0.018f, 0.09f),
            bottomPaddingFraction = bottom / viewH,
            mpvSubPos = ((line / viewH) * 100f).toInt().coerceIn(18, 100),
            mpvFontSize = (style.mpvFontSize * videoScale).roundToInt().coerceIn(28, 72),
            mpvSubScale = style.sizeScale / zoom,
        )
    }

    /** How much fill/panscan enlarges the fitted picture. 1 when the picture already fills the window. */
    fun fillZoom(viewWidth: Float, viewHeight: Float, videoWidth: Float, videoHeight: Float): Float {
        if (viewWidth <= 0f || viewHeight <= 0f || videoWidth <= 0f || videoHeight <= 0f) return 1f
        val fit = min(viewWidth / videoWidth, viewHeight / videoHeight)
        val filled = max(viewWidth / videoWidth, viewHeight / videoHeight)
        return if (fit > 0f) max(filled / fit, 1f) else 1f
    }

    data class PictureSize(val width: Float, val height: Float, val bottom: Float)

    fun pictureSize(
        viewWidth: Float,
        viewHeight: Float,
        videoWidth: Float,
        videoHeight: Float,
        fill: Boolean,
    ): PictureSize {
        if (viewWidth <= 0f || viewHeight <= 0f || videoWidth <= 0f || videoHeight <= 0f) {
            return PictureSize(viewWidth, viewHeight, viewHeight)
        }
        val videoAspect = videoWidth / videoHeight
        val viewAspect = viewWidth / viewHeight
        return if (fill) {
            if (videoAspect > viewAspect) {
                PictureSize(viewHeight * videoAspect, viewHeight, viewHeight)
            } else {
                val height = viewWidth / videoAspect
                val y = (viewHeight - height) / 2f
                PictureSize(viewWidth, height, y + height)
            }
        } else if (videoAspect > viewAspect) {
            val height = viewWidth / videoAspect
            val y = (viewHeight - height) / 2f
            PictureSize(viewWidth, height, y + height)
        } else {
            PictureSize(viewHeight * videoAspect, viewHeight, viewHeight)
        }
    }

    private fun fallback(style: SubtitleAppearance.Snapshot) = Placement(
        pictureHeight = 0f,
        letterboxBottom = 0f,
        fractionalTextSize = style.fractionalTextSize,
        bottomPaddingFraction = style.bottomPadding,
        mpvSubPos = 100,
        mpvFontSize = style.mpvFontSize,
        mpvSubScale = style.sizeScale,
    )
}
