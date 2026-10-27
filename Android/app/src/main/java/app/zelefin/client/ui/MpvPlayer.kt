package app.zelefin.client.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.SystemClock
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.LockOpen
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.PlayerDirective
import app.zelefin.client.SubtitleAppearance
import app.zelefin.client.SubtitlePictureLayout
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.client.plugins.SkipPrompt
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.client.PlaybackLanguage
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.SavedSession
import dev.jdtech.mpv.MPVLib
import java.util.Locale
import kotlin.math.min
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow

data class MpvPlaybackState(
    val playing: Boolean = false,
    val buffering: Boolean = true,
    val ended: Boolean = false,
    val position: Double = 0.0,
    val duration: Double = 0.0,
    val speed: Float = 1f,
)

class MpvController(private val mpv: MPVLib) {
    fun play() = mpv.setPropertyBoolean("pause", false)
    fun pause() = mpv.setPropertyBoolean("pause", true)
    fun toggle() {
        mpv.setPropertyBoolean("pause", mpv.getPropertyBoolean("pause") != true)
    }
    fun seek(seconds: Double) = mpv.command(arrayOf("seek", seconds.coerceAtLeast(0.0).toString(), "absolute"))
    fun setSpeed(rate: Float) = mpv.setPropertyDouble("speed", rate.toDouble())
    fun duration(): Double = mpv.getPropertyDouble("duration") ?: 0.0
    fun position(): Double = mpv.getPropertyDouble("time-pos") ?: 0.0
    fun isPaused(): Boolean = mpv.getPropertyBoolean("pause") == true
    fun eof(): Boolean = mpv.getPropertyBoolean("eof-reached") == true
    fun speed(): Float = (mpv.getPropertyDouble("speed") ?: 1.0).toFloat()
    private var viewWidth = 0
    private var viewHeight = 0
    private var fillScreen = false
    private var subtitleStyle = SubtitleAppearance.Snapshot()

    fun setFillScreen(fill: Boolean) {
        fillScreen = fill
        mpv.setPropertyDouble("panscan", if (fill) 1.0 else 0.0)
        applySubtitlePlacement()
    }

