package app.zelefin.client

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.ZelefinException
import java.util.Locale
import java.util.concurrent.TimeUnit
import okhttp3.Request

/** Mirrors iOS `PlaybackQuality`. [bits] of 0 is Auto, which streams at the device ceiling. */
enum class PlaybackQuality(val bits: Int, val title: String) {
    Auto(0, "Auto"),
    Mbps120(120_000_000, "120 Mbps"),
    Mbps80(80_000_000, "80 Mbps"),
    Mbps60(60_000_000, "60 Mbps"),
    Mbps40(40_000_000, "40 Mbps"),
    Mbps20(20_000_000, "20 Mbps"),
    Mbps15(15_000_000, "15 Mbps"),
    Mbps10(10_000_000, "10 Mbps"),
    Mbps8(8_000_000, "8 Mbps"),
    Mbps6(6_000_000, "6 Mbps"),
    Mbps4(4_000_000, "4 Mbps"),
    Mbps3(3_000_000, "3 Mbps"),
    Mbps2(2_000_000, "2 Mbps"),
    Kbps1500(1_500_000, "1.5 Mbps"),
    Mbps1(1_000_000, "1 Mbps"),
    Kbps720(720_000, "720 kbps"),
    Kbps420(420_000, "420 kbps");

    val bitsPerSecond: Int get() = if (this == Auto) MAX_BITRATE else bits

    companion object {
        const val MAX_BITRATE = 200_000_000

        /** Ascending, without Auto. */
        val ladder: List<PlaybackQuality> = entries.filter { it != Auto }.sortedBy { it.bits }

        fun resolved(stored: Int): PlaybackQuality = entries.firstOrNull { it.bits == stored } ?: Auto

        fun atOrBelow(bitsPerSecond: Int): PlaybackQuality {
            if (bitsPerSecond >= Mbps80.bits) return Auto
            return ladder.lastOrNull { it.bits <= bitsPerSecond } ?: Kbps420
        }

        fun stricter(lhs: PlaybackQuality, rhs: PlaybackQuality): PlaybackQuality =
            if (lhs.bitsPerSecond <= rhs.bitsPerSecond) lhs else rhs

        /** Next lower rung. From Auto this drops below the file bitrate so the server transcodes. */
        fun stepDown(current: PlaybackQuality, sourceBitsPerSecond: Int?): PlaybackQuality? {
            if (current == Auto || (sourceBitsPerSecond != null && current.bitsPerSecond >= sourceBitsPerSecond)) {
                val limit = sourceBitsPerSecond?.coerceAtLeast(1) ?: Mbps40.bits
                return ladder.lastOrNull { it.bits < limit }
            }
            return ladder.lastOrNull { it.bits < current.bits }
        }

        /** One rung up, or Auto when that rung can carry the file again. */
        fun stepUp(current: PlaybackQuality, sourceBitsPerSecond: Int?, ceiling: PlaybackQuality): PlaybackQuality? {
            if (current == Auto) return null
            var candidate = ladder.firstOrNull { it.bits > current.bits } ?: Auto
            if (ceiling != Auto) candidate = stricter(candidate, ceiling)
            if (ceiling == Auto && AdaptiveBitratePolicy.fitsDirectPlay(sourceBitsPerSecond, candidate.bitsPerSecond)) {
                candidate = Auto
            }
            return if (candidate.bitsPerSecond > current.bitsPerSecond) candidate else null
        }
    }
}

enum class NetworkTransport(val title: String) {
    Wifi("Wi-Fi"),
    Cellular("Cellular"),
    Wired("Ethernet"),
    Other("Network"),
}

