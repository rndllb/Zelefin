package app.zelefin.client.ui

import android.app.Activity
import android.app.PendingIntent
import android.content.pm.ActivityInfo
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Rational
import androidx.annotation.RequiresApi
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

/**
 * Picture-in-picture and immersive state for the player on screen.
 * Ownership is token based: the next episode's player can attach before the finished one disposes.
 */
object PlayerWindow {
    const val ACTION_TOGGLE = "app.zelefin.client.action.PIP_TOGGLE"
    private val NarrowestAspect = Rational(100, 239)
    private val WidestAspect = Rational(239, 100)

    var inPictureInPicture by mutableStateOf(false)
        private set

    private var owner: Any? = null
    private var onDismiss: (() -> Unit)? = null
    private var aspect: Rational? = null
    private var playing = false
    private var immersiveHolds = 0
    private var hdr = false
    private val main = Handler(Looper.getMainLooper())

    fun supported(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            context.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    fun attach(activity: Activity, owner: Any, onDismiss: () -> Unit) {
        this.owner = owner
        this.onDismiss = onDismiss
        aspect = null
        playing = false
        apply(activity)
    }

    fun detach(activity: Activity, owner: Any) {
        if (this.owner !== owner) return
        this.owner = null
        onDismiss = null
        playing = false
        apply(activity)
    }

    fun update(activity: Activity, owner: Any, aspect: Rational?, playing: Boolean) {
        if (this.owner !== owner) return
        this.aspect = aspect
        this.playing = playing
        apply(activity)
    }

    fun enter(activity: Activity): Boolean {
        if (owner == null || !supported(activity) || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return runCatching { activity.enterPictureInPictureMode(params(activity)) }.getOrDefault(false)
    }

    /** Android 12+ enters on its own through auto-enter params; older releases need the leave hint. */
    fun onUserLeaveHint(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) return
        if (owner != null && playing) enter(activity)
    }

    /**
     * Closing the PiP window stops the activity without a dedicated callback. Depending on the
     * release, onStop lands just before or just after the mode change, so check now and again shortly.
     */
    fun onModeChanged(activity: Activity, active: Boolean) {
        inPictureInPicture = active
        if (active) return
        val lifecycle = (activity as? LifecycleOwner)?.lifecycle ?: return
        val check = Runnable {
            if (!inPictureInPicture && !lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) dismiss()
        }
        check.run()
        main.postDelayed(check, 500)
    }

    fun holdImmersive(activity: Activity) {
        immersiveHolds += 1
        hideBars(activity)
        applyColorMode(activity)
    }

    /** An SDR window tone-maps HDR into a dim picture. Match the window to the stream. */
    fun setHdr(activity: Activity, enabled: Boolean) {
        if (hdr == enabled) return
        hdr = enabled
        applyColorMode(activity)
    }

    /** Some releases bring the bars back after PiP or the recents screen. */
    fun reapplyImmersive(activity: Activity) {
        if (immersiveHolds > 0) hideBars(activity)
    }

    private fun hideBars(activity: Activity) {
        val controller = WindowCompat.getInsetsController(activity.window, activity.window.decorView)
        controller.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        controller.hide(WindowInsetsCompat.Type.systemBars())
    }

    fun releaseImmersive(activity: Activity) {
        immersiveHolds = (immersiveHolds - 1).coerceAtLeast(0)
        if (immersiveHolds > 0) return
        hdr = false
        applyColorMode(activity)
        WindowCompat.getInsetsController(activity.window, activity.window.decorView).show(WindowInsetsCompat.Type.systemBars())
    }

    private fun applyColorMode(activity: Activity) {
        val mode = if (hdr && immersiveHolds > 0) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        if (activity.window.colorMode != mode) activity.window.colorMode = mode
    }

    private fun dismiss() {
        val callback = onDismiss ?: return
        onDismiss = null
        callback()
    }

    private fun apply(activity: Activity) {
        if (!supported(activity) || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching { activity.setPictureInPictureParams(params(activity)) }
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun params(activity: Activity): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder()
        aspect?.let { builder.setAspectRatio(clamp(it)) }
        builder.setActions(if (owner != null) listOf(toggleAction(activity)) else emptyList())
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(owner != null && playing)
            builder.setSeamlessResizeEnabled(true)
        }
        return builder.build()
    }

    private fun clamp(value: Rational): Rational = when {
        value.toFloat() < NarrowestAspect.toFloat() -> NarrowestAspect
        value.toFloat() > WidestAspect.toFloat() -> WidestAspect
        else -> value
    }

    @RequiresApi(Build.VERSION_CODES.O)
    private fun toggleAction(activity: Activity): RemoteAction {
        val intent = PendingIntent.getBroadcast(
            activity,
            0,
            Intent(ACTION_TOGGLE).setPackage(activity.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val icon = Icon.createWithResource(activity, if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play)
        val title = if (playing) "Pause" else "Play"
        return RemoteAction(icon, title, title, intent)
    }
}

internal tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
