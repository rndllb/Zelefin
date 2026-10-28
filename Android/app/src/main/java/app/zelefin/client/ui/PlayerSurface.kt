package app.zelefin.client.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.util.Rational
import android.view.LayoutInflater
import android.view.ViewGroup
import androidx.activity.compose.BackHandler
import androidx.annotation.OptIn
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredHeight
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.FormatListBulleted
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AddComment
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.CloseFullscreen
import androidx.compose.material.icons.rounded.Info
import androidx.compose.material.icons.rounded.OpenInFull
import app.zelefin.core.PlaybackChapter
import androidx.compose.material.icons.rounded.ClosedCaption
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Forward10
import androidx.compose.material.icons.rounded.Forward30
import androidx.compose.material.icons.rounded.Forward5
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PictureInPictureAlt
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Replay
import androidx.compose.material.icons.rounded.Replay10
import androidx.compose.material.icons.rounded.Replay30
import androidx.compose.material.icons.rounded.Replay5
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Sync
import androidx.compose.material.icons.rounded.TextFields
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem as ExoItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.Tracks
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import app.zelefin.client.PlaybackLanguage
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.TrackPick
import app.zelefin.client.PlayerDirective
import app.zelefin.client.R
import app.zelefin.client.SubtitleAppearance
import app.zelefin.client.network.GatewayHttp
import app.zelefin.client.plugins.SkipPrompt
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.VideoRange
import app.zelefin.core.PlaybackResumePolicy
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow

private const val ChromeIdleMillis = 3_000L
private const val UpNextWindowSeconds = 30.0
private const val UpNextOutroCountdown = 10.0
private const val UpNextMinimumRuntime = 60.0

internal enum class PlayerMenuPage(val title: String) {
    Root("More"),
    Speed("Playback Speed"),
    Audio("Select Audio"),
    Subtitles("Select Subtitles"),
    SubtitleStyle("Subtitle Style"),
    SubtitleSync("Subtitle Sync"),
    Chapters("Chapters"),
    Sleep("Sleep Timer"),
}

internal data class OverlayTrack(
    val key: String,
    val title: String,
    val selected: Boolean,
    val language: String? = null,
    /** PGS, VobSub and DVB subtitles are pictures, which only the size setting changes. */
    val isPicture: Boolean = false,
)

private class PlayerTrack(val title: String, val group: Tracks.Group, val index: Int, val selected: Boolean) {
    fun overlay(): OverlayTrack = OverlayTrack(
        "${System.identityHashCode(group)}:$index",
        title,
        selected,
        isPicture = SubtitleAppearance.isPictureCodec(group.getTrackFormat(index).sampleMimeType),
    )
}