    fun setViewSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        viewWidth = width
        viewHeight = height
        applySubtitlePlacement()
    }

    fun selectAudio(id: String) = mpv.setPropertyString("aid", id)
    fun selectSubtitle(id: String?) = mpv.setPropertyString("sid", id ?: "no")

    fun videoWidth(): Float {
        val display = mpv.getPropertyInt("dwidth") ?: 0
        val raw = mpv.getPropertyInt("video-params/w") ?: 0
        return (if (display > 0) display else raw).toFloat()
    }

    fun videoHeight(): Float {
        val display = mpv.getPropertyInt("dheight") ?: 0
        val raw = mpv.getPropertyInt("video-params/h") ?: 0
        return (if (display > 0) display else raw).toFloat()
    }

    fun applySubtitleAppearance(style: SubtitleAppearance.Snapshot) {
        subtitleStyle = style
        mpv.setPropertyString("sub-delay", style.syncSeconds.toString())
        mpv.setPropertyString("sub-color", style.mpvColor())
        mpv.setPropertyString("sub-border-size", style.mpvBorderSize())
        mpv.setPropertyString("sub-shadow-offset", style.mpvShadowOffset())
        mpv.setPropertyString("sub-back-color", style.mpvBackColor())
        mpv.setPropertyString("sub-italic", "no")
        mpv.setPropertyString("sub-bold", "yes")
        mpv.setPropertyString("sub-align-x", "center")
        mpv.setPropertyString("sub-align-y", "bottom")
        mpv.setPropertyString("sub-ass-override", "strip")
        mpv.setPropertyString("sub-scale-with-window", "no")
        mpv.setPropertyString("sub-use-margins", "yes")
        applySubtitlePlacement()
    }

    fun applySubtitlePlacement() {
        val placed = SubtitlePictureLayout.placement(
            viewWidth = viewWidth,
            viewHeight = viewHeight,
            videoWidth = videoWidth(),
            videoHeight = videoHeight(),
            fill = fillScreen,
            style = subtitleStyle,
        )
        mpv.setPropertyString("sub-font-size", placed.mpvFontSize.toString())
        mpv.setPropertyString("sub-pos", placed.mpvSubPos.toString())
        mpv.setPropertyString("sub-margin-y", "0")
    }

    internal fun tracks(kind: String): List<OverlayTrack> {
        val count = mpv.getPropertyInt("track-list/count") ?: 0
        val found = mutableListOf<OverlayTrack>()
        for (index in 0 until count) {
            if (mpv.getPropertyString("track-list/$index/type") != kind) continue
            val id = mpv.getPropertyInt("track-list/$index/id") ?: continue
            val title = mpv.getPropertyString("track-list/$index/title").orEmpty().trim()
            val lang = mpv.getPropertyString("track-list/$index/lang").orEmpty().trim()
            val selected = mpv.getPropertyBoolean("track-list/$index/selected") == true
            val language = lang.takeIf { it.isNotEmpty() }?.let { code ->
                Locale.forLanguageTag(code).getDisplayLanguage(Locale.getDefault())
                    .takeIf { it.isNotBlank() && !it.equals(code, ignoreCase = true) }
                    ?.replaceFirstChar { it.titlecase(Locale.getDefault()) }
                    ?: code
            }
            val name = listOfNotNull(title.takeIf { it.isNotEmpty() }, language)
                .joinToString(" · ")
                .ifBlank { if (kind == "audio") "Audio ${found.size + 1}" else "Subtitle ${found.size + 1}" }
            found += OverlayTrack(id.toString(), name, selected, lang.takeIf { it.isNotEmpty() })
        }
        return found
    }

    internal fun string(name: String): String? = mpv.getPropertyString(name)?.trim()?.takeIf { it.isNotEmpty() && it != "no" }
    internal fun int(name: String): Int? = mpv.getPropertyInt(name)
    internal fun double(name: String): Double? = mpv.getPropertyDouble(name)
    internal fun bool(name: String): Boolean? = mpv.getPropertyBoolean(name)

    fun applyPlanTracks(plan: PlaybackPlan, preferSdh: Boolean): Boolean {
        val listed = mpv.getPropertyInt("track-list/count") ?: 0
        plan.audioChoice?.let { choice ->
            val audio = tracks("audio")
            val match = audio.getOrNull(choice.ordinal)?.takeIf { audio.size > 1 }
                ?: audio.firstOrNull { PlaybackLanguage.matchesLabel(it.title, it.language, choice.language.orEmpty()) }
                ?: audio.getOrNull(choice.ordinal)
            match?.let { selectAudio(it.key) }
        }
        if (plan.subtitlesOff) {
            selectSubtitle(null)
            return true
        }
        val subtitle = plan.subtitleChoice
        val subs = tracks("sub")
        if (subs.isEmpty()) return listed > 0
        val language = subtitle?.language.orEmpty()
        val ordinal = subtitle?.ordinal ?: -1
        val externalId = subtitle?.externalId
        val sdh = { track: OverlayTrack ->
            track.title.contains("SDH", true) ||
                track.title.contains("CC", true) ||
                track.title.contains("caption", true) ||
                track.title.contains("hearing", true)
        }
        val match = when {
            externalId != null -> subs.firstOrNull { it.title.contains(externalId, true) }
            preferSdh -> subs.firstOrNull { sdh(it) && PlaybackLanguage.matchesLabel(it.title, it.language, language) }
                ?: subs.firstOrNull(sdh)
                ?: subs.getOrNull(ordinal)
            else -> subs.getOrNull(ordinal)
                ?: subs.firstOrNull { PlaybackLanguage.matchesLabel(it.title, it.language, language) }
        } ?: subs.firstOrNull()
        match?.let { selectSubtitle(it.key) }
        return match != null
    }
}