data class NetworkPathSnapshot(
    val transport: NetworkTransport,
    val isExpensive: Boolean,
    val isConstrained: Boolean,
    val isSatisfied: Boolean,
    /** `Network.networkHandle`: a hotspot and home Wi-Fi share a transport but not a network. */
    val networkId: Long = 0,
) {
    /** Conservative budget when this connection has not been measured yet. */
    val estimatedBitsPerSecond: Int
        get() {
            if (!isSatisfied || isConstrained) return PlaybackQuality.Kbps720.bits
            return when (transport) {
                NetworkTransport.Wired -> PlaybackQuality.Auto.bitsPerSecond
                NetworkTransport.Wifi -> if (isExpensive) PlaybackQuality.Mbps8.bits else PlaybackQuality.Mbps20.bits
                NetworkTransport.Cellular -> if (isExpensive) PlaybackQuality.Mbps3.bits else PlaybackQuality.Mbps6.bits
                NetworkTransport.Other -> if (isExpensive) PlaybackQuality.Mbps3.bits else PlaybackQuality.Mbps10.bits
            }
        }

    companion object {
        fun current(context: Context): NetworkPathSnapshot {
            val manager = context.getSystemService(ConnectivityManager::class.java)
                ?: return NetworkPathSnapshot(NetworkTransport.Other, false, false, false)
            val caps = runCatching { manager.getNetworkCapabilities(manager.activeNetwork) }.getOrNull()
                ?: return NetworkPathSnapshot(NetworkTransport.Other, false, false, false)
            val transport = when {
                caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> NetworkTransport.Wired
                caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> NetworkTransport.Wifi
                caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> NetworkTransport.Cellular
                else -> NetworkTransport.Other
            }
            return NetworkPathSnapshot(
                networkId = manager.activeNetwork?.networkHandle ?: 0,
                transport = transport,
                isExpensive = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
                // Data Saver only limits background transfers. Playback is in the foreground, so
                // that flag must not collapse the cap to 720 kbps and force a transcode.
                isConstrained = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED),
                isSatisfied = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET),
            )
        }
    }
}

data class BitrateProbeResult(
    val bitsPerSecond: Int,
    val bytes: Int,
    val elapsedSeconds: Double,
    val transport: NetworkTransport,
    val measuredAtMillis: Long,
) {
    companion object {
        fun from(bytes: Int, elapsedNanos: Long, transport: NetworkTransport): BitrateProbeResult {
            val elapsed = (elapsedNanos / 1_000_000_000.0).coerceAtLeast(0.05)
            return BitrateProbeResult(
                bitsPerSecond = ((bytes * 8.0) / elapsed).toInt().coerceAtLeast(0),
                bytes = bytes,
                elapsedSeconds = elapsed,
                transport = transport,
                measuredAtMillis = SystemClock.elapsedRealtime(),
            )
        }
    }
}

/** Times a `/Playback/BitrateTest` download, like iOS `measureStreamingBitrate`. Null when too little arrived. */
internal fun timedBitrateDownload(
    request: Request,
    timeoutMillis: Long,
    transport: NetworkTransport,
    serverName: String,
): BitrateProbeResult? {
    val client = GatewayHttp.client.newBuilder()
        .callTimeout(timeoutMillis, TimeUnit.MILLISECONDS)
        .build()
    val response = runCatching { client.newCall(request).execute() }.getOrNull() ?: return null
    // Timed from the headers, so DNS, TLS and the server's time to first byte do not count
    // against the link: on a small sample they made a fast remote connection read as slow.
    val started = System.nanoTime()
    response.use {
        if (!it.isSuccessful) {
            throw ZelefinException.server("$serverName did not send the test file (HTTP ${it.code}). Check the connection and try again.")
        }
        val bytes = runCatching { it.body?.bytes()?.size ?: 0 }.getOrDefault(0)
        if (bytes < 16_000) return null
        return BitrateProbeResult.from(bytes, System.nanoTime() - started, transport)
    }
}

object AdaptiveBitratePolicy {
    const val UTILIZATION = 0.7

    /**
     * Cellular and metered links swing more than Wi-Fi at home, so playback claims less of what was
     * measured and lets the live monitor step up once the buffer proves the link holds.
     */
    const val METERED_UTILIZATION = 0.5
    const val CACHE_TTL_MILLIS = 90_000L
    const val PLAYBACK_SAMPLE_BYTES = 750_000
    const val SETTINGS_SAMPLE_BYTES = 2_500_000
    const val PLAYBACK_PROBE_TIMEOUT_MILLIS = 4_000L
    const val SETTINGS_PROBE_TIMEOUT_MILLIS = 20_000L

    /** Headroom so a title Direct Plays when it fits the pipe. */
    const val DIRECT_PLAY_MARGIN = 1.2

    fun budgetBitsPerSecond(measured: Int?, path: NetworkPathSnapshot): Int {
        val raw = measured ?: path.estimatedBitsPerSecond
        val share = if (path.transport == NetworkTransport.Cellular || path.isExpensive || path.isConstrained) {
            METERED_UTILIZATION
        } else {
            UTILIZATION
        }
        return maxOf(PlaybackQuality.Kbps420.bits, (raw * share).toInt())
    }