@OptIn(UnstableApi::class)
@Composable
fun PlayerSurface(
    plan: PlaybackPlan,
    session: app.zelefin.core.SavedSession? = null,
    onProgress: (Double, Boolean) -> Unit,
    onStopped: (Double) -> Unit,
    onClose: () -> Unit,
    skipSegments: List<SkipSegment> = emptyList(),
    autoSkip: (SkipSegment.Kind) -> Boolean = { false },
    nextEpisode: MediaItem? = null,
    nextArtwork: List<String> = emptyList(),
    onPlayNext: (MediaItem, Double) -> Unit = { _, _ -> },
    onAddSubtitles: ((Double) -> Unit)? = null,
    suspended: Boolean = false,
    onAdaptiveBitrate: ((Int, Double) -> Unit)? = null,
    onRecover: ((Double) -> Unit)? = null,
    onRetryStream: ((Double) -> Unit)? = null,
    onPlaybackReady: () -> Unit = {},
    onUserTransport: (PlayerDirective) -> Unit = {},
    onTrackPicked: (TrackPick) -> Unit = {},
    directives: SharedFlow<PlayerDirective>? = null,
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val castConnected = app.zelefin.client.cast.rememberCastConnected()
    if (castConnected) {
        app.zelefin.client.cast.CastRemoteSurface(
            plan = plan,
            artworkUrl = plan.item.backdropUrl ?: plan.item.posterUrl,
            onClose = onClose,
        )
        return
    }
    if (PlaybackPreferences.usesMpv(context)) {
        MpvPlayerSurface(
            plan = plan,
            session = session,
            onProgress = onProgress,
            onStopped = onStopped,
            onClose = onClose,
            onCast = {},
            skipSegments = skipSegments,
            autoSkip = autoSkip,
            nextEpisode = nextEpisode,
            nextArtwork = nextArtwork,
            onPlayNext = onPlayNext,
            onAddSubtitles = onAddSubtitles,
            suspended = suspended,
            onPlaybackReady = onPlaybackReady,
            onUserTransport = onUserTransport,
            onTrackPicked = onTrackPicked,
            directives = directives,
        )
        return
    }
    val clientStart = remember(plan.streamUrl) {
        PlaybackResumePolicy.clientStartPosition(plan.method, plan.startTimeSeconds, plan.clientOwnsPlayhead)
    }
    val bif = rememberBifPreviews(plan)
    // A server-owned transcode starts its stream at the resume point, so stream time 0 is media time startTimeSeconds.
    val streamOffset = if (clientStart == null) plan.startTimeSeconds else 0.0
    val player = remember(plan.streamUrl) {
        // GatewayHttp retries a dead socket and sends each request to whichever address is
        // answering. HttpURLConnection kept the dead one until the process was killed.
        val http = OkHttpDataSource.Factory(GatewayHttp.playback)
            .setDefaultRequestProperties(plan.headers)
        ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(DefaultDataSource.Factory(context, http)))
            .build()
            .apply {
                trackSelectionParameters = preferredLanguages(context, trackSelectionParameters)
                setPlaybackSpeed(PlaybackPreferences.defaultRate(context))
                val subtitles = plan.externalSubtitles.map { subtitle ->
                    ExoItem.SubtitleConfiguration.Builder(android.net.Uri.parse(subtitle.url))
                        .setMimeType(subtitle.mimeType)
                        .setLanguage(subtitle.language)
                        .setLabel(subtitle.title)
                        .apply { subtitle.id?.let(::setId) }
                        .build()
                }
                setMediaItem(ExoItem.Builder().setUri(plan.streamUrl).setSubtitleConfigurations(subtitles).build())
                prepare()
                if (clientStart != null) seekTo((clientStart * 1000).toLong())
                playWhenReady = true
            }
    }
    val mediaSeconds = { player.currentPosition.coerceAtLeast(0) / 1000.0 + streamOffset }
    val currentOnProgress by rememberUpdatedState(onProgress)
    val currentOnStopped by rememberUpdatedState(onStopped)
    val currentOnClose by rememberUpdatedState(onClose)
    val currentOnRecover by rememberUpdatedState(onRecover)
    val currentOnRetryStream by rememberUpdatedState(onRetryStream)
    val currentOnPlaybackReady by rememberUpdatedState(onPlaybackReady)
    val currentOnUserTransport by rememberUpdatedState(onUserTransport)
    LiveAdaptiveMonitor(player, plan, mediaSeconds, onAdaptiveBitrate)
    DisposableEffect(player) {
        onDispose {
            val seconds = mediaSeconds()
            player.release()
            currentOnStopped(seconds)
        }
    }

    var isPlaying by remember(player) { mutableStateOf(false) }
    var playWhenReady by remember(player) { mutableStateOf(true) }
    var playbackState by remember(player) { mutableIntStateOf(Player.STATE_IDLE) }
    var tracks by remember(player) { mutableStateOf(Tracks.EMPTY) }
    var speed by remember(player) { mutableFloatStateOf(player.playbackParameters.speed) }
    var aspect by remember(player) { mutableStateOf<Rational?>(null) }
    var positionMs by remember(player) { mutableLongStateOf(0L) }
    var durationMs by remember(player) { mutableLongStateOf(C.TIME_UNSET) }
    var playbackError by remember(player) { mutableStateOf<String?>(null) }
    var recovering by remember(player) { mutableStateOf(false) }
    DisposableEffect(player) {
        var startedWithServerChoice = false
        val listener = object : Player.Listener {
            override fun onIsPlayingChanged(value: Boolean) {
                isPlaying = value
            }

            override fun onPlayerError(error: PlaybackException) {
                val recover = currentOnRecover
                if (!recovering && recover != null && isRecoverableSource(error)) {
                    recovering = true
                    recover(mediaSeconds())
                } else if (!recovering) {
                    playbackError = playbackFailureCopy(error)
                }
            }

            override fun onPlayWhenReadyChanged(value: Boolean, reason: Int) {
                playWhenReady = value
            }

            override fun onPlaybackStateChanged(state: Int) {
                playbackState = state
            }

            override fun onTracksChanged(value: Tracks) {
                tracks = value
                if (!startedWithServerChoice && value.groups.isNotEmpty()) {
                    if (applyServerTrackChoice(player, value, plan, context)) {
                        startedWithServerChoice = true
                    }
                }
            }

            override fun onPlaybackParametersChanged(parameters: PlaybackParameters) {
                speed = parameters.speed
            }

            override fun onVideoSizeChanged(size: VideoSize) {
                if (size.width > 0 && size.height > 0) {
                    aspect = Rational((size.width * size.pixelWidthHeightRatio).roundToInt().coerceAtLeast(1), size.height)
                }
            }
        }
        player.addListener(listener)
        onDispose { player.removeListener(listener) }
    }
    LaunchedEffect(tracks, activity) {
        activity?.let { PlayerWindow.setHdr(it, tracks.isHdrVideo()) }
    }
    LaunchedEffect(player) {
        while (true) {
            positionMs = player.currentPosition
            durationMs = player.duration
            delay(250)
        }
    }
    LaunchedEffect(player, recovering) {
        if (!recovering) return@LaunchedEffect
        delay(20_000)
        recovering = false
        playbackError = "The connection to the server dropped."
    }
    LaunchedEffect(player) {
        while (true) {
            delay(5_000)
            if (player.playbackState == Player.STATE_READY || player.playbackState == Player.STATE_BUFFERING) {
                currentOnProgress(mediaSeconds(), !player.isPlaying)
            }
        }
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, player) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    player.pause()
                    currentOnProgress(mediaSeconds(), true)
                }
                Lifecycle.Event.ON_RESUME -> activity?.let(PlayerWindow::reapplyImmersive)
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val windowOwner = remember(player) { Any() }
    DisposableEffect(activity, windowOwner) {
        if (activity != null) {
            // Compose is paused once the PiP window is closed, so stop here instead of waiting for disposal.
            PlayerWindow.attach(activity, windowOwner) {
                player.pause()
                currentOnStopped(mediaSeconds())
                currentOnClose()
            }
            PlayerWindow.holdImmersive(activity)
        }
        onDispose {
            if (activity != null) {
                PlayerWindow.detach(activity, windowOwner)
                PlayerWindow.releaseImmersive(activity)
            }
        }
    }
    LaunchedEffect(activity, windowOwner, aspect, playWhenReady) {
        activity?.let { PlayerWindow.update(it, windowOwner, aspect, playWhenReady) }
    }
    DisposableEffect(player) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                if (player.playWhenReady) player.pause() else player.play()
            }
        }
        ContextCompat.registerReceiver(context, receiver, IntentFilter(PlayerWindow.ACTION_TOGGLE), ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { context.unregisterReceiver(receiver) }
    }

    val mediaPosition = positionMs.coerceAtLeast(0) / 1000.0 + streamOffset
    val mediaDuration = if (durationMs != C.TIME_UNSET && durationMs > 0) {
        durationMs / 1000.0 + streamOffset
    } else {
        plan.item.runtime ?: 0.0
    }
    val seekMedia: (Double) -> Unit = { target ->
        var streamMs = ((target - streamOffset).coerceAtLeast(0.0) * 1000).toLong()
        if (durationMs != C.TIME_UNSET && durationMs > 0) streamMs = min(streamMs, durationMs)
        player.seekTo(streamMs)
        positionMs = player.currentPosition
    }
    var announcedReady by remember(player) { mutableStateOf(false) }
    LaunchedEffect(playbackState) {
        if (!announcedReady && playbackState == Player.STATE_READY) {
            announcedReady = true
            currentOnPlaybackReady()
        }
    }
    LaunchedEffect(player, directives) {
        val commands = directives ?: return@LaunchedEffect
        commands.collect { directive ->
            when (directive) {
                PlayerDirective.Play -> player.play()
                PlayerDirective.Pause -> player.pause()
                is PlayerDirective.Seek -> seekMedia(directive.seconds)
            }
        }
    }

    val prompt = SkipSegment.prompt(skipSegments, mediaPosition)
    val currentAutoSkip by rememberUpdatedState(autoSkip)
    val skip: (SkipPrompt) -> Unit = { target ->
        val time = target.seekTo + 0.05
        seekMedia(time)
        currentOnUserTransport(PlayerDirective.Seek(time))
    }
    LaunchedEffect(prompt, playbackState) {
        val active = prompt ?: return@LaunchedEffect
        if (playbackState == Player.STATE_READY && currentAutoSkip(active.kind)) skip(active)
    }

    val inPip = PlayerWindow.inPictureInPicture
    val pipSupported = remember(context) { PlayerWindow.supported(context) }
    val skipBack = remember { PlaybackPreferences.skipBackward(context) }
    val skipForward = remember { PlaybackPreferences.skipForward(context) }
    val autoplayPreference = remember { PlaybackPreferences.autoplayNext(context) }

    var chromeVisible by remember { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var locked by remember { mutableStateOf(false) }
    var timelineTop by remember { mutableStateOf<Float?>(null) }
    var surfaceTop by remember { mutableFloatStateOf(0f) }
    var lockHint by remember { mutableStateOf(false) }
    var scrubTime by remember { mutableStateOf<Double?>(null) }
    var menuPage by remember { mutableStateOf<PlayerMenuPage?>(null) }
    var playerView by remember { mutableStateOf<PlayerView?>(null) }
    var styleRevision by remember { mutableIntStateOf(0) }
    var fillsScreen by remember { mutableStateOf(false) }
    var showStats by remember { mutableStateOf(false) }
    var sleep by remember { mutableStateOf<SleepTimer>(SleepTimer.Off) }
    var sleepDeadline by remember { mutableLongStateOf(0L) }
    LaunchedEffect(fillsScreen, playerView) {
        playerView?.resizeMode = if (fillsScreen) {
            androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
        } else {
            androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
        }
    }
    LaunchedEffect(sleep) {
        val timer = sleep as? SleepTimer.Minutes ?: return@LaunchedEffect
        sleepDeadline = android.os.SystemClock.elapsedRealtime() + timer.minutes * 60_000L
        while (android.os.SystemClock.elapsedRealtime() < sleepDeadline) delay(1_000)
        player.pause()
        sleep = SleepTimer.Off
    }
    LaunchedEffect(suspended) {
        if (suspended) player.pause()
    }
    val reveal = {
        chromeVisible = true
        interaction += 1
    }
    LaunchedEffect(chromeVisible, isPlaying, scrubTime != null, menuPage, interaction) {
        if (chromeVisible && isPlaying && scrubTime == null && menuPage == null) {
            delay(ChromeIdleMillis)
            chromeVisible = false
        }
    }
    LaunchedEffect(playWhenReady) {
        if (!playWhenReady && !locked) reveal()
    }
    LaunchedEffect(lockHint, interaction) {
        if (lockHint) {
            delay(ChromeIdleMillis)
            lockHint = false
        }
    }
    LaunchedEffect(inPip) {
        if (inPip) menuPage = null
    }
    BackHandler(enabled = menuPage != null) { menuPage = null }
    BackHandler(enabled = locked && menuPage == null) {
        lockHint = true
        interaction += 1
    }

    val autoplay = autoplayPreference && sleep != SleepTimer.EndOfEpisode
    var upNextCancelled by remember { mutableStateOf(false) }
    var upNextCountdown by remember { mutableStateOf<Double?>(null) }
    var finishing by remember { mutableStateOf(false) }
    val outroStart = skipSegments.firstOrNull { it.kind == SkipSegment.Kind.Outro && it.end - it.start >= SkipSegment.MIN_LENGTH }?.start
    val remaining = (mediaDuration - mediaPosition).coerceAtLeast(0.0)
    val inOutro = outroStart != null && mediaPosition >= outroStart - 0.35
    val upNextVisible = nextEpisode != null && !upNextCancelled && mediaDuration > UpNextMinimumRuntime &&
        playbackState != Player.STATE_IDLE && scrubTime == null && (inOutro || remaining <= UpNextWindowSeconds)
    val currentOnPlayNext by rememberUpdatedState(onPlayNext)
    val advance = {
        val next = nextEpisode
        if (!finishing && next != null) {
            finishing = true
            player.pause()
            currentOnPlayNext(next, mediaSeconds())
        }
    }
    LaunchedEffect(upNextVisible, inOutro) {
        upNextCountdown = if (upNextVisible && autoplay && inOutro) min(UpNextOutroCountdown, remaining) else null
    }
    LaunchedEffect(upNextCountdown != null, isPlaying) {
        while (isPlaying && !finishing) {
            val left = upNextCountdown ?: break
            if (left <= 0.0) {
                advance()
                break
            }
            delay(250)
            upNextCountdown = upNextCountdown?.minus(0.25)
        }
    }
    LaunchedEffect(playbackState) {
        if (playbackState != Player.STATE_ENDED || finishing) return@LaunchedEffect
        if (nextEpisode != null && autoplay && !upNextCancelled) {
            advance()
        } else {
            finishing = true
            currentOnClose()
        }
    }

    val togglePlay = {
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
            player.play()
            currentOnUserTransport(PlayerDirective.Play)
        } else if (player.playWhenReady) {
            player.pause()
            currentOnUserTransport(PlayerDirective.Pause)
        } else {
            player.play()
            currentOnUserTransport(PlayerDirective.Play)
        }
        reveal()
    }
    val skipBy: (Int) -> Unit = { seconds ->
        val target = (mediaSeconds() + seconds).coerceAtLeast(streamOffset)
        seekMedia(target)
        currentOnUserTransport(PlayerDirective.Seek(target))
        reveal()
    }

    val audioTracks = remember(tracks) { playerTracks(tracks, C.TRACK_TYPE_AUDIO) }
    val subtitleTracks = remember(tracks) { playerTracks(tracks, C.TRACK_TYPE_TEXT) }
    val selectAudio: (PlayerTrack) -> Unit = { track ->
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
            .setOverrideForType(TrackSelectionOverride(track.group.mediaTrackGroup, track.index))
            .build()
        onTrackPicked(TrackPick.Audio(track.group.getTrackFormat(track.index).language))
        menuPage = null
    }
    val selectSubtitle: (PlayerTrack?) -> Unit = { track ->
        val builder = player.trackSelectionParameters.buildUpon()
        if (track == null) {
            builder.clearOverridesOfType(C.TRACK_TYPE_TEXT).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        } else {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setOverrideForType(TrackSelectionOverride(track.group.mediaTrackGroup, track.index))
        }
        player.trackSelectionParameters = builder.build()
        onTrackPicked(track?.let { TrackPick.Subtitle(it.group.getTrackFormat(it.index).language) } ?: TrackPick.SubtitlesOff)
        menuPage = null
    }
    val selectSpeed: (Float) -> Unit = { rate ->
        player.setPlaybackSpeed(rate)
        menuPage = null
    }
    val audioNote = if (plan.method == PlaybackMethod.Transcode && audioTracks.size <= 1) {
        "This stream carries the audio track the server chose."
    } else {
        null
    }

    val item = plan.item
    val title = if (item.kind == MediaKind.Episode) item.seriesName ?: item.name else item.name
    val subtitle = if (item.kind == MediaKind.Episode) episodeCaption(item, includeName = item.seriesName != null) else null
    val buffering = playbackError == null &&
        (playbackState == Player.STATE_BUFFERING || (playbackState == Player.STATE_IDLE && playWhenReady))
    val showChrome = chromeVisible && !locked && !inPip && !suspended
    val captionGap = with(LocalDensity.current) { 8.dp.toPx() }
    val subtitleCeiling = timelineTop?.takeIf { showChrome }?.let { it - surfaceTop - captionGap }

    // SDR plays on a TextureView so the liquid glass controls can refract the picture; HDR keeps the
    // SurfaceView, which no layer can sample, and its controls fall back to tinted glass.
    val videoGlass = remember { GlassSource() }
    val sampleVideo = plan.item.videoRange == VideoRange.Sdr
    CompositionLocalProvider(LocalGlassSource provides if (sampleVideo) videoGlass else null) {
    Box(Modifier.fillMaxSize().background(Color.Black).onGloballyPositioned { surfaceTop = it.positionInRoot().y }) {
        val configuration = LocalConfiguration.current
        AndroidView(
            factory = { viewContext ->
                val layout = if (sampleVideo) R.layout.zelefin_player_view_texture else R.layout.zelefin_player_view
                (LayoutInflater.from(viewContext).inflate(layout, null) as PlayerView).apply {
                    this.player = player
                    layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                    playerView = this
                }
            },
            update = { view ->
                if (view.player !== player) view.player = player
                configuration.orientation
                configuration.screenWidthDp
                configuration.screenHeightDp
                view.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
                view.resizeMode = if (fillsScreen) {
                    androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_ZOOM
                } else {
                    androidx.media3.ui.AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
                styleRevision
                aspect
                fillsScreen
                SubtitleAppearance.applyTo(view, fill = fillsScreen, controlsTop = subtitleCeiling)
                view.post {
                    view.requestLayout()
                    (view.videoSurfaceView as? android.view.SurfaceView)?.holder?.setSizeFromLayout()
                    SubtitleAppearance.applyTo(view, fill = fillsScreen, controlsTop = subtitleCeiling)
                }
            },
            modifier = if (sampleVideo) Modifier.fillMaxSize().glassSource(videoGlass) else Modifier.fillMaxSize(),
        )
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(inPip, locked, chromeVisible) {
                    detectTapGestures {
                        when {
                            inPip -> Unit
                            locked -> {
                                lockHint = !lockHint
                                interaction += 1
                            }
                            chromeVisible -> chromeVisible = false
                            else -> reveal()
                        }
                    }
                },
        )
        if ((recovering || (buffering && !showChrome)) && !inPip) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.align(Alignment.Center).size(44.dp))
        }
        AnimatedVisibility(visible = showChrome, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            PlayerChrome(
                title = title,
                subtitle = subtitle,
                playing = playWhenReady && playbackState != Player.STATE_ENDED,
                buffering = buffering,
                position = scrubTime ?: mediaPosition,
                duration = mediaDuration,
                skipBack = skipBack,
                skipForward = skipForward,
                pipSupported = pipSupported,
                chapterStarts = plan.chapters.map { it.startSeconds },
                fillsScreen = fillsScreen,
                onTimelineTop = { timelineTop = it },
                onToggleFill = {
                    fillsScreen = !fillsScreen
                    reveal()
                },
                onClose = onClose,
                onLock = {
                    locked = true
                    lockHint = true
                    interaction += 1
                },
                onPip = { activity?.let { PlayerWindow.enter(it) } },
                onMore = {
                    menuPage = PlayerMenuPage.Root
                    reveal()
                },
                onTogglePlay = togglePlay,
                onSkip = skipBy,
                onScrub = { time ->
                    scrubTime = time
                    interaction += 1
                },
                onSeek = { time ->
                    scrubTime = null
                    val target = time.coerceAtLeast(streamOffset)
                    seekMedia(target)
                    currentOnUserTransport(PlayerDirective.Seek(target))
                    reveal()
                },
                trickplay = plan.trickplay ?: bif?.info,
                trickplayUrl = { time ->
                    val info = plan.trickplay ?: return@PlayerChrome bif?.frame(time)
                    val signed = session ?: return@PlayerChrome null
                    app.zelefin.core.ArtworkUrls.trickplayTile(signed.serverUrl, plan.item.id, info, time, signed.accessToken)
                },
                onCast = {},
            )
        }
        if (showStats && !inPip) {
            PlaybackStatsPanel(
                player = player,
                plan = plan,
                position = mediaPosition,
                duration = mediaDuration,
                speed = speed,
                fillsScreen = fillsScreen,
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .windowInsetsPadding(WindowInsets.safeDrawing)
                    .padding(start = 16.dp, top = 64.dp, end = 16.dp)
                    .heightIn(max = playerStatsMaxHeight(showChrome)),
            )
        }
        val lift by animateDpAsState(if (showChrome) 84.dp else 18.dp, label = "player-lift")
        val promptVisible = prompt != null && !inPip && !locked && !(upNextVisible && (prompt.kind == SkipSegment.Kind.Outro || prompt.kind == SkipSegment.Kind.Preview))
        AnimatedVisibility(
            visible = promptVisible,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(end = 20.dp, bottom = lift),
        ) {
            Text(
                prompt?.title.orEmpty(),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                modifier = Modifier
                    .playerGlass(RoundedCornerShape(50))
                    .clickable {
                        prompt?.let(skip)
                        reveal()
                    }
                    .padding(horizontal = 16.dp, vertical = 9.dp),
            )
        }
        AnimatedVisibility(
            visible = upNextVisible && !inPip && nextEpisode != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(start = 20.dp, end = 20.dp, bottom = lift),
        ) {
            nextEpisode?.let { next ->
                val countdown = upNextCountdown ?: remaining.takeIf { autoplay }
                UpNextCard(
                    item = next,
                    artwork = nextArtwork,
                    status = when {
                        finishing -> "Starting…"
                        countdown != null -> "Starts in ${countdown.coerceAtLeast(0.0).roundToInt()}s"
                        else -> "Next Episode"
                    },
                    onPlay = advance,
                    onCancel = {
                        upNextCancelled = true
                        upNextCountdown = null
                    },
                )
            }
        }
        AnimatedVisibility(
            visible = locked && lockHint && !inPip,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(bottom = 28.dp),
        ) {
            Row(
                Modifier
                    .playerGlass(RoundedCornerShape(50))
                    .clickable {
                        locked = false
                        lockHint = false
                        reveal()
                    }
                    .padding(horizontal = 18.dp, vertical = 11.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Rounded.LockOpen, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text("Tap to Unlock", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
            }
        }
        playbackError?.takeIf { !inPip && !recovering }?.let { message ->
            PlaybackErrorCard(
                message = message,
                onRetry = {
                    playbackError = null
                    val retry = currentOnRetryStream
                    if (retry != null) {
                        recovering = true
                        retry(mediaSeconds())
                    } else {
                        player.prepare()
                        player.play()
                    }
                },
                onClose = onClose,
                modifier = Modifier.align(Alignment.Center),
            )
        }
    }

    PresentZelefinOverlay(visible = menuPage != null && !inPip) {
        val page = menuPage ?: return@PresentZelefinOverlay
        PlayerMenuPanel(
            page = page,
            onPage = { menuPage = it },
            onClose = { menuPage = null },
            speed = speed,
            onSpeed = selectSpeed,
            audio = audioTracks.map { it.overlay() },
            audioNote = audioNote,
            onAudio = { overlay -> audioTracks.firstOrNull { it.overlay().key == overlay.key }?.let(selectAudio) },
            subtitles = subtitleTracks.map { it.overlay() },
            onSubtitle = { overlay ->
                selectSubtitle(overlay?.let { chosen -> subtitleTracks.firstOrNull { it.overlay().key == chosen.key } })
            },
            chapters = plan.chapters,
            position = mediaPosition,
            onChapter = { chapter ->
                seekMedia(chapter.startSeconds.coerceAtLeast(streamOffset))
                menuPage = null
                reveal()
            },
            sleep = sleep,
            sleepRemaining = if (sleep is SleepTimer.Minutes) {
                ((sleepDeadline - android.os.SystemClock.elapsedRealtime()) / 1000.0).coerceAtLeast(0.0)
            } else {
                null
            },
            sleepOffersEndOfEpisode = item.kind == MediaKind.Episode,
            onSleep = { timer ->
                sleep = timer
                menuPage = null
            },
            onAddSubtitles = onAddSubtitles?.let { add ->
                {
                    menuPage = null
                    add(mediaSeconds())
                }
            },
            fillsScreen = fillsScreen,
            onToggleFill = { fillsScreen = !fillsScreen },
            showStats = showStats,
            onToggleStats = { showStats = !showStats },
            onAppearanceChange = { styleRevision += 1 },
        )
    }
    }
}

