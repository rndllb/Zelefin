package app.zelefin.client.downloads

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import app.zelefin.client.MainActivity
import app.zelefin.client.R
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch

/** Keeps the app alive while transfers run, with a quiet progress notification. */
class DownloadService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var watching = false
    private var lastPercent = -1
    private var lastTitle: String? = null
    private var lastPost = 0L

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel(this)
        val transfers = ZelefinDownloads.state.value.progress.values.toList()
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        runCatching { ServiceCompat.startForeground(this, NotificationId, notification(transfers), type) }
            .onFailure {
                stopSelf()
                return START_NOT_STICKY
            }
        if (transfers.isEmpty()) {
            finish()
            return START_NOT_STICKY
        }
        if (!watching) {
            watching = true
            scope.launch {
                ZelefinDownloads.state.map { it.progress.values.toList() }.collect { current ->
                    if (current.isEmpty()) finish() else update(current)
                }
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    private fun update(transfers: List<DownloadProgress>) {
        val lead = transfers.first()
        val percent = (lead.fraction * 100).roundToInt()
        val title = lead.item.id
        val now = System.currentTimeMillis()
        if (title == lastTitle && percent == lastPercent && now - lastPost < 5_000) return
        if (title == lastTitle && now - lastPost < 1_000) return
        lastTitle = title
        lastPercent = percent
        lastPost = now
        getSystemService(NotificationManager::class.java)?.notify(NotificationId, notification(transfers))
    }

    private fun finish() {
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun notification(transfers: List<DownloadProgress>): Notification {
        val lead = transfers.firstOrNull()
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val label = lead?.item?.let(DownloadPrompts::label)
        val percent = lead?.percentLabel
        val title = when {
            label == null -> "Downloading"
            percent != null -> "Downloading $label · $percent"
            else -> "Downloading $label"
        }
        val builder = NotificationCompat.Builder(this, ChannelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
        if (lead != null) {
            builder.setContentText(if (transfers.size > 1) "${transfers.size} downloads" else lead.sizeLabel(this))
            builder.setProgress(100, (lead.fraction * 100).roundToInt(), lead.bytesExpected <= 0)
        }
        return builder.build()
    }

    companion object {
        private const val ChannelId = "downloads"
        private const val NotificationId = 4107

        fun start(context: Context) {
            runCatching { ContextCompat.startForegroundService(context, Intent(context, DownloadService::class.java)) }
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(ChannelId) != null) return
            manager.createNotificationChannel(
                NotificationChannel(ChannelId, "Downloads", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Progress while titles download for offline playback."
                    setShowBadge(false)
                },
            )
        }
    }
}