    /**
     * A sample that runs out its whole timeout is itself a measurement: the link moved at most
     * [bytes] in [timeoutMillis]. Without it a link too slow to finish the sample had no reading at
     * all and Auto Direct Played the original over it. Quick failures carry no speed and stay null.
     */
    fun timedOutProbe(bytes: Int, timeoutMillis: Long, elapsedMillis: Long, transport: NetworkTransport): BitrateProbeResult? {
        if (timeoutMillis <= 0 || elapsedMillis < timeoutMillis * 0.9) return null
        return BitrateProbeResult.from(bytes, maxOf(elapsedMillis, timeoutMillis) * 1_000_000, transport).copy(bytes = 0)
    }

    fun quality(
        enabled: Boolean,
        selected: PlaybackQuality,
        budgetBitsPerSecond: Int,
        sourceBitsPerSecond: Int?,
    ): PlaybackQuality {
        if (!enabled) return selected
        val network = if (fitsDirectPlay(sourceBitsPerSecond, budgetBitsPerSecond)) {
            PlaybackQuality.Auto
        } else {
            PlaybackQuality.atOrBelow(budgetBitsPerSecond)
        }
        return PlaybackQuality.stricter(network, selected)
    }

    fun fitsDirectPlay(sourceBitsPerSecond: Int?, budgetBitsPerSecond: Int): Boolean {
        if (sourceBitsPerSecond == null || sourceBitsPerSecond <= 0) {
            return budgetBitsPerSecond >= PlaybackQuality.Mbps40.bits
        }
        return sourceBitsPerSecond * DIRECT_PLAY_MARGIN <= budgetBitsPerSecond
    }

    fun isCacheValid(result: BitrateProbeResult?, path: NetworkPathSnapshot, now: Long = SystemClock.elapsedRealtime()): Boolean {
        if (result == null || result.transport != path.transport) return false
        return now - result.measuredAtMillis < CACHE_TTL_MILLIS
    }
}

/** Process-wide probe cache, like iOS `AdaptiveBitrateStore`. */
object AdaptiveBitrateStore {
    @Volatile
    var lastProbe: BitrateProbeResult? = null
        private set

    /** The network [lastProbe] was taken on; a sample only describes that one. */
    @Volatile
    private var probeNetworkId: Long = 0

    fun record(result: BitrateProbeResult, path: NetworkPathSnapshot) {
        lastProbe = result
        probeNetworkId = path.networkId
    }

    private fun validProbe(path: NetworkPathSnapshot): BitrateProbeResult? =
        lastProbe?.takeIf { probeNetworkId == path.networkId && AdaptiveBitratePolicy.isCacheValid(it, path) }

    fun cachedBudgetBitsPerSecond(path: NetworkPathSnapshot): Int =
        AdaptiveBitratePolicy.budgetBitsPerSecond(validProbe(path)?.bitsPerSecond, path)

    /** Runs the short pre-playback probe unless a fresh one exists for this network. */
    suspend fun refreshIfNeeded(context: Context, measure: suspend (Int, Long, NetworkTransport) -> BitrateProbeResult?) {
        if (!PlaybackPreferences.adaptiveBitrate(context)) return
        val path = NetworkPathSnapshot.current(context)
        if (validProbe(path) != null) return
        val bytes = AdaptiveBitratePolicy.PLAYBACK_SAMPLE_BYTES
        val timeout = AdaptiveBitratePolicy.PLAYBACK_PROBE_TIMEOUT_MILLIS
        val started = SystemClock.elapsedRealtime()
        val measured = runCatching { measure(bytes, timeout, path.transport) }.getOrNull()
        val result = measured ?: AdaptiveBitratePolicy.timedOutProbe(
            bytes,
            timeout,
            SystemClock.elapsedRealtime() - started,
            path.transport,
        )
        result?.let { record(it, path) }
    }

    fun resolvedBitsPerSecond(context: Context, sourceBitrate: Int?): Int {
        val selected = PlaybackPreferences.selectedQuality(context)
        if (!PlaybackPreferences.adaptiveBitrate(context)) return selected.bitsPerSecond
        val path = NetworkPathSnapshot.current(context)
        val measured = validProbe(path)?.bitsPerSecond
            ?: return selected.bitsPerSecond
        return AdaptiveBitratePolicy.quality(
            enabled = true,
            selected = selected,
            budgetBitsPerSecond = AdaptiveBitratePolicy.budgetBitsPerSecond(measured, path),
            sourceBitsPerSecond = sourceBitrate,
        ).bitsPerSecond
    }

