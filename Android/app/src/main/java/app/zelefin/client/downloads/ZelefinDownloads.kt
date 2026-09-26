package app.zelefin.client.downloads

import android.content.Context
import android.net.Uri
import android.text.format.Formatter
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.SavedSession
import app.zelefin.core.TitleDetail
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.net.URI
import java.net.URLDecoder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Request

@Serializable
data class DownloadedItem(
    val item: MediaItem,
    val relativeMediaPath: String,
    val relativeArtworkPath: String? = null,
    val relativeShowArtworkPath: String? = null,
    val container: String,
    val videoCodec: String? = null,
    val byteSize: Long = 0,
    val userId: String,
    val serverHost: String,
    val downloadedAt: Long,
    /** Managed row id on backends that track downloads server-side (Silo); removed with the file. */
    val serverDownloadId: String? = null,
)

@Serializable
private data class DownloadCatalog(val version: Int, val records: List<DownloadedItem>)

data class DownloadProgress(
    val item: MediaItem,
    val userId: String,
    val serverHost: String,
    val runId: String,
    val bytesWritten: Long = 0,
    val bytesExpected: Long = 0,
) {
    val fraction: Double
        get() = if (bytesExpected > 0 && bytesWritten >= 0) min(1.0, bytesWritten.toDouble() / bytesExpected.toDouble()) else 0.0

    val percentLabel: String?
        get() = if (bytesExpected > 0) "${(fraction * 100).roundToInt()}%" else null

    fun sizeLabel(context: Context): String = when {
        bytesExpected > 0 -> "${Formatter.formatFileSize(context, bytesWritten)} of ${Formatter.formatFileSize(context, bytesExpected)}"
        bytesWritten > 0 -> Formatter.formatFileSize(context, bytesWritten)
        else -> "Starting…"
    }

    val bannerTitle: String
        get() {
            val subject = if (item.kind == MediaKind.Episode) item.episodeIndex?.let { "Episode $it" } ?: item.name else null
            val percent = percentLabel
            return when {
                subject != null && percent != null -> "Downloading $subject · $percent"
                subject != null -> "Downloading $subject"
                percent != null -> "Downloading $percent"
                else -> "Downloading"
            }
        }
}

sealed interface DownloadControlState {
    data object Unavailable : DownloadControlState
    data object Idle : DownloadControlState
    data class Downloading(val fraction: Double) : DownloadControlState
    data object Downloaded : DownloadControlState

    val menuTitle: String
        get() = when (this) {
            Unavailable, Idle -> "Download"
            is Downloading -> if (fraction > 0) "Cancel Download · ${(fraction * 100).roundToInt()}%" else "Cancel Download"
            Downloaded -> "Remove Download"
        }
}

sealed interface DownloadMark {
    data object None : DownloadMark
    data class Downloading(val fraction: Double) : DownloadMark
    data object Downloaded : DownloadMark
}

data class DownloadNotice(val title: String, val message: String)

data class DownloadAccount(val userId: String, val host: String)

/** One poster on the Downloaded page: a movie, or a show holding its downloaded episodes. */
data class DownloadRow(
    val id: String,
    val isSeries: Boolean,
    val title: MediaItem,
    val records: List<DownloadedItem>,
) {
    val episodeCount: Int get() = records.size
}