@Composable
internal fun PlayerChrome(
    title: String,
    subtitle: String?,
    playing: Boolean,
    buffering: Boolean,
    position: Double,
    duration: Double,
    skipBack: Int,
    skipForward: Int,
    pipSupported: Boolean,
    chapterStarts: List<Double>,
    fillsScreen: Boolean,
    onToggleFill: () -> Unit,
    onClose: () -> Unit,
    onLock: () -> Unit,
    onPip: () -> Unit,
    onMore: () -> Unit,
    onTogglePlay: () -> Unit,
    onSkip: (Int) -> Unit,
    onScrub: (Double) -> Unit,
    onSeek: (Double) -> Unit,
    trickplay: app.zelefin.core.TrickplayInfo? = null,
    trickplayUrl: ((Double) -> Any?)? = null,
    onCast: (() -> Unit)? = null,
    onTimelineTop: (Float) -> Unit = {},
) {
    val wide = LocalConfiguration.current.screenWidthDp >= 600
    val horizontal = if (wide) 28.dp else 16.dp
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(140.dp)
                .background(Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))),
        )
        Box(
            Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .height(180.dp)
                .background(Brush.verticalGradient(listOf(Color.Transparent, Color.Black.copy(alpha = 0.5f)))),
        )
        Box(Modifier.align(Alignment.Center)) {
            Row(horizontalArrangement = Arrangement.spacedBy(if (wide) 64.dp else 40.dp), verticalAlignment = Alignment.CenterVertically) {
                SkipButton(seconds = skipBack, forward = false) { onSkip(-skipBack) }
                Box(
                    Modifier
                        .size(72.dp)
                        .playerGlass(CircleShape)
                        .clickable(onClick = onTogglePlay),
                    contentAlignment = Alignment.Center,
                ) {
                    if (buffering) {
                        CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.size(34.dp))
                    } else {
                        Icon(
                            if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                            contentDescription = if (playing) "Pause" else "Play",
                            tint = Color.White,
                            modifier = Modifier.size(38.dp),
                        )
                    }
                }
                SkipButton(seconds = skipForward, forward = true) { onSkip(skipForward) }
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(horizontal = horizontal)
                .padding(top = 8.dp, bottom = 8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                GlassIconButton(Icons.Rounded.Close, "Close", onClick = onClose)
                Column(
                    Modifier
                        .weight(1f)
                        .padding(horizontal = 12.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(
                        title,
                        color = Color.White,
                        fontFamily = ZelefinFont,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 17.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    subtitle?.let {
                        Text(
                            it,
                            color = Color.White.copy(alpha = 0.72f),
                            fontFamily = ZelefinFont,
                            fontSize = 13.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (onCast != null) {
                        Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) {
                            app.zelefin.client.cast.CastRouteButton()
                        }
                    }
                    GlassIconButton(Icons.Rounded.Lock, "Lock Controls", onClick = onLock)
                    if (pipSupported) GlassIconButton(Icons.Rounded.PictureInPictureAlt, "Picture in Picture", onClick = onPip)
                    GlassIconButton(
                        if (fillsScreen) Icons.Rounded.CloseFullscreen else Icons.Rounded.OpenInFull,
                        if (fillsScreen) "Fit to screen" else "Fill screen",
                        onClick = onToggleFill,
                    )
                    GlassIconButton(Icons.Rounded.MoreHoriz, "More", onClick = onMore)
                }
            }
            Spacer(Modifier.weight(1f))
            Timeline(
                position = position,
                duration = duration,
                chapterStarts = chapterStarts,
                onScrub = onScrub,
                onSeek = onSeek,
                trickplay = trickplay,
                trickplayUrl = { time -> trickplayUrl?.invoke(time) },
                onBarTop = onTimelineTop,
            )
        }
    }
}

@Composable
private fun Timeline(
    position: Double,
    duration: Double,
    chapterStarts: List<Double>,
    onScrub: (Double) -> Unit,
    onSeek: (Double) -> Unit,
    trickplay: app.zelefin.core.TrickplayInfo? = null,
    trickplayUrl: (Double) -> Any? = { null },
    onBarTop: (Float) -> Unit = {},
) {
    var previewing by remember { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth()) {
        if (previewing && trickplay != null) {
            val url = trickplayUrl(position)
            if (url != null) {
                Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    TrickplayPreview(url, trickplay, position)
                }
            }
        }
    Row(
        Modifier
            .fillMaxWidth()
            .onGloballyPositioned { onBarTop(it.positionInRoot().y) }
            .playerGlass(RoundedCornerShape(50))
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TimeLabel(clock(position), Modifier.widthIn(min = 48.dp))
        Scrubber(
            position = position,
            duration = duration,
            chapterStarts = chapterStarts,
            onScrub = {
                previewing = true
                onScrub(it)
            },
            onSeek = {
                previewing = false
                onSeek(it)
            },
            modifier = Modifier
                .weight(1f)
                .height(28.dp)
                .padding(horizontal = 12.dp),
        )
        TimeLabel(if (duration > 0) "-" + clock(duration - position) else "--:--", Modifier.widthIn(min = 56.dp), end = true)
    }
    }
}

