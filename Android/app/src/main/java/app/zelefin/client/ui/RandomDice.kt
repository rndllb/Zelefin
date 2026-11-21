package app.zelefin.client.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Job
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min

/** Lucide-style dice face (1…6), matching Jellyfin Enhanced’s random-button icons. */
@Composable
fun RandomDiceIcon(
    face: Int,
    modifier: Modifier = Modifier,
    tint: Color = Color.White,
    size: Dp = 28.dp,
    strokeWidth: Dp = 2.dp,
) {
    val pips = min(6, max(1, face))
    Canvas(modifier.size(size)) {
        val stroke = Stroke(
            width = strokeWidth.toPx(),
            cap = StrokeCap.Round,
            join = StrokeJoin.Round,
        )
        val inset = stroke.width / 2f
        val left = this.size.width * (3f / 24f) + inset
        val top = this.size.height * (3f / 24f) + inset
        val side = this.size.width * (18f / 24f) - stroke.width
        val radius = side * (2f / 18f)
        drawRoundRect(
            color = tint,
            topLeft = Offset(left, top),
            size = Size(side, side),
            cornerRadius = CornerRadius(radius, radius),
            style = stroke,
        )
        val pipRadius = max(stroke.width * 0.55f, this.size.width * 0.045f)
        for (point in pipUnits(pips)) {
            drawCircle(
                color = tint,
                radius = pipRadius,
                center = Offset(this.size.width * point.x, this.size.height * point.y),
            )
        }
    }
}

private fun pipUnits(face: Int): List<Offset> = when (face) {
    1 -> listOf(Offset(12f / 24f, 12f / 24f))
    2 -> listOf(
        Offset(15f / 24f, 9f / 24f),
        Offset(9f / 24f, 15f / 24f),
    )
    3 -> listOf(
        Offset(16f / 24f, 8f / 24f),
        Offset(12f / 24f, 12f / 24f),
        Offset(8f / 24f, 16f / 24f),
    )
    4 -> listOf(
        Offset(16f / 24f, 8f / 24f),
        Offset(8f / 24f, 8f / 24f),
        Offset(8f / 24f, 16f / 24f),
        Offset(16f / 24f, 16f / 24f),
    )
    5 -> listOf(
        Offset(16f / 24f, 8f / 24f),
        Offset(8f / 24f, 8f / 24f),
        Offset(8f / 24f, 16f / 24f),
        Offset(16f / 24f, 16f / 24f),
        Offset(12f / 24f, 12f / 24f),
    )
    else -> listOf(
        Offset(16f / 24f, 8f / 24f),
        Offset(16f / 24f, 12f / 24f),
        Offset(16f / 24f, 16f / 24f),
        Offset(8f / 24f, 8f / 24f),
        Offset(8f / 24f, 12f / 24f),
        Offset(8f / 24f, 16f / 24f),
    )
}

fun nextDiceFace(excluding: Int): Int {
    val options = (1..6).filter { it != excluding }
    return options.randomOrNull() ?: excluding
}

/**
 * Jellyfin Enhanced `dice` keyframes: wobble then a full spin, 0.6s linear loop while loading.
 */
fun diceSpinSample(phase: Float): Pair<Float, Float> {
    val keys = listOf(
        floatArrayOf(0f, 0f, 1f),
        floatArrayOf(0.1f, -10f, 1.1f),
        floatArrayOf(0.2f, 10f, 1.1f),
        floatArrayOf(0.3f, -10f, 1.1f),
        floatArrayOf(0.4f, 10f, 1.1f),
        floatArrayOf(0.5f, -10f, 1.1f),
        floatArrayOf(0.6f, 360f, 1f),
        floatArrayOf(1f, 0f, 1f),
    )
    val t = phase.coerceIn(0f, 1f)
    for (i in 0 until keys.lastIndex) {
        val a = keys[i]
        val b = keys[i + 1]
        if (t <= b[0] || i == keys.lastIndex - 1) {
            val span = max(b[0] - a[0], 0.0001f)
            val u = ((t - a[0]) / span).coerceIn(0f, 1f)
            return a[1] + (b[1] - a[1]) * u to a[2] + (b[2] - a[2]) * u
        }
    }
    return 0f to 1f
}

/**
 * Face swaps every 120ms while [runWhile] awaits the pick, then settles for 500ms
 * like Jellyfin Enhanced’s random button.
 */
class RandomDiceRollState {
    var face by mutableIntStateOf(5)
        private set
    var rolling by mutableStateOf(false)
        private set

    suspend fun runWhile(block: suspend () -> Unit) {
        if (rolling) return
        rolling = true
        coroutineScope {
            val job = launch {
                while (isActive) {
                    delay(120)
                    face = nextDiceFace(excluding = face)
                }
            }
            try {
                block()
            } finally {
                job.cancel()
            }
        }
        delay(500)
        face = nextDiceFace(excluding = face)
        rolling = false
    }
}

@Composable
fun rememberRandomDiceRollState(): RandomDiceRollState = remember { RandomDiceRollState() }

@Composable
fun RandomDiceFace(
    state: RandomDiceRollState,
    modifier: Modifier = Modifier,
    tint: Color = MaterialTheme.colorScheme.onSurface,
) {
    var phase by remember { mutableFloatStateOf(0f) }
    LaunchedEffect(state.rolling) {
        if (!state.rolling) {
            phase = 0f
            return@LaunchedEffect
        }
        while (true) {
            withFrameMillis { frameTime ->
                phase = (frameTime % 600L) / 600f
            }
        }
    }
    val (rotation, scale) = if (state.rolling) diceSpinSample(phase) else 0f to 1f
    RandomDiceIcon(
        face = state.face,
        tint = tint,
        modifier = modifier.graphicsLayer {
            rotationZ = rotation
            scaleX = scale
            scaleY = scale
        },
    )
}

@Composable
fun Modifier.zelefinRandomDiceDisc(
    key: Any,
    description: String,
    onPick: suspend () -> Unit,
): Modifier {
    val state = rememberRandomDiceRollState()
    val scope = rememberCoroutineScope()
    val pick = rememberUpdatedState(onPick)
    var job by remember { mutableStateOf<Job?>(null) }
    return zelefinGlassFaceDisc(
        key = key,
        description = description,
        onClick = {
            if (state.rolling || job?.isActive == true) return@zelefinGlassFaceDisc
            job = scope.launch {
                state.runWhile { pick.value() }
            }
        },
    ) {
        RandomDiceFace(state)
    }
}