@Composable
fun MpvPlayerHost(
    plan: PlaybackPlan,
    startSeconds: Double,
    headers: Map<String, String>,
    onState: (MpvPlaybackState) -> Unit,
    onEnded: () -> Unit,
    onReady: (MpvController) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current.applicationContext
    val session = remember(plan.streamUrl) { MpvSession(context, plan, startSeconds, headers) }
    DisposableEffect(session) {
        onDispose { session.release() }
    }
    LaunchedEffect(session) {
        while (true) {
            val controller = session.controller
            if (controller == null) {
                delay(80)
                continue
            }
            onReady(controller)
            controller.applySubtitlePlacement()
            val duration = controller.duration()
            val position = controller.position()
            val paused = controller.isPaused()
            val ended = controller.eof() || (duration > 1 && position >= duration - 0.4 && !paused)
            onState(
                MpvPlaybackState(
                    playing = !paused && duration > 0 && !ended,
                    buffering = duration <= 0 && !ended,
                    ended = ended,
                    position = position,
                    duration = duration,
                    speed = controller.speed(),
                ),
            )
            if (ended) {
                onEnded()
                break
            }
            delay(250)
        }
    }
    val configuration = LocalConfiguration.current
    AndroidView(
        modifier = modifier.fillMaxSize(),
        factory = { viewContext ->
            SurfaceView(viewContext).apply {
                holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) {
                        session.attach(holder)
                        session.resize(width, height)
                    }
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                        session.resize(width, height)
                    }
                    override fun surfaceDestroyed(holder: SurfaceHolder) = session.detach()
                })
            }
        },
        update = { view ->
            configuration.orientation
            configuration.screenWidthDp
            configuration.screenHeightDp
            view.post {
                if (view.width > 0 && view.height > 0) {
                    view.holder.setSizeFromLayout()
                    session.resize(view.width, view.height)
                }
            }
        },
    )
}

private class MpvSession(
    context: Context,
    private val plan: PlaybackPlan,
    private val startSeconds: Double,
    private val headers: Map<String, String>,
) {
    var controller: MpvController? = null
        private set
    private val mpv: MPVLib? = MPVLib.create(context)
    private var loaded = false

    init {
        val lib = mpv
        if (lib != null) {
            if (headers.isNotEmpty()) {
                lib.setOptionString("http-header-fields", headers.entries.joinToString(",") { "${it.key}: ${it.value}" })
            }
            lib.setOptionString("hwdec", "auto")
            lib.setOptionString("vo", "gpu")
            lib.setOptionString("keepaspect", "yes")
            lib.setOptionString("video-unscaled", "no")
            lib.setOptionString("force-window", "no")
            lib.setOptionString("keep-open", "yes")
            lib.setOptionString("idle", "once")
            lib.setOptionString("sub-ass", "yes")
            lib.setOptionString("sub-ass-override", "strip")
            lib.setOptionString("sub-italic", "no")
            lib.setOptionString("sub-bold", "yes")
            lib.setOptionString("sub-align-x", "center")
            lib.setOptionString("sub-align-y", "bottom")
            lib.setOptionString("sub-scale-with-window", "no")
            lib.setOptionString("sub-use-margins", "yes")
            lib.setOptionString("sub-pos", "100")
            PlaybackResumePolicy.clientStartPosition(plan.method, startSeconds, plan.clientOwnsPlayhead)?.let { resume ->
                lib.setOptionString("start", resume.toString())
            }
            lib.init()
            controller = MpvController(lib)
        }
    }

    fun resize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        mpv?.setPropertyString("android-surface-size", "${width}x${height}")
        controller?.setViewSize(width, height)
    }

    fun attach(holder: SurfaceHolder) {
        val lib = mpv ?: return
        lib.attachSurface(holder.surface)
        val frame = holder.surfaceFrame
        resize(frame.width(), frame.height())
        lib.setOptionString("force-window", "yes")
        if (!loaded) {
            loaded = true
            PlaybackResumePolicy.clientStartPosition(plan.method, startSeconds, plan.clientOwnsPlayhead)?.let { resume ->
                lib.setPropertyString("start", resume.toString())
            }
            lib.command(arrayOf("loadfile", plan.streamUrl))
            plan.externalSubtitles.forEach { subtitle ->
                lib.command(arrayOf("sub-add", subtitle.url, "auto", subtitle.title, subtitle.language.orEmpty()))
            }
            if (plan.subtitlesOff) lib.setPropertyString("sid", "no")
        } else {
            lib.setPropertyString("vo", "gpu")
        }
    }

    fun detach() {
        mpv?.setPropertyString("vo", "null")
        mpv?.detachSurface()
    }

    fun release() {
        runCatching { mpv?.detachSurface() }
        runCatching { mpv?.destroy() }
        controller = null
    }
}

