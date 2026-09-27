package app.zelefin.client

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.SystemClock
import java.util.Locale

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
            val constrained = runCatching {
                manager.restrictBackgroundStatus == ConnectivityManager.RESTRICT_BACKGROUND_STATUS_ENABLED
            }.getOrDefault(false)
            return NetworkPathSnapshot(
                transport = transport,
                isExpensive = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED),
                isConstrained = constrained,
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

object AdaptiveBitratePolicy {
    const val UTILIZATION = 0.7
    const val CACHE_TTL_MILLIS = 90_000L
    const val PLAYBACK_SAMPLE_BYTES = 750_000
    const val SETTINGS_SAMPLE_BYTES = 2_500_000
    const val PLAYBACK_PROBE_TIMEOUT_MILLIS = 4_000L
    const val SETTINGS_PROBE_TIMEOUT_MILLIS = 20_000L

    /** Headroom so a title Direct Plays when it fits the pipe. */
    const val DIRECT_PLAY_MARGIN = 1.2

    fun budgetBitsPerSecond(measured: Int?, path: NetworkPathSnapshot): Int {
        val raw = measured ?: path.estimatedBitsPerSecond
        return maxOf(PlaybackQuality.Kbps420.bits, (raw * UTILIZATION).toInt())
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

    fun record(result: BitrateProbeResult) {
        lastProbe = result
    }

    fun cachedBudgetBitsPerSecond(path: NetworkPathSnapshot): Int {
        val measured = lastProbe?.takeIf { AdaptiveBitratePolicy.isCacheValid(it, path) }?.bitsPerSecond
        return AdaptiveBitratePolicy.budgetBitsPerSecond(measured, path)
    }

    /** Runs the short pre-playback probe unless a fresh one exists for this transport. */
    suspend fun refreshIfNeeded(context: Context, measure: suspend (Int, Long, NetworkTransport) -> BitrateProbeResult?) {
        if (!PlaybackPreferences.adaptiveBitrate(context)) return
        val path = NetworkPathSnapshot.current(context)
        if (AdaptiveBitratePolicy.isCacheValid(lastProbe, path)) return
        measure(AdaptiveBitratePolicy.PLAYBACK_SAMPLE_BYTES, AdaptiveBitratePolicy.PLAYBACK_PROBE_TIMEOUT_MILLIS, path.transport)
            ?.let(::record)
    }

    fun resolvedBitsPerSecond(context: Context, sourceBitrate: Int?): Int {
        val path = NetworkPathSnapshot.current(context)
        return AdaptiveBitratePolicy.quality(
            enabled = PlaybackPreferences.adaptiveBitrate(context),
            selected = PlaybackPreferences.selectedQuality(context),
            budgetBitsPerSecond = cachedBudgetBitsPerSecond(path),
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
data class LanguageTrack(val index: Int, val language: String?, val isSelected: Boolean)

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
        PlaybackPreferences.AUTOMATIC, "" -> "Automatic"
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
        return stream == want || stream.startsWith(want) || want.startsWith(stream) || alias(stream) == want
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

    /** Jellyfin and Silo usually tag streams with ISO 639-2 codes ("eng"), the picker stores 639-1 ("en"). */
    private fun alias(code: String): String? {
        if (code.length != 3) return null
        return runCatching {
            Locale.getAvailableLocales().firstOrNull { it.isO3Language == code }?.language
        }.getOrNull()
    }
}
