package app.zelefin.client

import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import okhttp3.Request

/**
 * Zelefin's own log: what the app did and what went wrong, kept on the device so a user can read it
 * in Settings → Log or send it to the developer. Tokens, passwords, and API keys are taken out of
 * every line before it's written, so a shared log never carries a sign-in. Mirrors iOS `ZelefinLog`.
 */
object ZelefinLog {
    enum class Level(val label: String) { Info("INFO"), Warning("WARN"), Error("ERROR") }

    /** Two files of this size: the current one, and the one before it. */
    private const val FILE_LIMIT = 1_000_000L

    private val writer = Executors.newSingleThreadExecutor { Thread(it, "zelefin-log").apply { isDaemon = true } }
    private val stamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)
    @Volatile private var folder: File? = null

    fun attach(context: Context) {
        folder = File(context.filesDir, "logs").apply { mkdirs() }
    }

    private val current: File? get() = folder?.let { File(it, "zelefin.log") }
    private val previous: File? get() = folder?.let { File(it, "zelefin.previous.log") }

    fun info(category: String, message: String) = write(Level.Info, category, message)
    fun warning(category: String, message: String) = write(Level.Warning, category, message)
    fun error(category: String, message: String) = write(Level.Error, category, message)

    fun write(level: Level, category: String, message: String) {
        val date = Date()
        val text = redact(message)
        writer.execute {
            val line = "${synchronized(stamp) { stamp.format(date) }} ${level.label} [$category] $text\n"
            append(line)
        }
    }

    /** The whole log, oldest first. */
    fun contents(): String = writer.submit<String> {
        (previous?.takeIf { it.exists() }?.readText().orEmpty()) + (current?.takeIf { it.exists() }?.readText().orEmpty())
    }.get()

    fun clear() {
        writer.submit {
            previous?.delete()
            current?.delete()
        }.get()
    }

    /** A text file to share: what the app, device, and server are, then the log. */
    fun exportFile(context: Context, header: String): File? = runCatching {
        val dir = File(context.cacheDir, "logs").apply { mkdirs() }
        val name = "Zelefin Log ${SimpleDateFormat("yyyy-MM-dd HH.mm", Locale.US).format(Date())}.txt"
        File(dir, name).apply {
            dir.listFiles()?.forEach { it.delete() }
            writeText(header + "\n\n" + contents())
        }
    }.getOrNull()

    private fun append(line: String) {
        val file = current ?: return
        val old = previous
        if (file.exists() && file.length() + line.length > FILE_LIMIT && old != null) {
            old.delete()
            file.renameTo(old)
        }
        runCatching { file.appendText(line) }
    }

    // Redaction

    private val secretPatterns = listOf(
        // Query items and form fields: api_key=…, X-Emby-Token=…, Pw=…, password=…
        Regex("""(?i)\b(api_?key|x-emby-token|x-mediabrowser-token|access_?token|token|pw|password|secret|client_secret)=([^&\s"',]+)""") to "$1=REDACTED",
        // JSON fields: "Pw":"…", "password": "…", "AccessToken":"…"
        Regex("""(?i)"(pw|password|accesstoken|access_token|token|api_?key|secret)"\s*:\s*"[^"]*"""") to "\"$1\":\"REDACTED\"",
        // Authorization headers: Bearer …, MediaBrowser … Token="…"
        Regex("""(?i)\bbearer\s+[A-Za-z0-9._~+/=-]+""") to "Bearer REDACTED",
        Regex("""(?i)\btoken="[^"]*"""") to "Token=\"REDACTED\"",
    )

    fun redact(text: String): String = secretPatterns.fold(text) { result, (pattern, replacement) ->
        pattern.replace(result, replacement)
    }

    /**
     * Answers that aren't failures: the live connection opening (101), and lookups where "not
     * found" is the answer: the sign-in check for a Silo address, and Intro Skipper's segments
     * for a title it hasn't analysed. Missing posters and logos are normal too.
     */
    fun isExpectedStatus(path: String, host: String, status: Int): Boolean = when (status) {
        101, 304 -> true
        404 -> path.contains("/Images/") || host == "image.tmdb.org" || expectedMisses.any(path::endsWith)
        else -> false
    }

    private val expectedMisses = listOf(
        "/api/v2/system/setup",
        "/api/v1/health",
        "/IntroSkipperSegments",
        "/Timestamps",
        "/IntroTimestamps",
    )

    /** A request for the log: its method, host, and path with its query items' secrets taken out. */
    fun describe(request: Request): String {
        val url = request.url
        val query = url.encodedQuery?.let { "?$it" }.orEmpty()
        return "${request.method} ${url.host}${url.encodedPath}$query"
    }

    // Header

    /** What a shared log starts with: the app, the device, and the server, never a sign-in. */
    fun header(server: String?, requests: String?): String = listOfNotNull(
        "Zelefin ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})",
        "${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        "Generated ${SimpleDateFormat.getDateTimeInstance().format(Date())}",
        "Server: ${server ?: "not signed in"}",
        requests?.let { "Requests: $it" },
    ).joinToString("\n")
}
