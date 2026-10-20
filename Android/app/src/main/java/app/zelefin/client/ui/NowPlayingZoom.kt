package app.zelefin.client.ui

import android.os.Build
import android.view.RoundedCorner
import android.view.View
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.util.lerp
import app.zelefin.core.MediaItem
import app.zelefin.core.SavedSession
import coil.compose.AsyncImage
import kotlinx.coroutines.delay

/** Material emphasized-decelerate, shared with the app's page transitions so the zoom feels of a piece. */
private val ZoomEasing = CubicBezierEasing(0.32f, 0.72f, 0f, 1f)

/** One duration for open and close, so the shrink is the exact reverse of the growth. */
private const val ZoomDurationMs = 340

/**
 * Apple Music style hand-off between the mini player and the full-screen player. A card grows
 * from the mini player artwork's frame to the full screen (and back), so the player itself
 * never has to scale. Video surfaces ignore Compose transforms.
 */
@Stable
class NowPlayingZoomState {
    enum class Phase { Idle, Opening, Waiting, Handoff, Closing }

    var phase by mutableStateOf(Phase.Idle)
        private set
    internal val progress = Animatable(0f)
    internal val alpha = Animatable(1f)
    internal var startsFull = false

    /** Mini player tapped: grow out of its artwork and wait for the player. */
    fun open() {
        startsFull = false
        phase = Phase.Opening
    }

    /** Player closed: start full screen and fold back into the artwork. */
    fun close() {
        startsFull = true
        phase = Phase.Closing
    }

    internal fun settle(next: Phase) {
        phase = next
    }
}

