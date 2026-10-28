package app.zelefin.client

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
        val picture = pictureSize(
            viewWidth = viewWidth.toFloat(),
            viewHeight = viewHeight.toFloat(),
            videoWidth = videoWidth,
            videoHeight = videoHeight,
            fill = fill,
        )
        val letterboxBottom = ((viewHeight - picture.height) / 2f).coerceAtLeast(0f)
        val lift = (style.positionLift / 100f).coerceIn(0f, 1f)
        val inset = picture.height * (0.06f + 0.32f * lift)
        val placedBottom = (letterboxBottom + inset).coerceIn(0f, viewHeight * 0.48f)
        val bottom = controlsTop?.let { maxOf(placedBottom, viewHeight - it) }?.coerceAtMost(viewHeight * 0.7f) ?: placedBottom
        val line = minOf(picture.bottom - inset, controlsTop ?: Float.MAX_VALUE)
        val shortSide = minOf(viewWidth, viewHeight).toFloat()
        val fontPx = (0.0533f * style.sizeScale * shortSide).coerceAtMost(picture.height * 0.16f)
        val videoScale = (shortSide / picture.height.coerceAtLeast(1f)).coerceIn(1f, 2.4f)
        return Placement(
            pictureHeight = picture.height,
            letterboxBottom = letterboxBottom,
            fractionalTextSize = (fontPx / viewHeight).coerceIn(0.018f, 0.09f),
            bottomPaddingFraction = bottom / viewHeight,
            mpvSubPos = ((line / viewHeight) * 100f).toInt().coerceIn(18, 100),
            mpvFontSize = (style.mpvFontSize * videoScale).roundToInt().coerceIn(28, 72),
        )
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
    )
}