@Composable
fun MpvPlayerSurface(
    plan: PlaybackPlan,
    session: SavedSession?,
    onProgress: (Double, Boolean) -> Unit,
    onStopped: (Double) -> Unit,
    onClose: () -> Unit,
    onCast: () -> Unit,
    skipSegments: List<SkipSegment> = emptyList(),
    autoSkip: (SkipSegment.Kind) -> Boolean = { false },
    nextEpisode: MediaItem? = null,
    nextArtwork: List<String> = emptyList(),
    onPlayNext: (MediaItem, Double) -> Unit = { _, _ -> },
    onAddSubtitles: ((Double) -> Unit)? = null,
    suspended: Boolean = false,
    onPlaybackReady: () -> Unit = {},
    onUserTransport: (PlayerDirective) -> Unit = {},
    directives: SharedFlow<PlayerDirective>? = null,
) {
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    var controller by remember { mutableStateOf<MpvController?>(null) }
    var state by remember { mutableStateOf(MpvPlaybackState(position = plan.startTimeSeconds)) }
    var lastPosition by remember { mutableStateOf(plan.startTimeSeconds) }
    var trackTick by remember { mutableIntStateOf(0) }
    var styleRevision by remember { mutableIntStateOf(0) }
    var tracksApplied by remember(plan.streamUrl) { mutableStateOf(false) }
    var resumeApplied by remember(plan.streamUrl) { mutableStateOf(false) }
    val resumeAt = remember(plan.streamUrl) {
        PlaybackResumePolicy.clientStartPosition(plan.method, plan.startTimeSeconds, plan.clientOwnsPlayhead)
    }
    val bif = rememberBifPreviews(plan)
    val currentOnProgress by rememberUpdatedState(onProgress)
    val currentOnStopped by rememberUpdatedState(onStopped)
    val currentOnClose by rememberUpdatedState(onClose)
    val currentOnPlaybackReady by rememberUpdatedState(onPlaybackReady)
    val currentOnUserTransport by rememberUpdatedState(onUserTransport)

    DisposableEffect(plan.streamUrl) {
        onDispose { currentOnStopped(lastPosition) }
    }
    LaunchedEffect(state.position, state.playing) {
        lastPosition = state.position
        if (state.duration > 0) currentOnProgress(state.position, !state.playing)
    }
    LaunchedEffect(controller, state.duration, state.buffering) {
        val engine = controller ?: return@LaunchedEffect
        engine.setSpeed(PlaybackPreferences.defaultRate(context))
        engine.applySubtitleAppearance(SubtitleAppearance.current(context))
        if (!tracksApplied && engine.applyPlanTracks(plan, PlaybackPreferences.preferSdh(context))) {
            tracksApplied = true
            trackTick += 1
        }
    }
    LaunchedEffect(controller, state.duration, state.position, state.buffering) {
        val target = resumeAt ?: return@LaunchedEffect
        val engine = controller ?: return@LaunchedEffect
        if (resumeApplied || state.buffering) return@LaunchedEffect
        if (state.duration > 1 && state.duration + 1 < target) return@LaunchedEffect
        if (PlaybackResumePolicy.needsDeferredSeek(plan.method, state.position, plan.startTimeSeconds, plan.clientOwnsPlayhead)) {
            engine.seek(target)
            lastPosition = target
        } else if (state.position > PlaybackResumePolicy.THRESHOLD) {
            resumeApplied = true
        }
    }
    val configuration = LocalConfiguration.current
    LaunchedEffect(
        controller,
        styleRevision,
        configuration.orientation,
        configuration.screenWidthDp,
        configuration.screenHeightDp,
    ) {
        controller?.applySubtitleAppearance(SubtitleAppearance.current(context))
    }

    val lifecycleOwner = LocalLifecycleOwner.current
    DisposableEffect(lifecycleOwner, controller) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_STOP -> {
                    controller?.pause()
                    currentOnProgress(state.position, true)
                }
                Lifecycle.Event.ON_RESUME -> activity?.let(PlayerWindow::reapplyImmersive)
                else -> Unit
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }
    val windowOwner = remember(plan.streamUrl) { Any() }
    DisposableEffect(activity, windowOwner) {
        if (activity != null) {
            PlayerWindow.attach(activity, windowOwner) {
                controller?.pause()
                currentOnStopped(state.position)
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
    LaunchedEffect(activity, windowOwner, state.playing) {
        activity?.let { PlayerWindow.update(it, windowOwner, null, state.playing) }
    }
    DisposableEffect(controller) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context, intent: Intent) {
                controller?.toggle()
            }
        }
        ContextCompat.registerReceiver(context, receiver, IntentFilter(PlayerWindow.ACTION_TOGGLE), ContextCompat.RECEIVER_NOT_EXPORTED)
        onDispose { context.unregisterReceiver(receiver) }
    }

    val inPip = PlayerWindow.inPictureInPicture
    val pipSupported = remember(context) { PlayerWindow.supported(context) }
    val skipBack = remember { PlaybackPreferences.skipBackward(context) }
    val skipForward = remember { PlaybackPreferences.skipForward(context) }
    val autoplayPreference = remember { PlaybackPreferences.autoplayNext(context) }

    var chromeVisible by remember { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var locked by remember { mutableStateOf(false) }
    var lockHint by remember { mutableStateOf(false) }
    var scrubTime by remember { mutableStateOf<Double?>(null) }
    var menuPage by remember { mutableStateOf<PlayerMenuPage?>(null) }
    var fillsScreen by remember { mutableStateOf(false) }
    var showStats by remember { mutableStateOf(false) }
    var sleep by remember { mutableStateOf<SleepTimer>(SleepTimer.Off) }
    var sleepDeadline by remember { mutableLongStateOf(0L) }
    var appliedFill by remember { mutableStateOf(false) }

    LaunchedEffect(fillsScreen, controller) {
        controller?.setFillScreen(fillsScreen)
        appliedFill = fillsScreen
    }
    LaunchedEffect(sleep) {
        val timer = sleep as? SleepTimer.Minutes ?: return@LaunchedEffect
        sleepDeadline = SystemClock.elapsedRealtime() + timer.minutes * 60_000L
        while (SystemClock.elapsedRealtime() < sleepDeadline) delay(1_000)
        controller?.pause()
        sleep = SleepTimer.Off
    }
    LaunchedEffect(suspended) {
        if (suspended) controller?.pause()
    }
    val reveal = {
        chromeVisible = true
        interaction += 1
    }
    LaunchedEffect(chromeVisible, state.playing, scrubTime != null, menuPage, interaction) {
        if (chromeVisible && state.playing && scrubTime == null && menuPage == null) {
            delay(3_000)
            chromeVisible = false
        }
    }
    LaunchedEffect(state.playing) {
        if (!state.playing && !locked) reveal()
    }
    LaunchedEffect(lockHint, interaction) {
        if (lockHint) {
            delay(3_000)
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

    val mediaPosition = state.position
    val mediaDuration = if (state.duration > 0) state.duration else plan.item.runtime ?: 0.0
    val seekMedia: (Double) -> Unit = { target ->
        controller?.seek(target.coerceAtLeast(0.0))
        lastPosition = target
    }
    var announcedReady by remember(plan.streamUrl) { mutableStateOf(false) }
    LaunchedEffect(controller, state.buffering) {
        if (!announcedReady && controller != null && !state.buffering) {
            announcedReady = true
            currentOnPlaybackReady()
        }
    }
    LaunchedEffect(controller, directives) {
        val engine = controller ?: return@LaunchedEffect
        val commands = directives ?: return@LaunchedEffect
        commands.collect { directive ->
            when (directive) {
                PlayerDirective.Play -> engine.play()
                PlayerDirective.Pause -> engine.pause()
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
    LaunchedEffect(prompt, state.buffering) {
        val active = prompt ?: return@LaunchedEffect
        if (!state.buffering && currentAutoSkip(active.kind)) skip(active)
    }

    val autoplay = autoplayPreference && sleep != SleepTimer.EndOfEpisode
    var upNextCancelled by remember { mutableStateOf(false) }
    var upNextCountdown by remember { mutableStateOf<Double?>(null) }
    var finishing by remember { mutableStateOf(false) }
    val outroStart = skipSegments.firstOrNull { it.kind == SkipSegment.Kind.Outro && it.end - it.start >= SkipSegment.MIN_LENGTH }?.start
    val remaining = (mediaDuration - mediaPosition).coerceAtLeast(0.0)
    val inOutro = outroStart != null && mediaPosition >= outroStart - 0.35
    val upNextVisible = nextEpisode != null && !upNextCancelled && mediaDuration > 60.0 &&
        !state.buffering && scrubTime == null && (inOutro || remaining <= 30.0)
    val currentOnPlayNext by rememberUpdatedState(onPlayNext)
    val advance = {
        val next = nextEpisode
        if (!finishing && next != null) {
            finishing = true
            controller?.pause()
            currentOnPlayNext(next, mediaPosition)
        }
    }
    LaunchedEffect(upNextVisible, inOutro) {
        upNextCountdown = if (upNextVisible && autoplay && inOutro) min(10.0, remaining) else null
    }
    LaunchedEffect(upNextCountdown != null, state.playing) {
        while (state.playing && !finishing) {
            val left = upNextCountdown ?: break
            if (left <= 0.0) {
                advance()
                break
            }
            delay(250)
            upNextCountdown = upNextCountdown?.minus(0.25)
        }
    }

    val togglePlay = {
        if (state.ended) {
            controller?.seek(0.0)
            controller?.play()
            currentOnUserTransport(PlayerDirective.Play)
        } else {
            val pausing = state.playing
            controller?.toggle()
            currentOnUserTransport(if (pausing) PlayerDirective.Pause else PlayerDirective.Play)
        }
        reveal()
    }
    val skipBy: (Int) -> Unit = { seconds ->
        val target = (mediaPosition + seconds).coerceAtLeast(0.0)
        seekMedia(target)
        currentOnUserTransport(PlayerDirective.Seek(target))
        reveal()
    }

    val audioTracks = remember(controller, trackTick, state.duration) { controller?.tracks("audio").orEmpty() }
    val subtitleTracks = remember(controller, trackTick, state.duration) { controller?.tracks("sub").orEmpty() }
    val item = plan.item
    val title = if (item.kind == MediaKind.Episode) item.seriesName ?: item.name else item.name
    val subtitle = if (item.kind == MediaKind.Episode) episodeCaption(item, includeName = item.seriesName != null) else null
    val showChrome = chromeVisible && !locked && !inPip && !suspended

    Box(Modifier.fillMaxSize().background(Color.Black)) {
        MpvPlayerHost(
            plan = plan,
            startSeconds = plan.startTimeSeconds,
            headers = plan.headers,
            onState = { state = it },
            onEnded = {
                if (finishing) return@MpvPlayerHost
                if (nextEpisode != null && autoplay && !upNextCancelled) {
                    advance()
                } else {
                    finishing = true
                    currentOnClose()
                }
            },
            onReady = { controller = it },
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
        if (state.buffering && !showChrome && !inPip) {
            CircularProgressIndicator(color = Color.White, strokeWidth = 3.dp, modifier = Modifier.align(Alignment.Center).size(44.dp))
        }
        AnimatedVisibility(visible = showChrome, enter = fadeIn(), exit = fadeOut(), modifier = Modifier.fillMaxSize()) {
            PlayerChrome(
                title = title,
                subtitle = subtitle,
                playing = state.playing,
                buffering = state.buffering,
                position = scrubTime ?: mediaPosition,
                duration = mediaDuration,
                skipBack = skipBack,
                skipForward = skipForward,
                pipSupported = pipSupported,
                chapterStarts = plan.chapters.map { it.startSeconds },
                fillsScreen = fillsScreen,
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
                    trackTick += 1
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
                    seekMedia(time)
                    currentOnUserTransport(PlayerDirective.Seek(time))
                    reveal()
                },
                trickplay = plan.trickplay ?: bif?.info,
                trickplayUrl = { time ->
                    val info = plan.trickplay ?: return@PlayerChrome bif?.frame(time)
                    val signed = session ?: return@PlayerChrome null
                    app.zelefin.core.ArtworkUrls.trickplayTile(signed.serverUrl, plan.item.id, info, time, signed.accessToken)
                },
                onCast = onCast,
            )
        }
        if (showStats && !inPip) {
            controller?.let { engine ->
                MpvPlaybackStatsPanel(
                    controller = engine,
                    plan = plan,
                    position = mediaPosition,
                    duration = mediaDuration,
                    speed = state.speed,
                    fillsScreen = fillsScreen,
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .windowInsetsPadding(WindowInsets.safeDrawing)
                        .padding(start = 16.dp, top = 64.dp, end = 16.dp)
                        .heightIn(max = playerStatsMaxHeight(showChrome)),
                )
            }
        }
        val lift by animateDpAsState(if (showChrome) 84.dp else 18.dp, label = "mpv-player-lift")
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
                        countdown != null -> "Starts in ${countdown.coerceAtLeast(0.0).toInt()}s"
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
    }

    PresentZelefinOverlay(visible = menuPage != null && !inPip) {
        val page = menuPage ?: return@PresentZelefinOverlay
        PlayerMenuPanel(
            page = page,
            onPage = { menuPage = it },
            onClose = { menuPage = null },
            speed = state.speed,
            onSpeed = { rate ->
                controller?.setSpeed(rate)
                menuPage = null
            },
            audio = audioTracks,
            audioNote = null,
            onAudio = { track ->
                controller?.selectAudio(track.key)
                trackTick += 1
                menuPage = null
            },
            subtitles = subtitleTracks,
            onSubtitle = { track ->
                controller?.selectSubtitle(track?.key)
                trackTick += 1
                menuPage = null
            },
            chapters = plan.chapters,
            position = mediaPosition,
            onChapter = { chapter ->
                seekMedia(chapter.startSeconds)
                menuPage = null
                reveal()
            },
            sleep = sleep,
            sleepRemaining = if (sleep is SleepTimer.Minutes) {
                ((sleepDeadline - SystemClock.elapsedRealtime()) / 1000.0).coerceAtLeast(0.0)
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
                    add(mediaPosition)
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