    fun recommendedQuality(context: Context, result: BitrateProbeResult): PlaybackQuality {
        val path = NetworkPathSnapshot.current(context)
        return AdaptiveBitratePolicy.quality(
            enabled = true,
            selected = PlaybackPreferences.selectedQuality(context),
            budgetBitsPerSecond = AdaptiveBitratePolicy.budgetBitsPerSecond(result.bitsPerSecond, path),
            sourceBitsPerSecond = null,
        )
    }
}

enum class LiveAdaptiveAction { None, StepDown, StepUp }

data class LiveAdaptiveSample(
    val hasFirstFrame: Boolean,
    val isPaused: Boolean,
    val isSeeking: Boolean,
    val isRebuffering: Boolean,
    val bufferedAheadSeconds: Double,
    val current: PlaybackQuality,
    val ceiling: PlaybackQuality,
    val sourceBitsPerSecond: Int?,
)

/** Mirrors iOS `LiveAdaptiveTracker`: step down on sustained rebuffering, up after a long healthy stretch. */
class LiveAdaptiveTracker(private val startedAt: Long = SystemClock.elapsedRealtime()) {
    private var rebufferStartedAt: Long? = null
    private var healthySince: Long? = null

    fun action(now: Long, sample: LiveAdaptiveSample): LiveAdaptiveAction {
        if (!sample.hasFirstFrame || sample.isPaused) return LiveAdaptiveAction.None
        if (sample.isSeeking) {
            rebufferStartedAt = null
            healthySince = null
            return LiveAdaptiveAction.None
        }
        if (now - startedAt < STARTUP_GRACE_MILLIS) return LiveAdaptiveAction.None

        if (sample.isRebuffering) {
            healthySince = null
            val began = rebufferStartedAt ?: now
            rebufferStartedAt = began
            if (now - began < REBUFFER_CONFIRM_MILLIS) return LiveAdaptiveAction.None
            if (PlaybackQuality.stepDown(sample.current, sample.sourceBitsPerSecond) == null) return LiveAdaptiveAction.None
            rebufferStartedAt = null
            return LiveAdaptiveAction.StepDown
        }

        rebufferStartedAt = null
        if (sample.bufferedAheadSeconds >= HEALTHY_BUFFER_SECONDS) {
            val began = healthySince ?: now
            healthySince = began
            if (now - began < HEALTHY_HOLD_MILLIS) return LiveAdaptiveAction.None
            if (PlaybackQuality.stepUp(sample.current, sample.sourceBitsPerSecond, sample.ceiling) == null) return LiveAdaptiveAction.None
            healthySince = null
            return LiveAdaptiveAction.StepUp
        }
        healthySince = null
        return LiveAdaptiveAction.None
    }

    companion object {
        const val STARTUP_GRACE_MILLIS = 8_000L
        const val REBUFFER_CONFIRM_MILLIS = 1_800L
        const val HEALTHY_BUFFER_SECONDS = 12.0
        const val HEALTHY_HOLD_MILLIS = 20_000L
    }
}

/** A server-side audio or subtitle stream, as far as language preference needs to know. */
data class LanguageTrack(
    val index: Int,
    val language: String?,
    val isSelected: Boolean,
    val title: String = "",
    val isHearingImpaired: Boolean = false,
)

/** Mirrors iOS `PlaybackLanguage`. */
object PlaybackLanguage {
    private val common = listOf(
        "en", "es", "fr", "de", "it", "pt", "nl", "sv", "nb", "da", "fi", "pl", "cs", "hu", "ro",
        "el", "tr", "ru", "uk", "ar", "he", "hi", "ja", "ko", "zh",
    )

    fun choices(context: Context): List<String> {
        val locales = context.resources.configuration.locales
        val device = (0 until locales.size()).map { normalize(locales[it].language) }
        return (device + common).filter { it.isNotEmpty() }.distinct()
    }

    fun displayName(code: String): String = when (code) {
        PlaybackPreferences.AUTOMATIC -> "Automatic"
        "" -> "Any Language"
        PlaybackPreferences.OFF -> "Off"
        else -> {
            val name = Locale.forLanguageTag(code).getDisplayLanguage(Locale.getDefault()).trim()
            if (name.isEmpty() || name.equals(code, ignoreCase = true)) {
                code.uppercase()
            } else {
                name.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
            }
        }
    }

