package app.zelefin.client.ui

import androidx.compose.foundation.background
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.dp

/**
 * Controls drawn over video, on the dock's liquid glass. SDR video plays on a TextureView, so the
 * glass refracts the picture; HDR's SurfaceView cannot be sampled, so there the glass is a tint
 * with the dock's rim. Off keeps the solid surface.
 */
@Composable
internal fun Modifier.playerGlass(shape: Shape): Modifier {
    val shadowed = this
        .shadow(6.dp, shape, clip = false, ambientColor = Color.Black.copy(alpha = 0.28f), spotColor = Color.Black.copy(alpha = 0.36f))
        .clip(shape)
    if (GlassPreferences.mode == GlassMode.Off) {
        return shadowed.background(MaterialTheme.colorScheme.surfaceContainerHigh.copy(alpha = 0.94f))
    }
    val base = GlassPreferences.style
    // A touch more tint than the dock so icons read over moving video.
    val style = base.copy(tintAlpha = maxOf(base.tintAlpha, 0.3f))
    val tinted = style.tint.copy(alpha = (style.tintAlpha + 0.3f).coerceIn(0.42f, 0.92f))
    return shadowed.zelefinLiquidGlassBackground(shape, fallback = tinted, style = style, rimOnFallback = true)
}
