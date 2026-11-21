package app.zelefin.client.ui

import app.zelefin.client.R
import androidx.compose.ui.res.stringResource
import android.app.Activity
import android.content.Context
import android.media.AudioManager
import android.os.SystemClock
import android.provider.Settings
import android.view.HapticFeedbackConstants
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.VolumeDown
import androidx.compose.material.icons.automirrored.rounded.VolumeMute
import androidx.compose.material.icons.automirrored.rounded.VolumeOff
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material.icons.rounded.ChevronLeft
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.LightMode
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.zelefin.client.PlaybackPreferences
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Full-screen touch layer for both players: single tap toggles chrome, double-tap skips,
 * and a vertical swipe on the left sets window brightness while the right sets device volume.
 */
@Composable
internal fun PlayerGestureOverlay(
    enabled: Boolean,
    controlsVisible: Boolean,
    onSingleTap: () -> Unit,
    onSkip: (seconds: Int) -> Unit,
    volume: Float,
    onVolume: (Float) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (!enabled) return
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val tapAction by rememberUpdatedState(onSingleTap)
    val skipAction by rememberUpdatedState(onSkip)
    val volumeAction by rememberUpdatedState(onVolume)
    val volumeLevel by rememberUpdatedState(volume)
    var flash by remember { mutableStateOf<SkipFlash?>(null) }
    var flashShown by remember { mutableStateOf<SkipFlash?>(null) }
    var hud by remember { mutableStateOf<GestureHud?>(null) }
    var hudShown by remember { mutableStateOf<GestureHud?>(null) }
    var flashToken by remember { mutableIntStateOf(0) }
    var hudToken by remember { mutableIntStateOf(0) }
    val pending = remember { PendingTap() }

    LaunchedEffect(flash?.token) {
        val shown = flash ?: return@LaunchedEffect
        flashShown = shown
        delay(700)
        if (flash?.token == shown.token) flash = null
    }
    LaunchedEffect(hud?.token) {
        val shown = hud ?: return@LaunchedEffect
        hudShown = shown
        delay(800)
        if (hud?.token == shown.token) hud = null
    }
    DisposableEffect(controlsVisible) {
        onDispose { pending.clear() }
    }

    Box(modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(controlsVisible) {
                    val slop = viewConfiguration.touchSlop
                    val timeout = viewConfiguration.doubleTapTimeoutMillis
                    val bottomGuard = if (controlsVisible) 120.dp.toPx() else 0f
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val start = down.position
                        val pointer = down.id
                        var dragged = false
                        var pan: EdgePan? = null
                        var origin = 0f
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == pointer } ?: break
                            if (!change.pressed) {
                                if (!dragged && pan == null) {
                                    val now = SystemClock.uptimeMillis()
                                    val forward = start.x >= size.width / 2f
                                    val pendingOnRight = pending.x >= size.width / 2f
                                    val sameSide = pending.x >= 0f && pendingOnRight == forward
                                    if (sameSide && now - pending.at <= timeout) {
                                        pending.clear()
                                        val seconds = if (forward) {
                                            PlaybackPreferences.skipForward(context)
                                        } else {
                                            PlaybackPreferences.skipBackward(context)
                                        }
                                        skipAction(if (forward) seconds else -seconds)
                                        flashToken += 1
                                        flash = SkipFlash(forward, seconds, flashToken)
                                        view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
                                    } else {
                                        pending.clear()
                                        pending.x = start.x
                                        pending.at = now
                                        pending.job = scope.launch {
                                            delay(timeout)
                                            tapAction()
                                            pending.x = -1f
                                        }
                                    }
                                }
                                break
                            }
                            val deltaX = change.position.x - start.x
                            val deltaY = change.position.y - start.y
                            if (!dragged && (abs(deltaX) > slop || abs(deltaY) > slop)) {
                                dragged = true
                                pending.clear()
                            }
                            if (dragged && pan == null) {
                                val mostlyHorizontal = abs(deltaX) > abs(deltaY) * 1.2f
                                val inBottomChrome = start.y > size.height - bottomGuard
                                if (!mostlyHorizontal && !inBottomChrome && abs(deltaY) > slop) {
                                    val brightness = start.x < size.width / 2f
                                    origin = if (brightness) {
                                        activity?.playerBrightness() ?: 0.5f
                                    } else {
                                        activity?.musicVolumeFraction() ?: volumeLevel
                                    }
                                    pan = if (brightness) EdgePan.Brightness else EdgePan.Volume
                                }
                            }
                            val active = pan
                            if (active != null) {
                                change.consume()
                                val travel = -(change.position.y - start.y) / size.height.coerceAtLeast(1).toFloat()
                                val next = (origin + travel).coerceIn(0f, 1f)
                                when (active) {
                                    EdgePan.Brightness -> activity?.setPlayerBrightness(next)
                                    EdgePan.Volume -> {
                                        activity?.setMusicVolumeFraction(next)
                                        volumeAction(next)
                                    }
                                }
                                hudToken += 1
                                hud = GestureHud(active == EdgePan.Brightness, next, hudToken)
                            }
                        }
                    }
                },
        )
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val flashEdge = (maxWidth * 0.06f).coerceAtLeast(36.dp)
            val hudEdge = (maxWidth * 0.04f).coerceAtLeast(20.dp)
            AnimatedVisibility(
                visible = flash != null,
                enter = fadeIn(tween(120)),
                exit = fadeOut(tween(200)),
                modifier = Modifier.fillMaxSize(),
            ) {
                flashShown?.let { badge ->
                    SkipFlashBadge(badge, Modifier.padding(horizontal = flashEdge))
                }
            }
            AnimatedVisibility(
                visible = hud != null,
                enter = fadeIn(tween(100)),
                exit = fadeOut(tween(200)),
                modifier = Modifier.fillMaxSize(),
            ) {
                hudShown?.let { level ->
                    GestureHudBadge(
                        level,
                        Modifier
                            .padding(horizontal = hudEdge)
                            .offset(y = if (controlsVisible) (-28).dp else 0.dp),
                    )
                }
            }
        }
    }
}