/** [image] is a tile sheet URL, or the JPEG bytes of one BIF frame. */
@Composable
private fun TrickplayPreview(image: Any, info: app.zelefin.core.TrickplayInfo, time: Double) {
    val cell = info.cell(time)
    val previewW = 160.dp
    val thumbW = info.thumbnailWidth.coerceAtLeast(1)
    val thumbH = info.thumbnailHeight.coerceAtLeast(1)
    val previewH = previewW * thumbH / thumbW
    Box(
        Modifier
            .size(previewW, previewH)
            .clip(RoundedCornerShape(8.dp))
            .background(Color.Black),
    ) {
        coil.compose.AsyncImage(
            model = image,
            contentDescription = null,
            contentScale = ContentScale.FillBounds,
            modifier = Modifier
                .requiredWidth(previewW * info.tileWidth.coerceAtLeast(1))
                .requiredHeight(previewH * info.tileHeight.coerceAtLeast(1))
                .offset(x = -(previewW * cell.first), y = -(previewH * cell.second)),
        )
    }
}

@Composable
private fun TimeLabel(text: String, modifier: Modifier, end: Boolean = false) {
    Text(
        text,
        color = Color.White,
        fontFamily = ZelefinFont,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        textAlign = if (end) androidx.compose.ui.text.style.TextAlign.End else androidx.compose.ui.text.style.TextAlign.Start,
        style = androidx.compose.ui.text.TextStyle(fontFeatureSettings = "tnum"),
        modifier = modifier,
    )
}