data class DownloadsState(
    val records: List<DownloadedItem> = emptyList(),
    val progress: Map<String, DownloadProgress> = emptyMap(),
    val account: DownloadAccount? = null,
    val available: Boolean = true,
    val notice: DownloadNotice? = null,
) {
    val scopedRecords: List<DownloadedItem>
        get() {
            val current = account ?: return emptyList()
            return records.filter { it.userId == current.userId && it.serverHost == current.host }
        }

    val scopedProgress: Map<String, DownloadProgress>
        get() {
            val current = account ?: return emptyMap()
            return progress.filterValues { it.userId == current.userId && it.serverHost == current.host }
        }

    fun record(itemId: String): DownloadedItem? = scopedRecords.firstOrNull { it.item.id == itemId }

    fun transfer(item: MediaItem): DownloadProgress? {
        val scoped = scopedProgress
        scoped[item.id]?.let { return it }
        if (item.kind != MediaKind.Series) return null
        return scoped.values.firstOrNull { it.item.seriesId == item.id }
    }

    fun mark(item: MediaItem): DownloadMark {
        transfer(item)?.let { return DownloadMark.Downloading(it.fraction) }
        val covered = scopedRecords.any { it.item.id == item.id || (item.kind == MediaKind.Series && it.item.seriesId == item.id) }
        return if (covered) DownloadMark.Downloaded else DownloadMark.None
    }

    fun control(item: MediaItem, episodes: List<MediaItem> = emptyList()): DownloadControlState {
        val target = DownloadEligibility.playableItem(item, episodes) ?: return DownloadControlState.Unavailable
        scopedProgress[target.id]?.let { return DownloadControlState.Downloading(it.fraction) }
        if (record(target.id) != null) return DownloadControlState.Downloaded
        return if (available) DownloadControlState.Idle else DownloadControlState.Unavailable
    }

    val activeTransfers: List<DownloadProgress>
        get() = scopedProgress.values.sortedBy { it.item.name }

    val rows: List<DownloadRow>
        get() {
            val sorted = scopedRecords.sortedWith(compareByDescending<DownloadedItem> { it.downloadedAt }.thenBy { it.item.name.lowercase() })
            val movies = mutableListOf<DownloadRow>()
            val buckets = LinkedHashMap<String, MutableList<DownloadedItem>>()
            sorted.forEach { record ->
                val seriesId = record.item.seriesId
                if (record.item.kind == MediaKind.Episode && !seriesId.isNullOrEmpty()) {
                    buckets.getOrPut(seriesId) { mutableListOf() } += record
                } else {
                    movies += DownloadRow(record.item.id, isSeries = false, title = record.item, records = listOf(record))
                }
            }
            val shows = buckets.map { (seriesId, episodes) ->
                DownloadRow(seriesId, isSeries = true, title = DownloadEligibility.showItem(episodes.first().item), records = episodes)
            }
            return (movies + shows).sortedWith(
                compareByDescending<DownloadRow> { row -> row.records.maxOf { it.downloadedAt } }.thenBy { it.title.name.lowercase() },
            )
        }
}

object DownloadEligibility {
    fun playableItem(item: MediaItem, episodes: List<MediaItem> = emptyList()): MediaItem? = when (item.kind) {
        MediaKind.Movie, MediaKind.Episode -> item
        MediaKind.Series -> MediaItem.heroPlaybackItem(item, episodes).takeIf { it.kind == MediaKind.Episode }
        else -> null
    }

    /** The show an episode belongs to, built from what the episode carries so it works offline. */
    fun showItem(episode: MediaItem): MediaItem = MediaItem(
        id = episode.seriesId ?: episode.id,
        name = episode.seriesName ?: episode.name,
        kind = MediaKind.Series,
        genres = episode.genres,
        officialRating = episode.officialRating,
        backdropImageTag = null,
        parentBackdropItemId = episode.parentBackdropItemId,
        logoImageTag = null,
        parentLogoItemId = episode.parentLogoItemId,
        parentLogoImageTag = episode.parentLogoImageTag,
    )
}

object DownloadPrompts {
    const val Title = "Delete Download?"

    fun removal(item: MediaItem): DownloadNotice =
        DownloadNotice(Title, "Are you sure you want to delete the downloaded file for ${label(item)}? You can download it again later.")

    fun removal(row: DownloadRow): DownloadNotice {
        if (row.isSeries && row.episodeCount > 1) {
            return DownloadNotice(
                Title,
                "Are you sure you want to delete ${row.episodeCount} downloaded episodes of ${row.title.name}? You can download them again later.",
            )
        }
        return removal(row.records.firstOrNull()?.item ?: row.title)
    }

    fun label(item: MediaItem): String {
        val show = item.seriesName
        return if (item.kind == MediaKind.Episode && !show.isNullOrBlank()) "$show — ${item.name}" else item.name
    }
}

data class DownloadAsset(
    val url: String,
    val headers: Map<String, String>,
    val container: String? = null,
    val knownSize: Long = 0,
    val serverDownloadId: String? = null,
)

