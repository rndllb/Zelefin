package app.zelefin.client.ui

import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem as ExoItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackResumePolicy
import kotlinx.coroutines.delay

@OptIn(UnstableApi::class)
@Composable
fun PlayerSurface(plan: PlaybackPlan, onProgress: (Double, Boolean) -> Unit, onStopped: (Double) -> Unit) {
    val context = LocalContext.current
    val player = remember(plan.streamUrl) {
        val dataSource = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(plan.headers)
            .setAllowCrossProtocolRedirects(true)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(dataSource))
            .build()
            .apply {
                setMediaItem(ExoItem.fromUri(plan.streamUrl))
                prepare()
                val start = PlaybackResumePolicy.clientStartPosition(plan.method, plan.startTimeSeconds, plan.clientOwnsPlayhead)
                if (start != null) seekTo((start * 1000).toLong())
                playWhenReady = true
            }
    }
    DisposableEffect(player) {
        onDispose {
            val seconds = player.currentPosition / 1000.0
            player.release()
            onStopped(seconds)
        }
    }
    LaunchedEffect(player) {
        while (true) {
            delay(5_000)
            if (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING) {
                onProgress(player.currentPosition / 1000.0, !player.isPlaying)
            }
        }
    }
    AndroidView(
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                this.player = player
                useController = true
                layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
            }
        },
        modifier = androidx.compose.ui.Modifier.fillMaxSize(),
    )
}
