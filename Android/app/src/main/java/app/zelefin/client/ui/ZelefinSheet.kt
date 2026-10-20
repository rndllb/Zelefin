package app.zelefin.client.ui

import androidx.compose.material3.MaterialTheme

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.AnimationVector1D
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.dp

val LocalZelefinInSheet = compositionLocalOf { false }

@Stable
class ZelefinSheetMotion<T>(
    initial: T?,
    val progress: Animatable<Float, AnimationVector1D>,
) {
    var displayed by mutableStateOf(initial)
}

@Composable
fun <T> rememberZelefinSheet(target: T?): ZelefinSheetMotion<T> {
    val progress = remember { Animatable(if (target != null) 1f else 0f) }
    val motion = remember { ZelefinSheetMotion(target, progress) }
    if (target != null) motion.displayed = target
    LaunchedEffect(target) {
        progress.animateTo(if (target != null) 1f else 0f, SheetSpring)
        if (target == null) motion.displayed = null
    }
    return motion
}

suspend fun ZelefinSheetMotion<*>.followPredictiveDismiss(gestureProgress: Float) {
    progress.snapTo((1f - gestureProgress).coerceIn(0f, 1f))
}

suspend fun ZelefinSheetMotion<*>.finishPredictiveDismiss() {
    progress.animateTo(0f, SheetSpring)
}

suspend fun ZelefinSheetMotion<*>.cancelPredictiveDismiss() {
    progress.animateTo(1f, SheetSpring)
}

fun Modifier.zelefinSheetBackdrop(progress: Animatable<Float, AnimationVector1D>): Modifier =
    graphicsLayer {
        val amount = progress.value.coerceIn(0f, 1f)
        val scale = 1f - 0.08f * amount
        scaleX = scale
        scaleY = scale
        shape = RoundedCornerShape((40f * amount).dp)
        clip = amount > 0.001f
    }

fun Modifier.zelefinSheetRise(progress: Animatable<Float, AnimationVector1D>): Modifier =
    graphicsLayer {
        val amount = progress.value.coerceIn(0f, 1f)
        translationY = size.height * (1f - amount)
    }

@Composable
fun ZelefinSheetSurface(
    progress: Animatable<Float, AnimationVector1D>,
    canvas: Color = MaterialTheme.colorScheme.surface,
    content: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxSize().zelefinSheetRise(progress)) {
        Spacer(Modifier.statusBarsPadding().height(12.dp))
        Box(
            Modifier
                .weight(1f)
                .fillMaxWidth()
                .clip(RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp))
                .background(canvas),
        ) {
            CompositionLocalProvider(LocalZelefinCanvas provides canvas) {
                content()
            }
        }
    }
}

@Composable
fun ZelefinSheetScrim(progress: Animatable<Float, AnimationVector1D>) {
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = progress.value.coerceIn(0f, 1f) * 0.28f }
            .background(Color.Black),
    )
}

private val SheetSpring = spring<Float>(dampingRatio = 0.9f, stiffness = 320f)