/** Thin capsule that thickens and shows a knob while dragged, like the iOS AVKit timeline. */
@Composable
private fun Scrubber(
    position: Double,
    duration: Double,
    chapterStarts: List<Double>,
    onScrub: (Double) -> Unit,
    onSeek: (Double) -> Unit,
    modifier: Modifier,
) {
    var dragging by remember { mutableStateOf(false) }
    val currentScrub by rememberUpdatedState(onScrub)
    val currentSeek by rememberUpdatedState(onSeek)
    val thickness by animateDpAsState(if (dragging) 8.dp else 5.dp, label = "scrub-thickness")
    val fraction = if (duration > 0) (position / duration).coerceIn(0.0, 1.0).toFloat() else 0f
    androidx.compose.foundation.layout.BoxWithConstraints(
        modifier.pointerInput(duration) {
            if (duration <= 0) return@pointerInput
            awaitEachGesture {
                val down = awaitFirstDown()
                fun timeAt(x: Float) = (x / size.width.coerceAtLeast(1)).coerceIn(0f, 1f) * duration
                dragging = true
                down.consume()
                var last = down.position.x
                currentScrub(timeAt(last))
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) break
                    last = change.position.x
                    change.consume()
                    currentScrub(timeAt(last))
                }
                dragging = false
                currentSeek(timeAt(last))
            }
        },
        contentAlignment = Alignment.CenterStart,
    ) {
        val width = maxWidth
        Box(
            Modifier
                .fillMaxWidth()
                .height(thickness)
                .clip(RoundedCornerShape(50))
                .background(Color.White.copy(alpha = 0.32f)),
        )
        Box(
            Modifier
                .width((width * fraction).coerceAtLeast(4.dp))
                .height(thickness)
                .clip(RoundedCornerShape(50))
                .background(Color.White),
        )
        if (duration > 0) {
            val tickHeight by animateDpAsState(if (dragging) 10.dp else 7.dp, label = "chapter-tick")
            chapterStarts.filter { it > 1.0 && it < duration - 1.0 }.forEach { start ->
                Box(
                    Modifier
                        .offset { IntOffset((width * (start / duration).toFloat()).roundToPx(), 0) }
                        .width(1.5.dp)
                        .height(tickHeight)
                        .background(Color.White.copy(alpha = 0.7f)),
                )
            }
        }
        if (dragging) {
            Box(
                Modifier
                    .offset { IntOffset(((width * fraction) - 8.dp).roundToPx(), 0) }
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(Color.White),
            )
        }
    }
}

@Composable
private fun SkipButton(seconds: Int, forward: Boolean, onClick: () -> Unit) {
    val icon = skipIcon(seconds, forward)
    Box(
        Modifier
            .size(56.dp)
            .playerGlass(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        val description = if (forward) "Skip forward $seconds seconds" else "Skip back $seconds seconds"
        if (icon != null) {
            Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(30.dp))
        } else {
            Icon(
                Icons.Rounded.Replay,
                contentDescription = description,
                tint = Color.White,
                modifier = Modifier
                    .size(30.dp)
                    .graphicsLayer { scaleX = if (forward) -1f else 1f },
            )
            Text(
                seconds.toString(),
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.Bold,
                fontSize = 8.sp,
                modifier = Modifier.padding(top = 3.dp),
            )
        }
    }
}

@Composable
private fun GlassIconButton(icon: ImageVector, description: String, size: Dp = 44.dp, onClick: () -> Unit) {
    Box(
        Modifier
            .size(size)
            .playerGlass(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(22.dp))
    }
}