/** Resolves where a title's original file lives for the signed-in backend. */
interface DownloadBackend {
    suspend fun available(session: SavedSession): Boolean
    suspend fun prepare(item: MediaItem, session: SavedSession): DownloadAsset
    suspend fun finalize(session: SavedSession, serverDownloadId: String) {}
    suspend fun deleteServer(session: SavedSession, serverDownloadId: String) {}

    /** Poster for the title, and for an episode the show's poster. */
    suspend fun artworkUrls(item: MediaItem, session: SavedSession): Pair<String?, String?>
}

sealed interface LocalPlayback {
    data object None : LocalPlayback
    data object Missing : LocalPlayback
    data class Ready(val plan: PlaybackPlan) : LocalPlayback
}

/**
 * Offline downloads, shared by every screen. Transfers run in an application scope so they
 * keep going when the page closes; [DownloadService] keeps the process in the foreground meanwhile.
 * Layout matches iOS `DownloadStore`: `Zelefin/Downloads/catalog.json` + `files/{host}/{user}/{item}/`.
 */
object ZelefinDownloads {
    const val FailureMessage = "Zelefin could not download this title. Check the connection and try again."
    const val OpenFailureMessage = "Zelefin could not open the downloaded file."
    private const val CatalogVersion = 1

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val json = Json { ignoreUnknownKeys = true }
    private val lock = Any()
    private val jobs = ConcurrentHashMap<String, Job>()
    private val _state = MutableStateFlow(DownloadsState())
    val state: StateFlow<DownloadsState> = _state.asStateFlow()

    @Volatile private var appContext: Context? = null
    @Volatile private var backend: DownloadBackend? = null
    @Volatile private var session: SavedSession? = null
    private var sessionJob: Job? = null

    private val transferClient by lazy {
        GatewayHttp.client.newBuilder()
            .readTimeout(120, TimeUnit.SECONDS)
            .callTimeout(0, TimeUnit.SECONDS)
            .build()
    }

    fun attach(context: Context, backend: DownloadBackend, sessions: Flow<SavedSession?>) {
        val app = context.applicationContext
        synchronized(lock) {
            if (appContext == null) {
                appContext = app
                _state.update { it.copy(records = loadCatalog(app)) }
            }
        }
        this.backend = backend
        sessionJob?.cancel()
        sessionJob = scope.launch {
            sessions.distinctUntilChanged().collectLatest { current ->
                session = current
                val account = current?.let { DownloadAccount(it.userId, host(it.serverUrl)) }
                _state.update { it.copy(account = account, available = current != null && !current.usesSilo) }
                if (current != null && current.usesSilo) {
                    val usable = runCatching { backend.available(current) }
                        .onFailure { if (it is CancellationException) throw it }
                        .getOrDefault(false)
                    _state.update { if (it.account == account) it.copy(available = usable) else it }
                }
            }
        }
    }

    fun dismissNotice() {
        _state.update { it.copy(notice = null) }
    }

    fun showNotice(notice: DownloadNotice) {
        _state.update { it.copy(notice = notice) }
    }

    fun start(target: MediaItem) {
        val current = session ?: return
        val backend = backend ?: return
        val app = appContext ?: return
        val runId = UUID.randomUUID().toString()
        synchronized(lock) {
            if (jobs.containsKey(target.id)) return
            if (_state.value.record(target.id) != null) return
            val progress = DownloadProgress(target, current.userId, host(current.serverUrl), runId)
            _state.update { it.copy(progress = it.progress + (target.id to progress)) }
            val job = scope.launch(start = CoroutineStart.LAZY) { perform(app, target, current, backend, runId) }
            jobs[target.id] = job
            job.invokeOnCompletion {
                synchronized(lock) { if (jobs[target.id] === job) jobs.remove(target.id) }
                clearProgress(target.id, runId)
            }
            job.start()
        }
        DownloadService.start(app)
    }

    /** Stops the transfer for [item] (or, for a show, its episode that is downloading). */
    fun cancel(item: MediaItem) {
        val id = _state.value.transfer(item)?.item?.id ?: item.id
        synchronized(lock) {
            jobs.remove(id)?.cancel()
            _state.update { it.copy(progress = it.progress - id) }
        }
    }

