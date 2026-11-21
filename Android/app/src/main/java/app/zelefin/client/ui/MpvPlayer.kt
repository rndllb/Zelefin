package app.zelefin.client.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import app.zelefin.client.PlaybackPreferences
import app.zelefin.client.PlaybackQuality
import app.zelefin.client.R
import app.zelefin.client.StillWatchingSession
import app.zelefin.client.TrackPick
import app.zelefin.client.PlayerDirective
import app.zelefin.client.SubtitleAppearance
import app.zelefin.client.SubtitlePictureLayout
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.client.plugins.SkipPrompt
import app.zelefin.client.plugins.SkipSegment
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.MediaVersion
import app.zelefin.client.PlaybackLanguage
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.SavedSession
import dev.jdtech.mpv.MPVLib
import java.util.Locale
import kotlin.math.min
import kotlin.math.roundToInt
import java.util.concurrent.Executors
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.withContext

data class MpvPlaybackState(
    val playing: Boolean = false,
    val buffering: Boolean = true,
    val ended: Boolean = false,
    val position: Double = 0.0,
    val duration: Double = 0.0,
    val speed: Float = 1f,
    val cacheSeconds: Double = 0.0,
)

/**
 * Every mpv call waits for mpv's core thread, which can be busy for seconds (software-decoding a
 * 10-bit file, a slow network), so the UI never calls mpv itself: commands are queued here and
 * reads run here through [MpvCalls]. One thread also runs the teardown, so mpv is never destroyed
 * under a call in flight.
 */
private val MpvThread = Executors.newSingleThreadExecutor { Thread(it, "zelefin-mpv") }
internal val MpvCalls = MpvThread.asCoroutineDispatcher()

/**
 * Commands return at once and run in order on [MpvThread]. Reads block, so they're only for code
 * already running on [MpvCalls].
 */
class MpvController(private val mpv: MPVLib) {
    /** Set when the session tears mpv down; calls still queued after that skip it. */
    @Volatile
    internal var released = false

    private fun post(action: () -> Unit) = MpvThread.execute { if (!released) action() }

    fun play() = post { mpv.setPropertyBoolean("pause", false) }
    fun pause() = post { mpv.setPropertyBoolean("pause", true) }
    fun toggle() = post { mpv.setPropertyBoolean("pause", mpv.getPropertyBoolean("pause") != true) }
    fun seek(seconds: Double) = post { mpv.command(arrayOf("seek", seconds.coerceAtLeast(0.0).toString(), "absolute")) }
    fun setSpeed(rate: Float) = post { mpv.setPropertyDouble("speed", rate.toDouble()) }
    fun setVolume(level: Float) = post { mpv.setPropertyDouble("volume", level.coerceIn(0f, 1f) * 100.0) }
    fun duration(): Double = mpv.getPropertyDouble("duration") ?: 0.0
    fun position(): Double = mpv.getPropertyDouble("time-pos") ?: 0.0
    fun isPaused(): Boolean = mpv.getPropertyBoolean("pause") == true
    fun eof(): Boolean = mpv.getPropertyBoolean("eof-reached") == true
    fun speed(): Float = (mpv.getPropertyDouble("speed") ?: 1.0).toFloat()
    private var viewWidth = 0
    private var viewHeight = 0
    private var fillScreen = false
    private var subtitleStyle = SubtitleAppearance.Snapshot()
    private var controlsTop: Float? = null

    /** Top of the visible progress bar in view pixels, or null once the controls hide. */
    fun setControlsTop(top: Float?) = post {
        if (controlsTop != top) {
            controlsTop = top
            applySubtitlePlacement()
        }
    }

    fun setFillScreen(fill: Boolean) = post {
        fillScreen = fill
        mpv.setPropertyDouble("panscan", if (fill) 1.0 else 0.0)
        applySubtitlePlacement()
    }