@Composable
internal fun UpNextCard(item: MediaItem, artwork: List<String>, status: String, onPlay: () -> Unit, onCancel: () -> Unit) {
    Row(
        Modifier
            .widthIn(max = 420.dp)
            .playerGlass(RoundedCornerShape(22.dp))
            .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
            .padding(10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CachedArtwork(
            urls = artwork,
            contentDescription = null,
            modifier = Modifier
                .size(width = 128.dp, height = 72.dp)
                .clip(RoundedCornerShape(12.dp)),
        )
        Column(
            Modifier
                .weight(1f, fill = false)
                .padding(start = 12.dp),
        ) {
            Text(
                status,
                color = Color.White.copy(alpha = 0.72f),
                fontFamily = ZelefinFont,
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                episodeCaption(item, includeName = true) ?: item.name,
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Row(
                    Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color.White)
                        .clickable(onClick = onPlay)
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = Color.Black, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("Play Now", color = Color.Black, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                }
                Text(
                    "Cancel",
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 14.sp,
                    modifier = Modifier
                        .clip(RoundedCornerShape(50))
                        .background(Color.White.copy(alpha = 0.14f))
                        .clickable(onClick = onCancel)
                        .padding(horizontal = 14.dp, vertical = 7.dp),
                )
            }
        }
    }
}

/** A dropped socket or a dead server stream. A new session can replace it; a decoder failure cannot. */
private fun isRecoverableSource(error: PlaybackException): Boolean {
    val code = error.errorCode
    return code == PlaybackException.ERROR_CODE_IO_UNSPECIFIED ||
        code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
        code == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
        code == PlaybackException.ERROR_CODE_IO_INVALID_HTTP_CONTENT_TYPE ||
        code == PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS ||
        code == PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND ||
        code == PlaybackException.ERROR_CODE_IO_NO_PERMISSION ||
        code == PlaybackException.ERROR_CODE_IO_CLEARTEXT_NOT_PERMITTED ||
        code == PlaybackException.ERROR_CODE_IO_READ_POSITION_OUT_OF_RANGE ||
        code == PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED ||
        code == PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED ||
        code == PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED ||
        code == PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED
}

private fun playbackFailureCopy(error: PlaybackException): String = when (error.errorCode) {
    PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS,
    PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,
    -> "The server closed this stream."
    PlaybackException.ERROR_CODE_PARSING_CONTAINER_MALFORMED,
    PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED,
    PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED,
    PlaybackException.ERROR_CODE_PARSING_MANIFEST_UNSUPPORTED,
    -> "This file couldn't be read from the server."
    else -> "The connection to the server dropped."
}

@Composable
private fun PlaybackErrorCard(message: String, onRetry: () -> Unit, onClose: () -> Unit, modifier: Modifier) {
    Column(
        modifier
            .widthIn(max = 380.dp)
            .padding(24.dp)
            .playerGlass(RoundedCornerShape(22.dp))
            .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {}
            .padding(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text("Playback stopped", color = Color.White, fontFamily = ZelefinFont, fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
        Spacer(Modifier.height(6.dp))
        Text(
            message,
            color = Color.White.copy(alpha = 0.72f),
            fontFamily = ZelefinFont,
            fontSize = 14.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            maxLines = 4,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(
                "Try Again",
                color = Color.Black,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(Color.White)
                    .clickable(onClick = onRetry)
                    .padding(horizontal = 18.dp, vertical = 9.dp),
            )
            Text(
                "Close",
                color = Color.White,
                fontFamily = ZelefinFont,
                fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp,
                modifier = Modifier
                    .clip(RoundedCornerShape(50))
                    .background(Color.White.copy(alpha = 0.14f))
                    .clickable(onClick = onClose)
                    .padding(horizontal = 18.dp, vertical = 9.dp),
            )
        }
    }
}

@Composable
internal fun PlayerMenuPanel(
    page: PlayerMenuPage,
    onPage: (PlayerMenuPage) -> Unit,
    onClose: () -> Unit,
    speed: Float,
    onSpeed: (Float) -> Unit,
    audio: List<OverlayTrack>,
    audioNote: String?,
    onAudio: (OverlayTrack) -> Unit,
    subtitles: List<OverlayTrack>,
    onSubtitle: (OverlayTrack?) -> Unit,
    chapters: List<PlaybackChapter>,
    position: Double,
    onChapter: (PlaybackChapter) -> Unit,
    sleep: SleepTimer,
    sleepRemaining: Double?,
    sleepOffersEndOfEpisode: Boolean,
    onSleep: (SleepTimer) -> Unit,
    onAddSubtitles: (() -> Unit)?,
    fillsScreen: Boolean,
    onToggleFill: () -> Unit,
    showStats: Boolean,
    onToggleStats: () -> Unit,
    onAppearanceChange: () -> Unit = {},
) {
    val context = LocalContext.current
    var appearance by remember { mutableStateOf(SubtitleAppearance.current(context)) }
    fun updateAppearance(change: () -> Unit) {
        change()
        appearance = SubtitleAppearance.current(context)
        onAppearanceChange()
    }
    val screenHeight = LocalConfiguration.current.screenHeightDp.dp
    Box(Modifier.fillMaxSize()) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.28f))
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }, onClick = onClose),
        )
        Column(
            Modifier
                .align(Alignment.TopEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(top = 60.dp, end = 16.dp, start = 16.dp, bottom = 88.dp)
                .width(320.dp)
                .heightIn(max = minOf(420.dp, (screenHeight - 148.dp).coerceAtLeast(180.dp)))
                .playerGlass(RoundedCornerShape(22.dp))
                .clickable(indication = null, interactionSource = remember { MutableInteractionSource() }) {},
        ) {
            Row(
                Modifier.padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (page != PlayerMenuPage.Root) {
                    MenuIcon(Icons.AutoMirrored.Rounded.ArrowBack, "Back") { onPage(PlayerMenuPage.Root) }
                }
                Text(
                    page.title,
                    color = Color.White,
                    fontFamily = ZelefinFont,
                    fontWeight = FontWeight.SemiBold,
                    fontSize = 17.sp,
                    modifier = Modifier
                        .weight(1f)
                        .padding(horizontal = 6.dp),
                )
                MenuIcon(Icons.Rounded.Close, "Close", onClick = onClose)
            }
            Box(
                Modifier
                    .fillMaxWidth()
                    .height(0.5.dp)
                    .background(Color.White.copy(alpha = 0.12f)),
            )
            Column(
                Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(vertical = 6.dp),
            ) {
                when (page) {
                    PlayerMenuPage.Root -> {
                        MenuRow("Playback Speed", PlaybackPreferences.speedTitle(speed), Icons.Rounded.Speed) { onPage(PlayerMenuPage.Speed) }
                        MenuRow("Select Audio", audio.firstOrNull { it.selected }?.title ?: "Default", Icons.Rounded.GraphicEq) {
                            onPage(PlayerMenuPage.Audio)
                        }
                        MenuRow("Select Subtitles", subtitles.firstOrNull { it.selected }?.title ?: "Off", Icons.Rounded.ClosedCaption) {
                            onPage(PlayerMenuPage.Subtitles)
                        }
                        MenuRow("Subtitle Style", appearance.sizeTitle(), Icons.Rounded.TextFields) {
                            onPage(PlayerMenuPage.SubtitleStyle)
                        }
                        MenuRow("Subtitle Sync", appearance.syncTitle(), Icons.Rounded.Sync) {
                            onPage(PlayerMenuPage.SubtitleSync)
                        }
                        if (chapters.isNotEmpty()) {
                            MenuRow("Chapters", chapters.size.toString(), Icons.AutoMirrored.Rounded.FormatListBulleted) {
                                onPage(PlayerMenuPage.Chapters)
                            }
                        }
                        MenuRow(
                            "Sleep Timer",
                            sleepRemaining?.let { clockText(it) } ?: sleepTitle(sleep),
                            Icons.Rounded.Bedtime,
                        ) { onPage(PlayerMenuPage.Sleep) }
                        ToggleRow("Fill screen", Icons.Rounded.OpenInFull, fillsScreen, onToggleFill)
                        ToggleRow("Stats", Icons.Rounded.Info, showStats, onToggleStats)
                    }
                    PlayerMenuPage.Chapters -> {
                        val current = chapters.lastOrNull { it.startSeconds <= position + 0.5 }
                        chapters.forEach { chapter ->
                            ChoiceRow("${clockText(chapter.startSeconds)}  ${chapter.name}", selected = chapter == current) { onChapter(chapter) }
                        }
                    }
                    PlayerMenuPage.Sleep -> {
                        ChoiceRow("Off", selected = sleep == SleepTimer.Off) { onSleep(SleepTimer.Off) }
                        SleepTimer.durations.forEach { minutes ->
                            val timer = SleepTimer.Minutes(minutes)
                            ChoiceRow(sleepTitle(timer), selected = sleep == timer) { onSleep(timer) }
                        }
                        if (sleepOffersEndOfEpisode) {
                            ChoiceRow(sleepTitle(SleepTimer.EndOfEpisode), selected = sleep == SleepTimer.EndOfEpisode) {
                                onSleep(SleepTimer.EndOfEpisode)
                            }
                        }
                    }
                    PlayerMenuPage.Speed -> PlaybackPreferences.speeds.forEach { rate ->
                        ChoiceRow(PlaybackPreferences.speedTitle(rate), selected = kotlin.math.abs(rate - speed) < 0.01f) { onSpeed(rate) }
                    }
                    PlayerMenuPage.Audio -> {
                        if (audio.isEmpty()) {
                            MenuNote("This stream has one audio track.")
                        } else {
                            audio.forEach { track -> ChoiceRow(track.title, selected = track.selected) { onAudio(track) } }
                        }
                        audioNote?.let { MenuNote(it) }
                    }
                    PlayerMenuPage.Subtitles -> {
                        onAddSubtitles?.let { add -> ActionRow("Add Subtitles", Icons.Rounded.AddComment, add) }
                        ChoiceRow("Off", selected = subtitles.none { it.selected }) { onSubtitle(null) }
                        subtitles.forEach { track -> ChoiceRow(track.title, selected = track.selected) { onSubtitle(track) } }
                    }
                    PlayerMenuPage.SubtitleStyle -> {
                        MenuNote("Font Size")
                        SubtitleAppearance.sizes.forEach { option ->
                            ChoiceRow(SubtitleAppearance.sizeTitle(option), selected = appearance.size == option) {
                                updateAppearance { SubtitleAppearance.setSize(context, option) }
                            }
                        }
                        if (subtitles.any { it.selected && it.isPicture }) {
                            MenuNote("These subtitles are pictures (PGS or VobSub), so only their size can change.")
                        } else {
                            MenuNote("Text Color")
                            SubtitleAppearance.colors.forEach { option ->
                                ChoiceRow(SubtitleAppearance.colorTitle(option), selected = appearance.color == option) {
                                    updateAppearance { SubtitleAppearance.setColor(context, option) }
                                }
                            }
                            MenuNote("Background")
                            SubtitleAppearance.backgrounds.forEach { option ->
                                ChoiceRow(SubtitleAppearance.backgroundTitle(option), selected = appearance.background == option) {
                                    updateAppearance { SubtitleAppearance.setBackground(context, option) }
                                }
                            }
                        }
                    }
                    PlayerMenuPage.SubtitleSync -> {
                        Text(
                            appearance.syncTitle(),
                            color = Color.White,
                            fontFamily = ZelefinFont,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 16.sp,
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(
                                "−0.25",
                                color = Color.White,
                                fontFamily = ZelefinFont,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(50))
                                    .background(Color.White.copy(alpha = 0.12f))
                                    .clickable {
                                        updateAppearance { SubtitleAppearance.setSyncSeconds(context, appearance.syncSeconds - 0.25) }
                                    }
                                    .padding(vertical = 10.dp),
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            )
                            Text(
                                "+0.25",
                                color = Color.White,
                                fontFamily = ZelefinFont,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier
                                    .weight(1f)
                                    .clip(RoundedCornerShape(50))
                                    .background(Color.White.copy(alpha = 0.12f))
                                    .clickable {
                                        updateAppearance { SubtitleAppearance.setSyncSeconds(context, appearance.syncSeconds + 0.25) }
                                    }
                                    .padding(vertical = 10.dp),
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                            )
                        }
                        Slider(
                            value = appearance.syncSeconds.toFloat(),
                            onValueChange = {
                                updateAppearance { SubtitleAppearance.setSyncSeconds(context, it.toDouble()) }
                            },
                            valueRange = -10f..10f,
                            steps = 79,
                            colors = SliderDefaults.colors(
                                thumbColor = Color.White,
                                activeTrackColor = Color.White,
                                inactiveTrackColor = Color.White.copy(alpha = 0.22f),
                            ),
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                        ChoiceRow("Reset", selected = appearance.syncSeconds == 0.0) {
                            updateAppearance { SubtitleAppearance.setSyncSeconds(context, 0.0) }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun MenuIcon(icon: ImageVector, description: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(36.dp)
            .clip(CircleShape)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun MenuRow(title: String, value: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp)
        Spacer(Modifier.width(8.dp))
        Text(
            value,
            color = Color.White.copy(alpha = 0.62f),
            fontFamily = ZelefinFont,
            fontSize = 14.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
            modifier = Modifier.weight(1f),
        )
        Spacer(Modifier.width(6.dp))
        Icon(
            Icons.AutoMirrored.Rounded.KeyboardArrowRight,
            contentDescription = null,
            tint = Color.White.copy(alpha = 0.45f),
            modifier = Modifier.size(18.dp),
        )
    }
}

@Composable
private fun ActionRow(title: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun ToggleRow(title: String, icon: ImageVector, on: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(22.dp))
        Spacer(Modifier.width(12.dp))
        Text(title, color = Color.White, fontFamily = ZelefinFont, fontSize = 16.sp, modifier = Modifier.weight(1f))
        Text(if (on) "On" else "Off", color = Color.White.copy(alpha = 0.62f), fontFamily = ZelefinFont, fontSize = 14.sp)
        if (on) {
            Spacer(Modifier.width(6.dp))
            Icon(Icons.Rounded.Check, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
        }
    }
}

@Composable
private fun ChoiceRow(title: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            color = Color.White,
            fontFamily = ZelefinFont,
            fontSize = 16.sp,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Spacer(Modifier.width(8.dp))
            Icon(Icons.Rounded.Check, contentDescription = "Selected", tint = Color.White, modifier = Modifier.size(20.dp))
        }
    }
}

@Composable
private fun MenuNote(text: String) {
    Text(
        text,
        color = Color.White.copy(alpha = 0.6f),
        fontFamily = ZelefinFont,
        fontSize = 13.sp,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 10.dp),
    )
}

private fun skipIcon(seconds: Int, forward: Boolean): ImageVector? = when (seconds) {
    5 -> if (forward) Icons.Rounded.Forward5 else Icons.Rounded.Replay5
    10 -> if (forward) Icons.Rounded.Forward10 else Icons.Rounded.Replay10
    30 -> if (forward) Icons.Rounded.Forward30 else Icons.Rounded.Replay30
    else -> null
}

internal fun episodeCaption(item: MediaItem, includeName: Boolean): String? {
    val season = item.seasonIndex
    val episode = item.episodeIndex
    val code = if (season != null && episode != null) "S$season, E$episode" else null
    val parts = listOfNotNull(code, item.name.takeIf { includeName && it.isNotBlank() })
    return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
}

private fun clock(seconds: Double): String {
    val total = seconds.coerceAtLeast(0.0).toLong()
    val hours = total / 3600
    val minutes = (total % 3600) / 60
    val secs = total % 60
    return if (hours > 0) String.format(Locale.US, "%d:%02d:%02d", hours, minutes, secs) else String.format(Locale.US, "%d:%02d", minutes, secs)
}

/**
 * Starts the stream on the tracks Jellyfin picked for this user (preferred audio language,
 * "play default audio track", subtitle mode). ExoPlayer otherwise follows the phone's locale
 * and the file's own flags, which is why a Direct Play ignored the user's server settings.
 */
private fun applyServerTrackChoice(player: Player, tracks: Tracks, plan: PlaybackPlan, context: Context): Boolean {
    val builder = player.trackSelectionParameters.buildUpon()
    var changed = false
    plan.audioChoice?.let { choice ->
        val groups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO && it.length > 0 }
        val group = groups.getOrNull(choice.ordinal)?.takeIf { groups.size > 1 }
            ?: groups.firstOrNull { PlaybackLanguage.matchesLabel(it.getTrackFormat(0).label, it.getTrackFormat(0).language, choice.language.orEmpty()) }
        if (group != null && group.length > 0) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
            changed = true
        }
    }
    val subtitle = plan.subtitleChoice
    if (subtitle != null || !plan.subtitlesOff) {
        val text = tracks.groups.filter { it.type == C.TRACK_TYPE_TEXT && it.length > 0 }
        if (text.isEmpty()) return false
        val sideloaded = text.filter { it.getTrackFormat(0).id?.startsWith("jf-ext-") == true }
        val embedded = text - sideloaded.toSet()
        val preferSdh = PlaybackPreferences.preferSdh(context)
        val language = subtitle?.language.orEmpty()
        val sdhMatch: (Tracks.Group) -> Boolean = { group ->
            val format = group.getTrackFormat(0)
            val label = format.label.orEmpty()
            format.roleFlags and (C.ROLE_FLAG_CAPTION or C.ROLE_FLAG_DESCRIBES_MUSIC_AND_SOUND) != 0 ||
                label.contains("SDH", ignoreCase = true) ||
                label.contains("CC", ignoreCase = true) ||
                label.contains("caption", ignoreCase = true)
        }
        val matches: (Tracks.Group) -> Boolean = { group ->
            val format = group.getTrackFormat(0)
            PlaybackLanguage.matchesLabel(format.label, format.language, language)
        }
        val group = when {
            subtitle?.externalId != null -> sideloaded.firstOrNull { it.getTrackFormat(0).id == subtitle.externalId }
            preferSdh -> {
                val pool = embedded.ifEmpty { text }
                pool.firstOrNull { sdhMatch(it) && matches(it) }
                    ?: pool.firstOrNull(sdhMatch)
                    ?: embedded.getOrNull(subtitle?.ordinal ?: -1)
                    ?: embedded.firstOrNull(matches)
            }
            else -> embedded.getOrNull(subtitle?.ordinal ?: -1)
                ?: embedded.firstOrNull(matches)
        } ?: text.firstOrNull()
        if (group != null && group.length > 0) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
                .setIgnoredTextSelectionFlags(0)
                .setOverrideForType(TrackSelectionOverride(group.mediaTrackGroup, 0))
            changed = true
        }
    } else {
        builder.clearOverridesOfType(C.TRACK_TYPE_TEXT).setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        changed = true
    }
    if (changed) player.trackSelectionParameters = builder.build()
    return changed || plan.subtitlesOff
}

