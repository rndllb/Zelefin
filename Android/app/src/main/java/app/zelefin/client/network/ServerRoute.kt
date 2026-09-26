package app.zelefin.client.network

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import androidx.core.content.ContextCompat
import app.zelefin.core.ServerUrl
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Sends requests meant for the saved (remote) server address to the local address while
 * this phone is on the home network. Every client shares [GatewayHttp.client], so one
 * interceptor covers the Jellyfin SDK, Silo, plugins, and artwork.
 */
object ServerRoute {
    @Volatile
    private var remote: HttpUrl? = null

    @Volatile
    private var local: HttpUrl? = null

    val activeLocal: String? get() = if (remote != null) local?.toString()?.trimEnd('/') else null

    fun set(remoteBase: String?, localBase: String?) {
        remote = remoteBase?.toHttpUrlOrNull()
        local = localBase?.toHttpUrlOrNull()
    }

    fun rewrite(url: String): String {
        val parsed = url.toHttpUrlOrNull() ?: return url
        return rewrite(parsed)?.toString() ?: url
    }

    val interceptor = Interceptor { chain ->
        val request = chain.request()
        val target = rewrite(request.url)
        if (target == null) chain.proceed(request) else chain.proceed(request.newBuilder().url(target).build())
    }

    private fun rewrite(url: HttpUrl): HttpUrl? {
        val from = remote ?: return null
        val to = local ?: return null
        if (url.scheme != from.scheme || !url.host.equals(from.host, ignoreCase = true) || url.port != from.port) return null
        val prefix = from.encodedPath.trimEnd('/')
        val path = url.encodedPath
        if (prefix.isNotEmpty() && path != prefix && !path.startsWith("$prefix/")) return null
        val rest = path.removePrefix(prefix)
        val joined = (to.encodedPath.trimEnd('/') + rest).ifEmpty { "/" }
        return url.newBuilder().scheme(to.scheme).host(to.host).port(to.port).encodedPath(joined).build()
    }
}

data class HomeNetworkProfile(
    val localUrl: String = "",
    val autoSwitch: Boolean = false,
    val homeSsids: List<String> = emptyList(),
)

class HomeNetworkStore(context: Context) {
    private val prefs = context.getSharedPreferences("zelefin.network", Context.MODE_PRIVATE)

    fun load(accountId: String): HomeNetworkProfile = HomeNetworkProfile(
        localUrl = prefs.getString("$accountId|local", "").orEmpty(),
        autoSwitch = prefs.getBoolean("$accountId|auto", false),
        homeSsids = prefs.getString("$accountId|ssids", "").orEmpty().split('\n').filter { it.isNotBlank() },
    )

    fun save(accountId: String, profile: HomeNetworkProfile) {
        prefs.edit()
            .putString("$accountId|local", profile.localUrl.trim())
            .putBoolean("$accountId|auto", profile.autoSwitch)
            .putString("$accountId|ssids", profile.homeSsids.joinToString("\n"))
            .apply()
    }

    fun remove(accountId: String) {
        prefs.edit().remove("$accountId|local").remove("$accountId|auto").remove("$accountId|ssids").apply()
    }
}

object HomeNetwork {
    private val probeClient = OkHttpClient.Builder()
        .addInterceptor { chain ->
            val headers = GatewayCredentials.headers()
            chain.proceed(chain.request().newBuilder().apply { headers.forEach { (k, v) -> header(k, v) } }.build())
        }
        .connectTimeout(1500, TimeUnit.MILLISECONDS)
        .readTimeout(2000, TimeUnit.MILLISECONDS)
        .callTimeout(3000, TimeUnit.MILLISECONDS)
        .followRedirects(false)
        .build()

    fun normalizedLocal(raw: String): String? =
        raw.trim().takeIf { it.isNotEmpty() }?.let { runCatching { ServerUrl.normalizeLanAddress(it) }.getOrNull() }

    fun hasLocationPermission(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun onLocalNetwork(context: Context): Boolean {
        val connectivity = context.getSystemService(ConnectivityManager::class.java) ?: return false
        val caps = connectivity.getNetworkCapabilities(connectivity.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) || caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)
    }

    /** Android only reports the network name with location permission and Location turned on. */
    @Suppress("DEPRECATION")
    fun currentSsid(context: Context): String? {
        if (!hasLocationPermission(context)) return null
        val wifi = context.applicationContext.getSystemService(WifiManager::class.java) ?: return null
        val raw = wifi.connectionInfo?.ssid?.trim()?.removeSurrounding("\"") ?: return null
        return raw.takeIf { it.isNotBlank() && it != WifiManager.UNKNOWN_SSID }
    }

    fun isHome(ssid: String, list: List<String>): Boolean = list.any { it.equals(ssid, ignoreCase = true) }

    fun adding(ssid: String, list: List<String>): List<String> {
        val trimmed = ssid.trim()
        if (trimmed.isEmpty() || isHome(trimmed, list)) return list
        return list + trimmed
    }

    /** The local base URL to use right now, or null to stay on the remote address. */
    suspend fun resolve(context: Context, profile: HomeNetworkProfile): String? {
        if (!profile.autoSwitch) return null
        val local = normalizedLocal(profile.localUrl) ?: return null
        if (!onLocalNetwork(context)) return null
        val ssid = currentSsid(context)
        if (profile.homeSsids.isNotEmpty() && ssid != null && !isHome(ssid, profile.homeSsids)) return null
        return if (reachable(local)) local else null
    }

    suspend fun reachable(base: String): Boolean = withContext(Dispatchers.IO) {
        val url = ServerUrl.join(base, "/System/Info/Public") ?: return@withContext false
        runCatching {
            probeClient.newCall(Request.Builder().url(url).get().build()).execute().use { it.code < 500 }
        }.getOrDefault(false)
    }
}
