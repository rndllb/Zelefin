package app.zelefin.client.ui

import android.content.Context
import android.view.LayoutInflater
import androidx.annotation.OptIn
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.PlayerView
import app.zelefin.client.R
import app.zelefin.client.ThemeMedia
import app.zelefin.client.ZelefinModel
import app.zelefin.client.network.GatewayHttp
import kotlinx.coroutines.delay

/**
 * A title page's Jellyfin theme video, looping and muted unless Theme Video Sound is on, or else its
 * theme song (the model never hands over both). Neither takes audio focus from other apps.
 */
@Stable
internal class ThemeMediaPlayers(context: Context, media: ThemeMedia) {
    val song: ExoPlayer? = media.songUrl?.let { url ->
        player(context).apply {
            volume = 0f
            setMediaItem(MediaItem.fromUri(url))
            prepare()
            playWhenReady = true
        }
    }
    val video: ExoPlayer? = media.videoUrl?.let { url ->
        player(context).apply {
            volume = 0f
            repeatMode = Player.REPEAT_MODE_ONE
            setMediaItem(MediaItem.fromUri(url))
            prepare()
            playWhenReady = true
        }
    }
    /** Whichever player is heard, faded in when the page opens. */
    val sound: ExoPlayer? = song ?: video?.takeIf { media.videoSound }
    var videoShowing by mutableStateOf(false)
        private set

    init {
        video?.addListener(object : Player.Listener {
            override fun onRenderedFirstFrame() {
                videoShowing = true
            }
        })
    }

    fun pause() {
        song?.pause()
        video?.pause()
    }

    fun resume() {
        song?.play()
        video?.play()
    }

    fun release() {
        song?.release()
        video?.release()
    }

    private companion object {
        @OptIn(UnstableApi::class)
        fun player(context: Context): ExoPlayer = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(OkHttpDataSource.Factory(GatewayHttp.playback)))
            .setAudioAttributes(
                AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MUSIC).build(),
                false,
            )
            .build()
    }
}

/**
 * Loads and plays the title's theme media while the page is on screen. Paused in the background,
 * released when the page leaves, and nothing at all unless a switch in Settings → Playback is on.
 */
@Composable
internal fun rememberThemeMedia(itemId: String?): ThemeMediaPlayers? {
    val model: ZelefinModel = viewModel()
    val context = LocalContext.current
    var media by remember(itemId) { mutableStateOf<ThemeMedia?>(null) }
    LaunchedEffect(itemId) {
        media = itemId?.let { model.themeMedia(it) }
    }
    val players = remember(media) { media?.let { ThemeMediaPlayers(context.applicationContext, it) } }
    DisposableEffect(players) {
        onDispose { players?.release() }
    }
    LaunchedEffect(players) {
        val sound = players?.sound ?: return@LaunchedEffect
        repeat(20) { step ->
            delay(60)
            sound.volume = (step + 1) / 20f
        }
    }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    DisposableEffect(lifecycle, players) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> players?.pause()
                Lifecycle.Event.ON_START -> players?.resume()
                else -> Unit
            }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    return players
}

/** The theme video filling the hero, faded in on its first frame so the backdrop shows until then. */
@OptIn(UnstableApi::class)
@Composable
internal fun ThemeVideoBackdrop(players: ThemeMediaPlayers, modifier: Modifier = Modifier) {
    val video = players.video ?: return
    val alpha by animateFloatAsState(if (players.videoShowing) 1f else 0f, tween(600), label = "themeVideo")
    AndroidView(
        factory = { context ->
            (LayoutInflater.from(context).inflate(R.layout.zelefin_player_view_texture, null) as PlayerView).apply {
                keepScreenOn = false
                resizeMode = AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                setShutterBackgroundColor(android.graphics.Color.TRANSPARENT)
                player = video
            }
        },
        update = { view -> if (view.player !== video) view.player = video },
        onRelease = { view -> view.player = null },
        modifier = modifier.alpha(alpha),
    )
}