private fun preferredLanguages(context: Context, current: TrackSelectionParameters): TrackSelectionParameters {
    val builder = current.buildUpon()
    val audio = PlaybackPreferences.audioLanguage(context)
    if (audio.isNotBlank() && audio != PlaybackPreferences.AUTOMATIC) builder.setPreferredAudioLanguage(audio)
    when (val subtitles = PlaybackPreferences.subtitleLanguage(context)) {
        PlaybackPreferences.OFF -> builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true)
        PlaybackPreferences.AUTOMATIC, "" -> Unit
        else -> builder.setPreferredTextLanguage(subtitles)
    }
    return builder.build()
}

private fun playerTracks(tracks: Tracks, type: Int): List<PlayerTrack> {
    val found = mutableListOf<Triple<String, Tracks.Group, Int>>()
    tracks.groups.filter { it.type == type }.forEach { group ->
        for (index in 0 until group.length) {
            if (!group.isTrackSupported(index)) continue
            found += Triple(trackTitle(group.getTrackFormat(index), type, found.size + 1), group, index)
        }
    }
    val counts = found.groupingBy { it.first }.eachCount()
    val seen = mutableMapOf<String, Int>()
    return found.map { (title, group, index) ->
        val shown = if ((counts[title] ?: 0) > 1) {
            val ordinal = (seen[title] ?: 0) + 1
            seen[title] = ordinal
            "$title ($ordinal)"
        } else {
            title
        }
        PlayerTrack(shown, group, index, group.isTrackSelected(index))
    }
}

