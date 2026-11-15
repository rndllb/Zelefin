package app.zelefin.client.push

import android.content.Context
import android.text.format.DateFormat
import java.util.Calendar
import java.util.concurrent.atomic.AtomicInteger

/**
 * Quiet hours and mute-while-open / mute-while-playing.
 * Matches iOS `LibraryAlertSettings`. In-app admin messages stay on the
 * [app.zelefin.client.session.SessionMessageCenter] path and are not decided here.
 */
object NotificationPreferences {
    private const val PREFS = "zelefin.push"
    private const val QUIET_HOURS_ENABLED_KEY = "zelefin.alerts.quiet-hours.enabled"
    private const val QUIET_HOURS_START_KEY = "zelefin.alerts.quiet-hours.start"
    private const val QUIET_HOURS_END_KEY = "zelefin.alerts.quiet-hours.end"
    private const val MUTE_WHILE_OPEN_KEY = "zelefin.alerts.mute-while-open"
    private const val MUTE_WHILE_PLAYING_KEY = "zelefin.alerts.mute-while-playing"

    /** Minutes from midnight. Default 22:00. */
    const val DEFAULT_QUIET_START_MINUTES = 22 * 60

    /** Minutes from midnight. Default 07:00. */
    const val DEFAULT_QUIET_END_MINUTES = 7 * 60

    private const val DAY_MINUTES = 24 * 60

    /** Set while a player screen is in the foreground. Nested players share one count. */
    @Volatile
    var isPlaybackActive: Boolean = false
        private set

    /** Set from [androidx.lifecycle.ProcessLifecycleOwner] ON_START / ON_STOP. */
    @Volatile
    var isAppForeground: Boolean = false
        private set

    private val playbackHolders = AtomicInteger(0)

    @Volatile
    private var playbackInForeground = false

    /**
     * `true` while a player screen is entered, `false` when that screen leaves.
     * Calls nest, so ExoPlayer and MPV can both hold the flag until the last one disposes.
     */
    fun setPlaybackActive(active: Boolean) {
        if (active) {
            playbackHolders.incrementAndGet()
            playbackInForeground = true
        } else {
            playbackHolders.updateAndGet { current -> (current - 1).coerceAtLeast(0) }
        }
        publishPlayback()
    }

    /** The activity behind the player stopped or started again. Does not change the holder count. */
    fun setPlaybackInForeground(started: Boolean) {
        playbackInForeground = started
        publishPlayback()
    }

    private fun publishPlayback() {
        isPlaybackActive = playbackHolders.get() > 0 && playbackInForeground
    }

    fun setAppForeground(foreground: Boolean) {
        isAppForeground = foreground
    }

    fun quietHoursEnabled(context: Context): Boolean =
        prefs(context).getBoolean(QUIET_HOURS_ENABLED_KEY, false)

    fun setQuietHoursEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(QUIET_HOURS_ENABLED_KEY, enabled).apply()
    }

    fun quietHoursStartMinutes(context: Context): Int =
        clampedMinutes(prefs(context).getInt(QUIET_HOURS_START_KEY, DEFAULT_QUIET_START_MINUTES))

    fun setQuietHoursStartMinutes(context: Context, minutes: Int) {
        prefs(context).edit().putInt(QUIET_HOURS_START_KEY, clampedMinutes(minutes)).apply()
    }

    fun quietHoursEndMinutes(context: Context): Int =
        clampedMinutes(prefs(context).getInt(QUIET_HOURS_END_KEY, DEFAULT_QUIET_END_MINUTES))

    fun setQuietHoursEndMinutes(context: Context, minutes: Int) {
        prefs(context).edit().putInt(QUIET_HOURS_END_KEY, clampedMinutes(minutes)).apply()
    }

    /** When on, lock-screen banners are not shown while Zelefin is in the foreground. */
    fun muteWhileOpen(context: Context): Boolean =
        prefs(context).getBoolean(MUTE_WHILE_OPEN_KEY, true)

    fun setMuteWhileOpen(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(MUTE_WHILE_OPEN_KEY, enabled).apply()
    }

    /** When on, lock-screen banners are not shown while this device is playing in Zelefin. */
    fun muteWhilePlaying(context: Context): Boolean =
        prefs(context).getBoolean(MUTE_WHILE_PLAYING_KEY, true)

    fun setMuteWhilePlaying(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(MUTE_WHILE_PLAYING_KEY, enabled).apply()
    }

    /**
     * True when a banner should be held back right now (quiet hours / open / playing).
     * Master-off matches iOS: a disabled switch also suppresses presentation.
     */
    fun shouldSuppressPresentation(context: Context): Boolean {
        if (!ZelefinPush.isEnabled(context)) return true
        if (muteWhilePlaying(context) && isPlaybackActive) return true
        if (muteWhileOpen(context) && isAppForeground) return true
        if (quietHoursEnabled(context) && isInQuietHours(context)) return true
        return false
    }

    fun isInQuietHours(context: Context, now: Calendar = Calendar.getInstance()): Boolean {
        val minutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE)
        return isMinuteInQuietHours(minutes, quietHoursStartMinutes(context), quietHoursEndMinutes(context))
    }

    /** Supports overnight ranges (for example 22:00 → 07:00). Equal endpoints cover the whole day. */
    fun isMinuteInQuietHours(minutes: Int, start: Int, end: Int): Boolean {
        val minute = clampedMinutes(minutes)
        val from = clampedMinutes(start)
        val to = clampedMinutes(end)
        if (from == to) return true
        if (from < to) return minute >= from && minute < to
        return minute >= from || minute < to
    }

    fun timeLabel(context: Context, minutes: Int): String {
        val value = clampedMinutes(minutes)
        val calendar = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, value / 60)
            set(Calendar.MINUTE, value % 60)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        return DateFormat.getTimeFormat(context).format(calendar.time)
    }

    private fun clampedMinutes(value: Int): Int = ((value % DAY_MINUTES) + DAY_MINUTES) % DAY_MINUTES

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