@Composable
fun NowPlayingZoomOverlay(
    chrome: DockChromeState,
    item: MediaItem?,
    session: SavedSession?,
    playerShowing: Boolean,
    loading: Boolean,
) {
    val zoom = chrome.zoom
    val showing by rememberUpdatedState(playerShowing)
    LaunchedEffect(zoom.phase) {
        when (zoom.phase) {
            // A crisp emphasized-decelerate (the same curve as the app's page transitions), not a soft
            // critically-damped spring. The spring's long tail reached full size early but only reported
            // "done" ~150ms later, leaving the card hanging at full screen before the hand-off — the
            // sluggish part. A fixed curve lands and hands off on a predictable beat, with no overshoot.
            NowPlayingZoomState.Phase.Opening -> {
                zoom.alpha.snapTo(1f)
                zoom.progress.snapTo(0f)
                zoom.progress.animateTo(1f, tween(ZoomDurationMs, easing = ZoomEasing))
                zoom.settle(if (showing) NowPlayingZoomState.Phase.Handoff else NowPlayingZoomState.Phase.Waiting)
            }
            NowPlayingZoomState.Phase.Closing -> {
                zoom.alpha.snapTo(1f)
                if (zoom.startsFull) zoom.progress.snapTo(1f)
                // Exactly the open's motion in reverse: same curve, same duration, animating 1 -> 0 so the
                // card settles into the mini the way it settled into full screen. By progress 0 it already
                // looks like the mini row, so the live dock takes over on a single hand-off frame.
                zoom.progress.animateTo(0f, tween(ZoomDurationMs, easing = ZoomEasing))
                zoom.settle(NowPlayingZoomState.Phase.Idle)
            }
            NowPlayingZoomState.Phase.Handoff -> {
                zoom.alpha.animateTo(0f, tween(150))
                zoom.settle(NowPlayingZoomState.Phase.Idle)
            }
            NowPlayingZoomState.Phase.Waiting, NowPlayingZoomState.Phase.Idle -> Unit
        }
    }
    LaunchedEffect(playerShowing, zoom.phase) {
        if (playerShowing && zoom.phase == NowPlayingZoomState.Phase.Waiting) {
            zoom.settle(NowPlayingZoomState.Phase.Handoff)
        }
    }
    // Playback failed to start: fold back into the mini player instead of leaving a black card.
    LaunchedEffect(loading, playerShowing, zoom.phase) {
        if (zoom.phase != NowPlayingZoomState.Phase.Waiting || loading || playerShowing) return@LaunchedEffect
        delay(400)
        if (zoom.phase == NowPlayingZoomState.Phase.Waiting) {
            zoom.startsFull = false
            zoom.settle(NowPlayingZoomState.Phase.Closing)
        }
    }
    if (zoom.phase == NowPlayingZoomState.Phase.Idle) return
    val bar = chrome.miniBar
    if (bar.width <= 0f) return

    val density = LocalDensity.current
    val view = LocalView.current
    val screenCorner = remember(view) { displayCornerRadius(view) }
    val barFill = GlassPreferences.style.fallbackFill
    val frame = remember(chrome) { ZoomFrame(chrome) }
    // Composed once per zoom. Progress is only read in layer and draw blocks, so each frame
    // updates a few layer properties instead of recomposing or re-measuring the card.
    androidx.compose.foundation.layout.BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .pointerInput(Unit) { awaitEachGesture { awaitFirstDown().consume() } },
    ) {
        val width = constraints.maxWidth.toFloat()
        val height = constraints.maxHeight.toFloat()
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = zoom.alpha.value * 0.45f * frame.progress }
                .background(Color.Black),
        )
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    val card = frame.card(width, height)
                    val radius = lerp(card.height.coerceAtMost(frame.bar.height) / 2f, screenCorner, frame.progress)
                    shape = ZoomCardShape(card, radius.coerceAtLeast(0f))
                    clip = true
                    alpha = zoom.alpha.value
                }
                .drawBehind { drawRect(lerp(barFill, Color.Black, (frame.progress * 2f).coerceAtMost(1f))) },
        ) {
            // Scaled to fill the card like the destination of an iOS zoom transition. Opening shows the
            // player's loading spinner; closing shows the artwork shrinking back, so the fold-away reads
            // as the title collapsing into the mini player instead of a black card vanishing.
            Box(
                Modifier
                    .fillMaxSize()
                    .graphicsLayer {
                        val card = frame.card(width, height)
                        val scale = maxOf(card.width / width, card.height / height)
                        translationX = card.center.x - width / 2f
                        translationY = card.center.y - height / 2f
                        scaleX = scale
                        scaleY = scale
                        alpha = 1f - frame.barAlpha
                    },
                contentAlignment = Alignment.Center,
            ) {
                if (zoom.startsFull && item != null) {
                    AsyncImage(
                        model = artwork(item, session, landscape = false),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize().background(Color.Black),
                    )
                } else {
                    CircularProgressIndicator(color = Color.White, modifier = Modifier.size(40.dp))
                }
            }
            if (item != null) {
                // The bar's own contents ride along and cross-fade out early, as the zoom source does.
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopStart) {
                    MiniPlayerRow(
                        item = item,
                        session = session,
                        collapse = chrome.miniCollapse,
                        onOpen = null,
                        modifier = Modifier
                            .requiredSize(with(density) { bar.width.toDp() }, with(density) { bar.height.toDp() })
                            .graphicsLayer {
                                val card = frame.card(width, height)
                                transformOrigin = TransformOrigin(0f, 0f)
                                translationX = card.left
                                translationY = card.top
                                scaleX = card.width / frame.bar.width
                                scaleY = scaleX
                                alpha = frame.barAlpha
                            },
                    )
                }
            }
        }
    }
}

/** Card geometry from the zoom progress. Reads state, so call it from layer or draw blocks. */
private class ZoomFrame(private val chrome: DockChromeState) {
    val progress: Float get() = chrome.zoom.progress.value.coerceIn(0f, 1f)
    val bar: Rect get() = chrome.miniBar
    val barAlpha: Float get() = (1f - progress * 3f).coerceIn(0f, 1f)

    fun card(width: Float, height: Float): Rect {
        val p = progress
        val from = bar
        return Rect(
            left = lerp(from.left, 0f, p),
            top = lerp(from.top, 0f, p),
            right = lerp(from.right, width, p),
            bottom = lerp(from.bottom, height, p),
        )
    }
}

/** A rounded rectangle at [card], for clipping a full-screen layer to the moving frame. */
private class ZoomCardShape(private val card: Rect, private val radius: Float) : Shape {
    override fun createOutline(size: Size, layoutDirection: LayoutDirection, density: Density): Outline =
        Outline.Rounded(RoundRect(card, CornerRadius(radius)))
}

/** The screen's own corner radius (Android 12+), so the card lands flush with the display. */
private fun displayCornerRadius(view: View): Float {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return 0f
    val corner = view.rootWindowInsets?.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT) ?: return 0f
    return corner.radius.toFloat()
}