    fun setViewSize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        post {
            viewWidth = width
            viewHeight = height
            applySubtitlePlacement()
        }
    }

    fun selectAudio(id: String) = post { mpv.setPropertyString("aid", id) }
    fun selectSubtitle(id: String?) = post { mpv.setPropertyString("sid", id ?: "no") }

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

    fun applySubtitleAppearance(style: SubtitleAppearance.Snapshot) = post { setSubtitleAppearance(style) }

    private fun setSubtitleAppearance(style: SubtitleAppearance.Snapshot) {
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

    /** Re-places subtitles for the current video size. Runs on [MpvCalls]. */
    internal fun applySubtitlePlacement() {
        val placed = SubtitlePictureLayout.placement(
            viewWidth = viewWidth,
            viewHeight = viewHeight,
            videoWidth = videoWidth(),
            videoHeight = videoHeight(),
            fill = fillScreen,
            style = subtitleStyle,
            controlsTop = controlsTop,
        )
        // sub-scale is what resizes image subtitles (PGS, VobSub); text takes it on top of the font size,
        // so the font size is divided back out to keep text where the layout put it. Fill/panscan
        // zooms the picture — placed.mpvSubScale is already shrunk by that zoom so captions stay put.
        val scale = placed.mpvSubScale.coerceAtLeast(0.01f)
        mpv.setPropertyString("sub-scale", "%.2f".format(Locale.US, scale))
        mpv.setPropertyString("sub-font-size", (placed.mpvFontSize / scale).roundToInt().toString())
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
            found += OverlayTrack(
                id.toString(),
                name,
                selected,
                lang.takeIf { it.isNotEmpty() },
                isPicture = SubtitleAppearance.isPictureCodec(mpv.getPropertyString("track-list/$index/codec")),
            )
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
    // mpv draws into a bare SurfaceView, so nothing keeps the screen on unless the view asks.
    var playing by remember(session) { mutableStateOf(false) }
    LaunchedEffect(session) {
        while (true) {
            val controller = session.controller
            if (controller == null) {
                delay(80)
                continue
            }
            onReady(controller)
            val (next, running) = withContext(MpvCalls) {
                if (controller.released) return@withContext MpvPlaybackState() to false
                val duration = controller.duration()
                val position = controller.position()
                val paused = controller.isPaused()
                val ended = controller.eof() || (duration > 1 && position >= duration - 0.4 && !paused)
                val cache = controller.double("demuxer-cache-duration")?.takeIf { it >= 0.0 } ?: 0.0
                MpvPlaybackState(
                    playing = !paused && duration > 0 && !ended,
                    buffering = duration <= 0 && !ended,
                    ended = ended,
                    position = position,
                    duration = duration,
                    speed = controller.speed(),
                    cacheSeconds = cache,
                ) to (!paused && !ended)
            }
            playing = running
            onState(next)
            if (next.ended) {
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
            view.keepScreenOn = playing
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
    @Volatile
    var controller: MpvController? = null
        private set
    private var mpv: MPVLib? = null
    private var loaded = false
    @Volatile
    private var released = false
    @Volatile
    private var pendingSurface: Surface? = null
    private var pendingWidth = 0
    private var pendingHeight = 0
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        // Native load + mpv init must never run on the UI thread (ANR on emulators / soft devices).
        // idle=yes keeps the core alive until loadfile/surface catch up — idle=once quit before that.
        val app = context.applicationContext
        MpvThread.execute {
            if (released) return@execute
            val lib = runCatching { MPVLib.create(app) }.getOrNull() ?: return@execute
            if (released) {
                runCatching { lib.destroy() }
                return@execute
            }
            if (headers.isNotEmpty()) {
                lib.setOptionString("http-header-fields", headers.entries.joinToString(",") { "${it.key}: ${it.value}" })
            }
            lib.setOptionString("hwdec", if (PlaybackPreferences.isEmulator()) "no" else "auto")
            lib.setOptionString("vo", "gpu")
            lib.setOptionString("keepaspect", "yes")
            lib.setOptionString("video-unscaled", "no")
            lib.setOptionString("force-window", "no")
            lib.setOptionString("keep-open", "yes")
            lib.setOptionString("idle", "yes")
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
            runCatching { lib.init() }
            if (released) {
                runCatching { lib.destroy() }
                return@execute
            }
            mpv = lib
            controller = MpvController(lib)
            // MediaCodec needs a real surface before loadfile — opening first leaves surface 0x0 (black video, audio only).
            val surface = pendingSurface
            if (surface != null) {
                bindSurfaceOnMain(lib, surface, pendingWidth, pendingHeight)
            }
        }
    }

    fun resize(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        pendingWidth = width
        pendingHeight = height
        val lib = mpv
        val engine = controller
        if (lib == null || engine == null) return
        MpvThread.execute {
            if (released || engine.released) return@execute
            lib.setPropertyString("android-surface-size", "${width}x${height}")
        }
        engine.setViewSize(width, height)
    }

    fun attach(holder: SurfaceHolder) {
        val surface = holder.surface
        val frame = holder.surfaceFrame
        val width = frame.width()
        val height = frame.height()
        pendingSurface = surface
        if (width > 0 && height > 0) {
            pendingWidth = width
            pendingHeight = height
        }
        val lib = mpv
        if (lib != null) {
            // Surface attach must happen on the main thread or the emulator often stays black.
            bindSurfaceOnMain(lib, surface, pendingWidth, pendingHeight)
        }
    }

    private fun loadFileIfNeeded(lib: MPVLib) {
        if (loaded) return
        loaded = true
        PlaybackResumePolicy.clientStartPosition(plan.method, startSeconds, plan.clientOwnsPlayhead)?.let { resume ->
            lib.setPropertyString("start", resume.toString())
        }
        lib.command(arrayOf("loadfile", plan.streamUrl))
        plan.externalSubtitles.forEach { subtitle ->
            lib.command(arrayOf("sub-add", subtitle.url, "auto", subtitle.title, subtitle.language.orEmpty()))
        }
        if (plan.subtitlesOff) lib.setPropertyString("sid", "no")
    }

    private fun bindSurfaceOnMain(lib: MPVLib, surface: Surface, width: Int, height: Int) {
        val work = Runnable {
            if (released || pendingSurface !== surface) return@Runnable
            // attachSurface is JNI into the GL path — keep it on main; other props stay on MpvThread.
            runCatching { lib.attachSurface(surface) }
            MpvThread.execute {
                if (released) return@execute
                if (width > 0 && height > 0) {
                    lib.setPropertyString("android-surface-size", "${width}x${height}")
                    controller?.setViewSize(width, height)
                }
                lib.setPropertyString("force-window", "yes")
                lib.setPropertyString("vo", "gpu")
                loadFileIfNeeded(lib)
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) work.run() else mainHandler.post(work)
    }

    fun detach() {
        val surface = pendingSurface
        pendingSurface = null
        val lib = mpv
        val work = Runnable {
            if (lib == null) return@Runnable
            runCatching { lib.setPropertyString("vo", "null") }
            runCatching { lib.detachSurface() }
        }
        if (surface == null) {
            MpvThread.execute(work)
        } else if (Looper.myLooper() == Looper.getMainLooper()) {
            work.run()
        } else {
            mainHandler.post(work)
        }
    }

    fun release() {
        released = true
        controller?.released = true
        controller = null
        pendingSurface = null
        MpvThread.execute {
            val lib = mpv ?: return@execute
            mpv = null
            runCatching { lib.detachSurface() }
            runCatching { lib.destroy() }
        }
    }
}

@Composable
fun MpvPlayerSurface(
    plan: PlaybackPlan,
    session: SavedSession?,
    onProgress: (Double, Boolean) -> Unit,
    onStopped: (Double) -> Unit,
    onClose: () -> Unit,
    watchTogether: PlayerWatchTogether? = PlayerWatchTogether(),
    skipSegments: List<SkipSegment> = emptyList(),
    autoSkip: (SkipSegment.Kind) -> Boolean = { false },
    nextEpisode: MediaItem? = null,
    nextArtwork: List<String> = emptyList(),
    onPlayNext: (MediaItem, Double) -> Unit = { _, _ -> },
    onAddSubtitles: ((Double) -> Unit)? = null,
    suspended: Boolean = false,
    onPlaybackReady: () -> Unit = {},
    onUserTransport: (PlayerDirective) -> Unit = {},
    onTrackPicked: (TrackPick) -> Unit = {},
    directives: SharedFlow<PlayerDirective>? = null,
    versions: List<MediaVersion> = emptyList(),
    onChooseVersion: ((String, Double) -> Unit)? = null,
    onQualityChange: ((PlaybackQuality, Double) -> Unit)? = null,
) {
    val context = LocalContext.current
    TrackAlertPlayback()
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
        val rate = PlaybackPreferences.defaultRate(context)
        val appearance = SubtitleAppearance.current(context)
        val preferSdh = PlaybackPreferences.preferSdh(context)
        val applied = withContext(MpvCalls) {
            if (engine.released) return@withContext false
            engine.setSpeed(rate)
            engine.applySubtitleAppearance(appearance)
            !tracksApplied && engine.applyPlanTracks(plan, preferSdh)
        }
        if (applied) {
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
        activity?.let {
            PlayerWindow.update(it, windowOwner, null, state.playing, PlaybackPreferences.autoPipOnLeave(it))
        }
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
    var playerVolume by remember(plan.streamUrl) {
        mutableFloatStateOf(context.findActivity()?.musicVolumeFraction() ?: 1f)
    }

    var chromeVisible by remember { mutableStateOf(true) }
    var interaction by remember { mutableIntStateOf(0) }
    var timelineTop by remember { mutableStateOf<Float?>(null) }
    var surfaceTop by remember { mutableFloatStateOf(0f) }
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
        if (!state.playing) reveal()
    }
    LaunchedEffect(inPip) {
        if (inPip) menuPage = null
    }
    BackHandler(enabled = menuPage != null) { menuPage = null }

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
    var stillWatching by remember { mutableStateOf(false) }
    val outroStart = skipSegments.firstOrNull { it.kind == SkipSegment.Kind.Outro && it.end - it.start >= SkipSegment.MIN_LENGTH }?.start
    val remaining = (mediaDuration - mediaPosition).coerceAtLeast(0.0)
    val inOutro = outroStart != null && mediaPosition >= outroStart - 0.35
    val upNextVisible = nextEpisode != null && !upNextCancelled && mediaDuration > 60.0 &&
        !state.buffering && scrubTime == null && (inOutro || remaining <= 30.0)
    val currentOnPlayNext by rememberUpdatedState(onPlayNext)
    val episode = plan.item.kind == MediaKind.Episode
    val advance = advance@{ automatic: Boolean ->
        if (finishing || stillWatching) return@advance
        val next = nextEpisode ?: return@advance
        if (automatic && StillWatchingSession.shouldPrompt(PlaybackPreferences.stillWatchingEnabled(context), episode)) {
            stillWatching = true
            controller?.pause()
            return@advance
        }
        if (automatic) StillWatchingSession.armAuto(next.id) else StillWatchingSession.armManual(next.id)
        finishing = true
        controller?.pause()
        currentOnPlayNext(next, mediaPosition)
    }
    val stopStillWatching = {
        stillWatching = false
        StillWatchingSession.reset()
        currentOnClose()
    }
    val continueStillWatching = {
        stillWatching = false
        StillWatchingSession.continueWatching()
        if (nextEpisode == null) currentOnClose() else advance(true)
    }
    LaunchedEffect(upNextVisible, inOutro) {
        upNextCountdown = if (upNextVisible && autoplay && inOutro && !stillWatching) min(10.0, remaining) else null
    }
    LaunchedEffect(upNextCountdown != null, state.playing, stillWatching) {
        while (state.playing && !finishing && !stillWatching) {
            val left = upNextCountdown ?: break
            if (left <= 0.0) {
                advance(true)
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
    val seekBy: (Int) -> Unit = { seconds ->
        val target = (mediaPosition + seconds).coerceAtLeast(0.0)
        seekMedia(target)
        currentOnUserTransport(PlayerDirective.Seek(target))
    }
    val skipBy: (Int) -> Unit = { seconds ->
        seekBy(seconds)
        reveal()
    }

    var audioTracks by remember { mutableStateOf(emptyList<OverlayTrack>()) }
    var subtitleTracks by remember { mutableStateOf(emptyList<OverlayTrack>()) }
    LaunchedEffect(controller, trackTick, state.duration) {
        val engine = controller
        val (audio, subs) = if (engine == null) {
            emptyList<OverlayTrack>() to emptyList()
        } else {
            withContext(MpvCalls) {
                if (engine.released) emptyList<OverlayTrack>() to emptyList() else engine.tracks("audio") to engine.tracks("sub")
            }
        }
        audioTracks = audio
        subtitleTracks = subs
    }
    val item = plan.item
    val title = if (item.kind == MediaKind.Episode) item.seriesName ?: item.name else item.name
    val subtitle = if (item.kind == MediaKind.Episode) episodeCaption(item, includeName = item.seriesName != null) else null
    val showChrome = chromeVisible && !inPip && !suspended
    val captionGap = with(LocalDensity.current) { 8.dp.toPx() }
    val subtitleCeiling = timelineTop?.takeIf { showChrome }?.let { it - surfaceTop - captionGap }
    LaunchedEffect(controller, subtitleCeiling) { controller?.setControlsTop(subtitleCeiling) }

    Box(Modifier.fillMaxSize().background(Color.Black).onGloballyPositioned { surfaceTop = it.positionInRoot().y }) {
        MpvPlayerHost(
            plan = plan,
            startSeconds = plan.startTimeSeconds,
            headers = plan.headers,
            onState = { state = it },
            onEnded = {
                if (finishing || stillWatching) return@MpvPlayerHost
                if (nextEpisode != null && autoplay && !upNextCancelled) {
                    advance(true)
                } else {
                    finishing = true
                    currentOnClose()
                }
            },
            onReady = {
                controller = it
                it.setVolume(1f)
            },
        )
        PlayerGestureOverlay(
            enabled = !inPip && !stillWatching && menuPage == null,
            controlsVisible = chromeVisible,
            onSingleTap = {
                if (chromeVisible) chromeVisible = false else reveal()
            },
            onSkip = seekBy,
            volume = playerVolume,
            onVolume = { level ->
                // Device volume is set by the gesture overlay; keep MPV at full gain.
                playerVolume = level
                controller?.setVolume(1f)
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
                bufferedAhead = state.cacheSeconds,
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
                watchTogether = watchTogether,
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
        val promptVisible = prompt != null && !inPip && !(upNextVisible && (prompt.kind == SkipSegment.Kind.Outro || prompt.kind == SkipSegment.Kind.Preview))
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
            visible = upNextVisible && !inPip && !stillWatching,
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
                        else -> stringResource(R.string.player_next_episode)
                    },
                    onPlay = { advance(false) },
                    onCancel = {
                        upNextCancelled = true
                        upNextCountdown = null
                    },
                )
            }
        }
        if (stillWatching) {
            BackHandler(onBack = stopStillWatching)
            StillWatchingOverlay(onContinue = continueStillWatching, onStop = stopStillWatching)
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
            },
            audio = audioTracks,
            audioNote = null,
            onAudio = { track ->
                controller?.selectAudio(track.key)
                onTrackPicked(TrackPick.Audio(track.language))
                trackTick += 1
            },
            subtitles = subtitleTracks,
            onSubtitle = { track ->
                controller?.selectSubtitle(track?.key)
                onTrackPicked(track?.let { TrackPick.Subtitle(it.language) } ?: TrackPick.SubtitlesOff)
                trackTick += 1
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
            versions = versions,
            playingVersion = plan.mediaSourceId,
            onVersion = onChooseVersion?.let { choose ->
                { version ->
                    menuPage = null
                    if (version.id != plan.mediaSourceId) choose(version.id, mediaPosition)
                }
            },
            quality = PlaybackPreferences.selectedQuality(context),
            onQuality = onQualityChange?.takeUnless { plan.streamUrl.startsWith("file:") }?.let { change ->
                { option ->
                    menuPage = null
                    change(option, mediaPosition)
                }
            },
        )
    }
}
