package app.zelefin.client.push

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import app.zelefin.client.BuildConfig
import app.zelefin.client.MainActivity
import app.zelefin.client.R
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import java.util.UUID
import kotlin.coroutines.resume
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine

/** Android side of iOS `PushNotificationCenter`: Firebase token, alert channel, and tap routing. */
object ZelefinPush {
    /** Must match the relay's `FCM_CHANNEL_ID`. */
    const val CHANNEL_ID = "zelefin_alerts"
    const val PLATFORM = "android"

    private const val PREFS = "zelefin.push"
    private const val TOKEN_KEY = "token"
    private const val DEVICE_ID_KEY = "device-id"
    private const val ENABLED_KEY = "enabled"
    private const val ASKED_KEY = "permission-asked"
    private val ITEM_KEYS = listOf("itemId", "itemID", "id")

    private val _tokens = MutableSharedFlow<String>(replay = 1, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    /** New Firebase tokens, for registering with the Zelefin plugin (iOS `zelefinPushTokenReady`). */
    val tokens: SharedFlow<String> = _tokens.asSharedFlow()

    private val _openItem = MutableStateFlow<String?>(null)
    /** Item ID from a tapped alert, until the app opens it (iOS `zelefinPushOpenItem`). */
    val openItem: StateFlow<String?> = _openItem.asStateFlow()

    /** False when the build has no `google-services.json`. */
    val isConfigured: Boolean get() = BuildConfig.PUSH_CONFIGURED

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun storedToken(context: Context): String? = prefs(context).getString(TOKEN_KEY, null)

    /** One UUID per install, like iOS `DeviceIdentity.deviceID()`. The plugin keys rows by it. */
    fun deviceId(context: Context): String {
        val prefs = prefs(context)
        prefs.getString(DEVICE_ID_KEY, null)?.let { return it }
        val id = UUID.randomUUID().toString().uppercase()
        prefs.edit().putString(DEVICE_ID_KEY, id).apply()
        return id
    }

    /** The Notifications master switch; on by default like iOS `LibraryAlertSettings`. */
    fun isEnabled(context: Context): Boolean = prefs(context).getBoolean(ENABLED_KEY, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(ENABLED_KEY, enabled).apply()
    }

    fun hasAskedPermission(context: Context): Boolean = prefs(context).getBoolean(ASKED_KEY, false)

    fun markAskedPermission(context: Context) {
        prefs(context).edit().putBoolean(ASKED_KEY, true).apply()
    }

    fun needsRuntimePermission(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    fun permissionGranted(context: Context): Boolean {
        if (needsRuntimePermission() &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Library alerts", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "New titles, streams, users online, and Seerr requests from your server"
        }
        manager.createNotificationChannel(channel)
    }

    /** Current Firebase token, cached for the next launch. Null when push is not configured or Play services fails. */
    suspend fun fetchToken(context: Context): String? {
        if (!isConfigured) return storedToken(context)
        if (FirebaseApp.getApps(context).isEmpty() && FirebaseApp.initializeApp(context) == null) return null
        val token = suspendCancellableCoroutine { continuation ->
            FirebaseMessaging.getInstance().token
                .addOnSuccessListener { continuation.resume(it) }
                .addOnFailureListener { continuation.resume(null) }
                .addOnCanceledListener { continuation.resume(null) }
        }
        if (!token.isNullOrBlank()) saveToken(context, token)
        return token?.takeIf { it.isNotBlank() } ?: storedToken(context)
    }

    internal fun didReceiveToken(context: Context, token: String) {
        saveToken(context, token)
        _tokens.tryEmit(token)
    }

    private fun saveToken(context: Context, token: String) {
        prefs(context).edit().putString(TOKEN_KEY, token).apply()
    }

    /** Reads the item ID from an alert tap. Firebase puts data keys into the launch intent's extras. */
    fun itemId(intent: Intent?): String? {
        val extras = intent?.extras ?: return null
        return ITEM_KEYS.firstNotNullOfOrNull { key -> extras.getString(key)?.trim()?.takeIf { it.isNotEmpty() } }
    }

    /** The plugin sends Jellyfin IDs as 32 hex digits; the SDK parses the dashed UUID form. */
    fun normalizedItemId(raw: String): String {
        val trimmed = raw.trim()
        if (trimmed.length != 32 || !trimmed.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) return trimmed
        return buildString {
            append(trimmed, 0, 8).append('-')
            append(trimmed, 8, 12).append('-')
            append(trimmed, 12, 16).append('-')
            append(trimmed, 16, 20).append('-')
            append(trimmed, 20, 32)
        }
    }

    fun handleLaunch(intent: Intent?) {
        itemId(intent)?.let { _openItem.value = it }
    }

    fun consumeOpenItem(id: String) {
        _openItem.compareAndSet(id, null)
    }

    /** Draws an alert while Zelefin is in the foreground; Android draws it itself while the app is closed. */
    fun show(context: Context, data: Map<String, String>, fallbackTitle: String?, fallbackBody: String?) {
        if (!isEnabled(context) || !permissionGranted(context)) return
        ensureChannel(context)
        val title = data["title"]?.takeIf { it.isNotBlank() } ?: fallbackTitle ?: "Zelefin"
        val subtitle = data["subtitle"]?.takeIf { it.isNotBlank() }
        val body = data["body"]?.takeIf { it.isNotBlank() } ?: fallbackBody.orEmpty()
        val text = if (subtitle != null) "$subtitle · $body" else body
        val itemId = ITEM_KEYS.firstNotNullOfOrNull { data[it]?.takeIf(String::isNotBlank) }
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            itemId?.let { putExtra("itemId", it) }
        }
        val requestCode = itemId?.hashCode() ?: System.currentTimeMillis().toInt()
        val pending = PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pending)
            .build()
        try {
            NotificationManagerCompat.from(context).notify(itemId, requestCode, notification)
        } catch (_: SecurityException) {
        }
    }
}