    fun remove(itemId: String) {
        synchronized(lock) {
            jobs.remove(itemId)?.cancel()
            _state.update { it.copy(progress = it.progress - itemId) }
        }
        val app = appContext ?: return
        val record = _state.value.record(itemId) ?: return
        File(root(app), record.relativeMediaPath).parentFile?.deleteRecursively()
        synchronized(lock) {
            _state.update { state ->
                state.copy(records = state.records.filterNot { it.sameEntry(record) })
            }
            persist(app)
        }
        val serverId = record.serverDownloadId
        val signedIn = session
        val backend = backend
        if (serverId != null && signedIn != null && backend != null) {
            scope.launch { runCatching { backend.deleteServer(signedIn, serverId) } }
        }
    }

    fun remove(row: DownloadRow) {
        row.records.forEach { remove(it.item.id) }
    }

    fun localPlayback(item: MediaItem): LocalPlayback {
        val app = appContext ?: return LocalPlayback.None
        val record = _state.value.record(item.id) ?: return LocalPlayback.None
        val file = File(root(app), record.relativeMediaPath)
        if (!file.exists()) {
            remove(record.item.id)
            showNotice(DownloadNotice("Download", OpenFailureMessage))
            return LocalPlayback.Missing
        }
        val playable = item.copy(playbackPosition = maxOf(item.playbackPosition, record.item.playbackPosition))
        return LocalPlayback.Ready(
            PlaybackPlan(
                item = playable,
                streamUrl = Uri.fromFile(file).toString(),
                playSessionId = null,
                mediaSourceId = null,
                method = PlaybackMethod.DirectPlay,
                container = record.container,
                videoCodec = record.videoCodec,
                startTimeSeconds = playable.playbackPosition,
                clientOwnsPlayhead = true,
            ),
        )
    }

    /** Keeps the stored resume point current, since local playback does not report to the server. */
    fun updatePosition(itemId: String, seconds: Double) {
        val app = appContext ?: return
        synchronized(lock) {
            val record = _state.value.record(itemId) ?: return
            val runtime = record.item.runtime
            val played = runtime != null && runtime > 0 && seconds / runtime >= 0.98
            val item = record.item.copy(playbackPosition = if (played) 0.0 else seconds, isPlayed = played || record.item.isPlayed)
            _state.update { state ->
                state.copy(records = state.records.map { if (it.sameEntry(record)) it.copy(item = item) else it })
            }
            persist(app)
        }
    }

    /** Local artwork for a poster: the show's poster for a series, else the title's own. */
    fun localArtwork(item: MediaItem): String? {
        val app = appContext ?: return null
        val matches = _state.value.scopedRecords.filter { it.item.id == item.id || (item.kind == MediaKind.Series && it.item.seriesId == item.id) }
        val path = if (item.kind == MediaKind.Series) {
            matches.firstNotNullOfOrNull { it.relativeShowArtworkPath } ?: matches.firstNotNullOfOrNull { it.relativeArtworkPath }
        } else {
            matches.firstNotNullOfOrNull { it.relativeArtworkPath }
        } ?: return null
        val file = File(root(app), path)
        return if (file.exists()) Uri.fromFile(file).toString() else null
    }

    /** A title page built only from local records, for opening a download without a connection. */
    fun offlineDetail(id: String): TitleDetail? {
        val records = _state.value.scopedRecords
        records.firstOrNull { it.item.id == id }?.let { record ->
            return TitleDetail(item = record.item.copy(posterUrl = record.item.posterUrl ?: localArtwork(record.item)))
        }
        val episodes = records.filter { it.item.seriesId == id }.map { it.item }
        if (episodes.isEmpty()) return null
        val show = DownloadEligibility.showItem(episodes.first())
        val ordered = MediaItem.orderedEpisodes(episodes)
        val seasons = ordered.mapNotNull { it.seasonIndex }.distinct().map { number ->
            MediaItem(
                id = "$id-season-$number",
                name = if (number == 0) "Specials" else "Season $number",
                kind = MediaKind.Season,
                seasonIndex = number,
                seriesId = id,
            )
        }
        return TitleDetail(item = show.copy(posterUrl = localArtwork(show)), seasons = seasons, episodes = ordered)
    }