    fun normalize(raw: String?): String {
        val trimmed = raw?.trim()?.lowercase().orEmpty()
        if (trimmed.isEmpty()) return ""
        return trimmed.replace('_', '-').split('-').firstOrNull()?.ifEmpty { null } ?: trimmed
    }

    fun matches(streamLanguage: String?, preference: String): Boolean {
        val stream = normalize(streamLanguage)
        val want = normalize(preference)
        if (stream.isEmpty() || want.isEmpty()) return false
        return stream == want || stream.startsWith(want) || want.startsWith(stream) || alias(stream) == want || alias(want) == stream
    }

    fun matchesLabel(label: String?, language: String?, preference: String): Boolean {
        if (preference.isEmpty()) return false
        if (matches(language, preference)) return true
        if (matches(label, preference)) return true
        val names = listOfNotNull(
            normalize(preference),
            alias(normalize(preference)),
            displayName(preference).lowercase(),
            alias(normalize(preference))?.let { displayName(it).lowercase() },
        ).filter { it.isNotEmpty() && it != "any language" && it != "automatic" }
        val text = label.orEmpty().lowercase()
        return names.any { text.contains(it) }
    }

    fun audioIndex(tracks: List<LanguageTrack>, preference: String): Int? {
        val fallback = tracks.firstOrNull { it.isSelected }?.index ?: tracks.firstOrNull()?.index
        if (preference == PlaybackPreferences.AUTOMATIC || preference.isEmpty()) return fallback
        return tracks.firstOrNull { matches(it.language, preference) }?.index ?: fallback
    }

    fun subtitleIndex(tracks: List<LanguageTrack>, preference: String): Int? {
        if (preference == PlaybackPreferences.OFF) return -1
        val fallback = tracks.firstOrNull { it.isSelected }?.index
        if (preference == PlaybackPreferences.AUTOMATIC || preference.isEmpty()) return fallback
        return tracks.firstOrNull { matches(it.language, preference) }?.index ?: fallback
    }

    fun isSDH(track: LanguageTrack): Boolean {
        if (track.isHearingImpaired) return true
        val title = track.title.lowercase()
        return title.contains("sdh") || title.contains("cc") || title.contains("caption") || title.contains("hearing")
    }

    /**
     * Jellyfin's Always mode only matches a preferred language. An empty "Any Language"
     * preference comes back as no subtitle, which this app used to treat as Off.
     */
    fun startingSubtitleIndex(
        tracks: List<LanguageTrack>,
        serverIndex: Int?,
        mode: org.jellyfin.sdk.model.api.SubtitlePlaybackMode,
        preferredLanguage: String,
        audioLanguage: String?,
        preferSdh: Boolean,
        deviceLanguage: String,
        forcedByUser: Boolean = false,
    ): Int? {
        if (forcedByUser) return serverIndex?.takeIf { it >= 0 }
        val wanted = preferredLanguage.ifBlank { deviceLanguage }
        val resolved = serverIndex?.takeIf { it >= 0 }?.let { index ->
            if (preferSdh) pick(tracks, wanted, preferSdh = true) ?: index else index
        }
        if (resolved != null) return resolved
        return when (mode) {
            org.jellyfin.sdk.model.api.SubtitlePlaybackMode.ALWAYS ->
                pick(tracks, wanted, preferSdh) ?: tracks.firstOrNull()?.index
            org.jellyfin.sdk.model.api.SubtitlePlaybackMode.SMART -> {
                if (wanted.isNotEmpty() && matches(audioLanguage, wanted)) null
                else pick(tracks, wanted, preferSdh)
            }
            else -> null
        }
    }

    private fun pick(tracks: List<LanguageTrack>, language: String, preferSdh: Boolean): Int? {
        val sdh = tracks.filter(::isSDH)
        val pool = if (preferSdh && sdh.isNotEmpty()) sdh else tracks
        if (language.isNotEmpty()) {
            return pool.firstOrNull { matches(it.language, language) }?.index
                ?: tracks.firstOrNull { matches(it.language, language) }?.index
        }
        return pool.firstOrNull()?.index
    }

    /** Jellyfin servers usually tag streams with ISO 639-2 codes ("eng"), the picker stores 639-1 ("en"). */
    fun alias(code: String): String? {
        if (code.length != 3) return null
        return runCatching {
            Locale.getAvailableLocales().firstOrNull { it.isO3Language == code }?.language?.ifEmpty { null }
        }.getOrNull()
    }
}
