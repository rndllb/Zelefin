package app.zelefin.client.ui

import android.os.SystemClock
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import app.zelefin.client.LiveAdaptiveAction
import app.zelefin.client.LiveAdaptiveSample
import app.zelefin.client.LiveAdaptiveTracker
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.PlaybackQuality
import app.zelefin.core.PlaybackPlan
import kotlinx.coroutines.delay

/**
 * Mirrors iOS `PlayerView.monitorLiveAdaptive`: once a second, step the stream down after
 * sustained rebuffering or up after a long healthy buffer. [onStep] receives the new cap in
 * bits per second and the current media position; the caller re-requests the stream.
 */
@Composable
internal fun LiveAdaptiveMonitor(
    player: ExoPlayer,
    plan: PlaybackPlan,
    mediaSeconds: () -> Double,
    onStep: ((Int, Double) -> Unit)?,
) {
    val applied = plan.appliedBitrate
    if (onStep == null || plan.streamUrl.startsWith("file:") || applied == null) return
    val context = LocalContext.current
    val currentOnStep by rememberUpdatedState(onStep)
    val signals = remember(player) { AdaptiveSignals() }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() {
                signals.hasFirstFrame = true
            }

            override fun onPositionDiscontinuity(oldPosition: Player.PositionInfo, newPosition: Player.PositionInfo, reason: Int) {
                if (reason == Player.DISCONTINUITY_REASON_SEEK || reason == Player.DISCONTINUITY_REASON_SEEK_ADJUSTMENT) {
                    signals.lastSeekAt = SystemClock.elapsedRealtime()
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    LaunchedEffect(player) {
        val tracker = LiveAdaptiveTracker()
        while (true) {
            delay(1_000)
            if (!PlaybackPreferences.adaptiveBitrate(context)) continue
            val ceiling = PlaybackPreferences.selectedQuality(context)
            val current = PlaybackQuality.atOrBelow(applied)
            val now = SystemClock.elapsedRealtime()
            val seeking = now - signals.lastSeekAt < SEEK_SETTLE_MILLIS && player.playbackState == Player.STATE_BUFFERING
            val sample = LiveAdaptiveSample(
                hasFirstFrame = signals.hasFirstFrame,
                isPaused = !player.playWhenReady,
                isSeeking = seeking,
                isRebuffering = player.playbackState == Player.STATE_BUFFERING && player.playWhenReady,
                bufferedAheadSeconds = ((player.bufferedPosition - player.currentPosition).coerceAtLeast(0L)) / 1000.0,
                current = current,
                ceiling = ceiling,
                sourceBitsPerSecond = plan.sourceBitrate,
            )
            val next = when (tracker.action(now, sample)) {
                LiveAdaptiveAction.None -> null
                LiveAdaptiveAction.StepDown -> PlaybackQuality.stepDown(current, plan.sourceBitrate)
                LiveAdaptiveAction.StepUp -> PlaybackQuality.stepUp(current, plan.sourceBitrate, ceiling)
            }
            if (next != null) {
                currentOnStep(next.bitsPerSecond, mediaSeconds())
                return@LaunchedEffect
            }
        }
    }
}

private class AdaptiveSignals {
    @Volatile var hasFirstFrame = false
    @Volatile var lastSeekAt = 0L
}

private const val SEEK_SETTLE_MILLIS = 3_000L
