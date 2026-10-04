package app.zelefin.client.session

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import app.zelefin.client.push.ZelefinPush
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Shows a Jellyfin user message in-app when Zelefin is open. Closed-app delivery is the plugin push. */
object SessionMessageCenter : Application.ActivityLifecycleCallbacks {
    private val _message = MutableStateFlow<SessionDisplayMessage?>(null)
    val message: StateFlow<SessionDisplayMessage?> = _message.asStateFlow()
    private val startedActivities = AtomicInteger(0)
    private var lastFingerprint: String? = null
    private var lastPresentedAt = 0L

    fun install(application: Application) {
        application.registerActivityLifecycleCallbacks(this)
    }

    fun present(context: Context, message: SessionDisplayMessage, fromPush: Boolean = false) {
        if (isDuplicate(message)) return
        if (isAppForeground()) {
            _message.value = message
            return
        }
        if (!fromPush || !ZelefinPush.isEnabled(context)) return
        ZelefinPush.showSessionMessage(context, message)
    }

    private fun isDuplicate(message: SessionDisplayMessage): Boolean {
        val fingerprint = "${message.header}\n${message.text}"
        val now = System.currentTimeMillis()
        if (lastFingerprint == fingerprint && now - lastPresentedAt < 3_000) return true
        lastFingerprint = fingerprint
        lastPresentedAt = now
        return false
    }

    fun dismiss() {
        _message.value = null
    }

    private fun isAppForeground(): Boolean = startedActivities.get() > 0

    override fun onActivityStarted(activity: Activity) {
        startedActivities.incrementAndGet()
    }

    override fun onActivityStopped(activity: Activity) {
        startedActivities.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
    override fun onActivityResumed(activity: Activity) = Unit
    override fun onActivityPaused(activity: Activity) = Unit
    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
    override fun onActivityDestroyed(activity: Activity) = Unit
}