private fun Tracks.isHdrVideo(): Boolean = groups.any { group ->
    group.type == C.TRACK_TYPE_VIDEO && (0 until group.length).any { index ->
        if (!group.isTrackSelected(index)) return@any false
        val format = group.getTrackFormat(index)
        format.sampleMimeType == MimeTypes.VIDEO_DOLBY_VISION ||
            format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_ST2084 ||
            format.colorInfo?.colorTransfer == C.COLOR_TRANSFER_HLG
    }
}

private fun trackTitle(format: Format, type: Int, ordinal: Int): String {
    val language = format.language
        ?.takeIf { it.isNotBlank() && it != C.LANGUAGE_UNDETERMINED }
        ?.let { code ->
            Locale.forLanguageTag(code).getDisplayLanguage(Locale.getDefault())
                .takeIf { it.isNotBlank() && !it.equals(code, ignoreCase = true) }
                ?.replaceFirstChar { it.titlecase(Locale.getDefault()) }
                ?: code
        }
    val label = format.label?.trim()?.takeIf { it.isNotEmpty() }
    val details = buildList {
        if (type == C.TRACK_TYPE_AUDIO) {
            audioCodec(format.sampleMimeType)?.let(::add)
            channelLayout(format.channelCount)?.let(::add)
        } else {
            if (format.selectionFlags and C.SELECTION_FLAG_FORCED != 0) add("Forced")
            if (format.roleFlags and (C.ROLE_FLAG_CAPTION or C.ROLE_FLAG_DESCRIBES_MUSIC_AND_SOUND) != 0) add("SDH")
        }
    }
    val base = label ?: language ?: if (type == C.TRACK_TYPE_AUDIO) "Audio $ordinal" else "Subtitle $ordinal"
    val extra = if (label != null) details.filter { !label.contains(it, ignoreCase = true) } else details
    return (listOf(base) + extra).joinToString(" · ")
}

private fun audioCodec(mime: String?): String? = when (mime) {
    MimeTypes.AUDIO_AC3 -> "Dolby Digital"
    MimeTypes.AUDIO_E_AC3, MimeTypes.AUDIO_E_AC3_JOC -> "Dolby Digital+"
    MimeTypes.AUDIO_TRUEHD -> "TrueHD"
    MimeTypes.AUDIO_DTS, MimeTypes.AUDIO_DTS_HD, MimeTypes.AUDIO_DTS_EXPRESS -> "DTS"
    MimeTypes.AUDIO_AAC -> "AAC"
    MimeTypes.AUDIO_OPUS -> "Opus"
    MimeTypes.AUDIO_FLAC -> "FLAC"
    MimeTypes.AUDIO_MPEG -> "MP3"
    else -> null
}

private fun channelLayout(channels: Int): String? = when {
    channels == 1 -> "Mono"
    channels == 2 -> "Stereo"
    channels == 6 -> "5.1"
    channels == 8 -> "7.1"
    channels > 0 -> "${channels}ch"
    else -> null
}
