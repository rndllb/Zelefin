package app.zelefin.client.ui

import android.content.res.Configuration
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.zIndex

/**
 * True on an Android TV / Google TV device (its UI mode is television). Distinct from [isLargeScreen],
 * which also covers tablets and Chromebooks — TV needs D-pad focus handling that touch devices must not get.
 */
internal fun Configuration.isTelevision(): Boolean =
    (uiMode and Configuration.UI_MODE_TYPE_MASK) == Configuration.UI_MODE_TYPE_TELEVISION

/** Whether the app is running on a TV, for composables that adapt navigation to a D-pad remote. */
val LocalIsTv = staticCompositionLocalOf { false }

/**
 * A visible D-pad focus cue for Android TV: the element grows a little while focused, the way TV home
 * rows highlight the selected card. On touch devices nothing takes focus, so this is inert there.
 *
 * Place it immediately before the `.clickable(...)` on a card or button, so it observes that element's
 * focus. A focused card is also lifted above its neighbours so the grown edge isn't clipped by them.
 */
fun Modifier.tvFocusScale(focusedScale: Float = 1.08f): Modifier = composed {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (focused) focusedScale else 1f,
        label = "tvFocusScale",
    )
    this
        .onFocusChanged { focused = it.isFocused }
        .zIndex(if (focused) 1f else 0f)
        .scale(scale)
}