    private suspend fun perform(app: Context, target: MediaItem, account: SavedSession, backend: DownloadBackend, runId: String) {
        val folder = itemDirectory(app, account, target.id)
        val staging = File(folder, ".run-$runId")
        var asset: DownloadAsset? = null
        var finished = false
        try {
            val resolved = backend.prepare(target, account)
            asset = resolved
            coroutineScope { ensureActive() }
            staging.mkdirs()
            if (resolved.knownSize > 0) updateProgress(target.id, runId) { copy(bytesExpected = resolved.knownSize) }
            val partial = File(staging, "media.part")
            val (bytes, extension) = transfer(resolved, partial) { written, expected ->
                updateProgress(target.id, runId) { copy(bytesWritten = written, bytesExpected = expected) }
            }
            val container = extension ?: resolved.container?.lowercase() ?: "mkv"
            val (posterUrl, showUrl) = runCatching { backend.artworkUrls(target, account) }
                .onFailure { if (it is CancellationException) throw it }
                .getOrDefault(null to null)
            val poster = saveArtwork(posterUrl, resolved.headers, File(staging, "poster.jpg"))
            val show = if (target.kind == MediaKind.Episode) saveArtwork(showUrl, resolved.headers, File(staging, "show.jpg")) else null
            coroutineScope { ensureActive() }

            val media = File(folder, "media.$container")
            moveInto(partial, media)
            val posterFile = poster?.let { moveInto(it, File(folder, "poster.jpg")) }
            val showFile = show?.let { moveInto(it, File(folder, "show.jpg")) }
            val record = DownloadedItem(
                item = target,
                relativeMediaPath = relativePath(app, media),
                relativeArtworkPath = posterFile?.let { relativePath(app, it) },
                relativeShowArtworkPath = showFile?.let { relativePath(app, it) },
                container = container,
                byteSize = if (bytes > 0) bytes else resolved.knownSize,
                userId = account.userId,
                serverHost = host(account.serverUrl),
                downloadedAt = System.currentTimeMillis(),
                serverDownloadId = resolved.serverDownloadId,
            )
            synchronized(lock) {
                _state.update { state ->
                    state.copy(records = state.records.filterNot { it.sameEntry(record) } + record)
                }
                persist(app)
            }
            finished = true
            resolved.serverDownloadId?.let { id -> runCatching { backend.finalize(account, id) } }
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Throwable) {
            showNotice(DownloadNotice("Download", FailureMessage))
        } finally {
            staging.deleteRecursively()
            if (!finished) {
                if (folder.listFiles().isNullOrEmpty()) folder.delete()
                val serverId = asset?.serverDownloadId
                if (serverId != null) scope.launch { runCatching { backend.deleteServer(account, serverId) } }
            }
        }
    }

