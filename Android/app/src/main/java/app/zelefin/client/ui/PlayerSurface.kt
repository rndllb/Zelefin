package app.zelefin.client.ui

import android.view.ViewGroup
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem as ExoItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import app.zelefin.client.plugins.SkipPrompt
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackResumePolicy
import kotlinx.coroutines.delay

@OptIn(UnstableApi::class)
@Composable
fun PlayerSurface(
    plan: PlaybackPlan,
    onProgress: (Double, Boolean) -> Unit,
    onStopped: (Double) -> Unit,
    skipSegments: List<SkipSegment> = emptyList(),
    autoSkip: (SkipSegment.Kind) -> Boolean = { false },
) {
    val context = LocalContext.current
    val clientStart = remember(plan.streamUrl) {
        PlaybackResumePolicy.clientStartPosition(plan.method, plan.startTimeSeconds, plan.clientOwnsPlayhead)
    }
    // A server-owned transcode starts its stream at the resume point, so stream time 0 is media time startTimeSeconds.
    val streamOffset = if (clientStart == null) plan.startTimeSeconds else 0.0
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
                if (clientStart != null) seekTo((clientStart * 1000).toLong())
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

    var prompt by remember(player) { mutableStateOf<SkipPrompt?>(null) }
    var controlsVisible by remember(player) { mutableStateOf(true) }
    val currentAutoSkip by rememberUpdatedState(autoSkip)
    val skip: (SkipPrompt) -> Unit = { target ->
        val streamSeconds = (target.seekTo - streamOffset).coerceAtLeast(0.0)
        player.seekTo((streamSeconds * 1000).toLong())
        prompt = SkipSegment.prompt(skipSegments, target.seekTo + 0.05)
    }
    LaunchedEffect(player, skipSegments) {
        if (skipSegments.isEmpty()) {
            prompt = null
            return@LaunchedEffect
        }
        while (true) {
            val media = player.currentPosition / 1000.0 + streamOffset
            val next = SkipSegment.prompt(skipSegments, media)
            prompt = next
            if (next != null && player.playbackState == Player.STATE_READY && currentAutoSkip(next.kind)) skip(next)
            delay(250)
        }
    }

    Box(Modifier.fillMaxSize()) {
        AndroidView(
            factory = { viewContext ->
                PlayerView(viewContext).apply {
                    this.player = player
                    useController = true
                    setControllerVisibilityListener(
                        PlayerView.ControllerVisibilityListener { visibility -> controlsVisible = visibility == android.view.View.VISIBLE },
                    )
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                }
            },
            modifier = Modifier.fillMaxSize(),
        )
        val lift by animateDpAsState(if (controlsVisible) 84.dp else 18.dp, label = "skip-lift")
        AnimatedVisibility(
            visible = prompt != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .navigationBarsPadding()
                .padding(end = 20.dp, bottom = lift),
        ) {
            val shape = RoundedCornerShape(50)
            Text(
                prompt?.title.orEmpty(),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                modifier = Modifier
                    .clip(shape)
                    .background(Color.Black.copy(alpha = 0.55f), shape)
                    .border(0.5.dp, Color.White.copy(alpha = 0.22f), shape)
                    .clickable { prompt?.let(skip) }
                    .padding(horizontal = 16.dp, vertical = 9.dp),
            )
        }
    }
}