@Composable
internal fun StillWatchingOverlay(onContinue: () -> Unit, onStop: () -> Unit) {
    val episodes = PlaybackPreferences.STILL_WATCHING_THRESHOLD
    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {},
        contentAlignment = Alignment.Center,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 32.dp)
                .widthIn(max = 440.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                stringResource(R.string.player_still_watching),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 22.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                "You’ve auto-played $episodes episodes.",
                color = Color.White.copy(alpha = 0.72f),
                fontFamily = ZelefinFont,
                fontSize = 15.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(20.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                StillWatchingButton("Stop", filled = false, onClick = onStop, modifier = Modifier.weight(1f))
                StillWatchingButton("Continue", filled = true, onClick = onContinue, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun StillWatchingButton(title: String, filled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Text(
        title,
        color = if (filled) Color.Black else Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 16.sp,
        textAlign = TextAlign.Center,
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(if (filled) Color.White else Color.White.copy(alpha = 0.14f))
            .clickable(onClick = onClick)
            .padding(vertical = 14.dp),
    )
}

/** Side skip cue: `+N` / `-N` with a chevron — no wash circle. */
@Composable
private fun SkipFlashBadge(flash: SkipFlash, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        val edgeInset = (maxWidth * 0.12f).coerceAtLeast(48.dp)
        val label = if (flash.forward) "+${flash.seconds}" else "-${flash.seconds}"
        Box(
            Modifier
                .fillMaxSize()
                .padding(horizontal = edgeInset),
            contentAlignment = if (flash.forward) Alignment.CenterEnd else Alignment.CenterStart,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                if (!flash.forward) {
                    Icon(
                        Icons.Rounded.ChevronLeft,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier
                            .size(18.dp)
                            .shadow(3.dp),
                    )
                }
                Text(
                    label,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 22.sp,
                    modifier = Modifier.shadow(3.dp),
                )
                if (flash.forward) {
                    Icon(
                        Icons.Rounded.ChevronRight,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier
                            .size(18.dp)
                            .shadow(3.dp),
                    )
                }
            }
        }
    }
}

/** Borderless vertical icon + fill bar (no chrome plate). */
@Composable
private fun GestureHudBadge(hud: GestureHud, modifier: Modifier = Modifier) {
    Box(
        modifier.fillMaxSize(),
        contentAlignment = if (hud.brightness) Alignment.CenterStart else Alignment.CenterEnd,
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                when {
                    hud.brightness -> Icons.Rounded.LightMode
                    hud.value <= 0.001f -> Icons.AutoMirrored.Rounded.VolumeOff
                    hud.value < 0.34f -> Icons.AutoMirrored.Rounded.VolumeMute
                    hud.value < 0.67f -> Icons.AutoMirrored.Rounded.VolumeDown
                    else -> Icons.AutoMirrored.Rounded.VolumeUp
                },
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier
                    .size(26.dp)
                    .shadow(3.dp),
            )
            Box(
                Modifier
                    .width(4.dp)
                    .height(120.dp)
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.28f))
                    .shadow(2.dp),
                contentAlignment = Alignment.BottomCenter,
            ) {
                Box(
                    Modifier
                        .fillMaxWidth()
                        .fillMaxHeight(hud.value.coerceIn(0f, 1f))
                        .background(Color.White),
                )
            }
        }
    }
}

private enum class EdgePan { Brightness, Volume }

private data class SkipFlash(val forward: Boolean, val seconds: Int, val token: Int)

private data class GestureHud(val brightness: Boolean, val value: Float, val token: Int)

private class PendingTap {
    var job: Job? = null
    var x: Float = -1f
    var at: Long = 0L

    fun clear() {
        job?.cancel()
        job = null
        x = -1f
    }
}

private fun Activity.playerBrightness(): Float {
    val current = window.attributes.screenBrightness
    if (current in 0f..1f) return current
    val raw = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, -1)
    if (raw < 0) return 0.5f
    return (raw / 255f).coerceIn(0f, 1f)
}

private fun Activity.setPlayerBrightness(level: Float) {
    val attrs = window.attributes
    attrs.screenBrightness = level.coerceIn(0.01f, 1f)
    window.attributes = attrs
}

/** Device media volume as 0–1 (STREAM_MUSIC). */
internal fun Activity.musicVolumeFraction(): Float {
    volumeControlStream = AudioManager.STREAM_MUSIC
    val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
    return am.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / max
}

/** Sets device media volume without showing the system volume panel (we draw our own HUD). */
internal fun Activity.setMusicVolumeFraction(level: Float) {
    volumeControlStream = AudioManager.STREAM_MUSIC
    val am = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC).coerceAtLeast(1)
    val index = (level.coerceIn(0f, 1f) * max).roundToInt().coerceIn(0, max)
    // FLAG_SHOW_UI = 0 keeps our gesture HUD as the only feedback.
    @Suppress("DEPRECATION")
    am.setStreamVolume(AudioManager.STREAM_MUSIC, index, 0)
}