    private suspend fun transfer(asset: DownloadAsset, destination: File, onProgress: (Long, Long) -> Unit): Pair<Long, String?> {
        val request = Request.Builder().url(asset.url).apply {
            asset.headers.forEach { (name, value) -> header(name, value) }
        }.build()
        val call = transferClient.newCall(request)
        return coroutineScope {
            val watcher = launch {
                try {
                    awaitCancellation()
                } finally {
                    call.cancel()
                }
            }
            try {
                call.execute().use { response ->
                    if (!response.isSuccessful) throw IOException("HTTP ${response.code}")
                    val type = response.header("Content-Type")?.lowercase()
                    if (type != null && type.contains("text/html")) throw IOException("Unexpected page")
                    val body = response.body ?: throw IOException("Empty body")
                    val expected = body.contentLength().takeIf { it > 0 } ?: asset.knownSize
                    val extension = response.header("Content-Disposition")?.let(::filenameExtension)
                    var written = 0L
                    var lastReport = 0L
                    body.byteStream().use { input ->
                        FileOutputStream(destination).use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                ensureActive()
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                written += read
                                val now = System.currentTimeMillis()
                                if (now - lastReport >= 250) {
                                    lastReport = now
                                    onProgress(written, expected)
                                }
                            }
                        }
                    }
                    if (written <= 0) throw IOException("Empty file")
                    onProgress(written, maxOf(expected, written))
                    written to extension
                }
            } finally {
                watcher.cancel()
            }
        }
    }

    private fun saveArtwork(url: String?, headers: Map<String, String>, destination: File): File? {
        if (url.isNullOrBlank()) return null
        return runCatching {
            val request = Request.Builder().url(url).apply { headers.forEach { (name, value) -> header(name, value) } }.build()
            GatewayHttp.client.newCall(request).execute().use { response ->
                val type = response.header("Content-Type")?.lowercase()
                if (!response.isSuccessful || (type != null && type.contains("text/html"))) return@use null
                val bytes = response.body?.bytes() ?: return@use null
                if (bytes.isEmpty()) return@use null
                destination.writeBytes(bytes)
                destination
            }
        }.getOrNull()
    }

    private fun updateProgress(id: String, runId: String, transform: DownloadProgress.() -> DownloadProgress) {
        _state.update { state ->
            val current = state.progress[id]
            if (current == null || current.runId != runId) state else state.copy(progress = state.progress + (id to current.transform()))
        }
    }

    private fun clearProgress(id: String, runId: String) {
        _state.update { state ->
            if (state.progress[id]?.runId == runId) state.copy(progress = state.progress - id) else state
        }
    }

    private fun moveInto(source: File, destination: File): File {
        destination.parentFile?.mkdirs()
        if (destination.exists()) destination.delete()
        if (!source.renameTo(destination)) {
            source.copyTo(destination, overwrite = true)
            source.delete()
        }
        return destination
    }

    private fun DownloadedItem.sameEntry(other: DownloadedItem): Boolean =
        item.id == other.item.id && userId == other.userId && serverHost == other.serverHost

    private fun root(context: Context): File = File(context.filesDir, "Zelefin/Downloads")

    private fun itemDirectory(context: Context, account: SavedSession, itemId: String): File =
        File(File(File(File(root(context), "files"), sanitized(host(account.serverUrl))), sanitized(account.userId)), sanitized(itemId))

    private fun relativePath(context: Context, file: File): String = file.relativeTo(root(context)).path

    private fun loadCatalog(context: Context): List<DownloadedItem> {
        val file = File(root(context), "catalog.json")
        if (!file.exists()) return emptyList()
        val catalog = runCatching { json.decodeFromString<DownloadCatalog>(file.readText()) }.getOrNull() ?: return emptyList()
        if (catalog.version != CatalogVersion) return emptyList()
        return catalog.records.filter { File(root(context), it.relativeMediaPath).exists() }
    }

    private fun persist(context: Context) {
        runCatching {
            val directory = root(context)
            directory.mkdirs()
            val data = json.encodeToString(DownloadCatalog.serializer(), DownloadCatalog(CatalogVersion, _state.value.records))
            val temporary = File(directory, "catalog.json.tmp")
            temporary.writeText(data)
            val target = File(directory, "catalog.json")
            if (!temporary.renameTo(target)) {
                target.writeText(data)
                temporary.delete()
            }
        }
    }

    internal fun host(serverUrl: String): String =
        runCatching { URI(serverUrl).host }.getOrNull()?.takeIf { it.isNotBlank() } ?: serverUrl

    private fun sanitized(value: String): String = value.replace("/", "_").replace(":", "_")

    internal fun filenameExtension(header: String): String? {
        val lower = header.lowercase()
        val filename = when {
            "filename*=" in lower -> {
                val raw = header.substring(lower.indexOf("filename*=") + "filename*=".length).substringBefore(';').trim()
                val encoded = raw.substringAfter("''", raw).trim('"', '\'')
                runCatching { URLDecoder.decode(encoded, "UTF-8") }.getOrDefault(encoded)
            }
            "filename=" in lower -> header.substring(lower.indexOf("filename=") + "filename=".length).substringBefore(';').trim().trim('"', '\'')
            else -> return null
        }
        val extension = filename.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty() || extension.length > 5 || !extension.all { it.isLetterOrDigit() }) return null
        return if (extension == "matroska") "mkv" else extension
    }
}
