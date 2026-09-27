package app.zelefin.client.ui

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer

enum class ZelefinPushRelation { None, Push, Pop }

@Stable
class ZelefinPushMotion<T>(initial: T) {
    var base by mutableStateOf(initial)
    var cover by mutableStateOf<T?>(null)
    var settled: T = initial
    var progress by mutableFloatStateOf(0f)
}

@Composable
fun <T> rememberZelefinPush(
    target: T,
    relation: (from: T, to: T) -> ZelefinPushRelation,
): ZelefinPushMotion<T> {
    val motion = remember { ZelefinPushMotion(target) }
    LaunchedEffect(target) {
        val from = motion.settled
        val kind = if (from == target) ZelefinPushRelation.None else relation(from, target)
        when (kind) {
            ZelefinPushRelation.None -> {
                motion.cover = null
                motion.base = target
                motion.progress = 0f
                motion.settled = target
            }
            ZelefinPushRelation.Push -> {
                motion.base = from
                motion.cover = target
                motion.progress = 0f
                animate(0f, 1f, animationSpec = PushSpec) { value, _ -> motion.progress = value }
                motion.base = target
                motion.cover = null
                motion.progress = 0f
                motion.settled = target
            }
            ZelefinPushRelation.Pop -> {
                motion.progress = 1f
                motion.base = target
                motion.cover = from
                animate(1f, 0f, animationSpec = PushSpec) { value, _ -> motion.progress = value }
                motion.cover = null
                motion.base = target
                motion.progress = 0f
                motion.settled = target
            }
        }
    }
    return motion
}

@Composable
fun <T> ZelefinPush(
    motion: ZelefinPushMotion<T>,
    modifier: Modifier = Modifier,
    content: @Composable (T) -> Unit,
) {
    val animating = motion.cover != null
    Box(modifier.fillMaxSize().clipToBounds()) {
        Box(Modifier.zelefinPushBase(motion, animating).fillMaxSize()) {
            content(motion.base)
            if (animating) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .graphicsLayer { alpha = motion.progress.coerceIn(0f, 1f) * 0.18f }
                        .background(Color.Black),
                )
            }
        }
        motion.cover?.let { cover ->
            Box(Modifier.zelefinPushCover(motion).fillMaxSize().background(LocalZelefinCanvas.current)) {
                content(cover)
            }
        }
    }
}

fun Modifier.zelefinPushBase(motion: ZelefinPushMotion<*>, active: Boolean): Modifier =
    graphicsLayer {
        if (!active) return@graphicsLayer
        translationX = -size.width * 0.3f * motion.progress.coerceIn(0f, 1f)
    }

fun Modifier.zelefinPushCover(motion: ZelefinPushMotion<*>): Modifier =
    graphicsLayer {
        translationX = size.width * (1f - motion.progress.coerceIn(0f, 1f))
    }

private val PushSpec = tween<Float>(350, easing = CubicBezierEasing(0.32f, 0.72f, 0f, 1f))
