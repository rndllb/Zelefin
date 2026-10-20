package app.zelefin.client.silo

import app.zelefin.client.CatalogBrowseQuery
import app.zelefin.client.CatalogSortField
import app.zelefin.client.CatalogStatusFilter
import app.zelefin.client.LibraryCounts
import app.zelefin.client.LibraryKind
import app.zelefin.client.LibraryRoom
import app.zelefin.client.SearchHit
import app.zelefin.client.SearchHitKind
import app.zelefin.client.searchSubtitle
import app.zelefin.client.matchesCatalog
import app.zelefin.client.orderedForCatalog
import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.HomeFeed
import app.zelefin.core.HouseholdProfile
import app.zelefin.core.MediaItem
import app.zelefin.core.MediaKind
import app.zelefin.core.PlaybackMethod
import app.zelefin.core.PlaybackPlan
import app.zelefin.core.PlaybackResumePolicy
import app.zelefin.core.SiloAuth
import app.zelefin.core.SiloJson
import app.zelefin.core.SiloMapper
import app.zelefin.core.SiloMediaUrl
import app.zelefin.core.TitleDetail
import app.zelefin.core.TitleTrailer
import app.zelefin.core.ZelefinException
import app.zelefin.core.arr
import app.zelefin.core.bool
import app.zelefin.core.dbl
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import java.net.URLEncoder
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

private data class SiloCatalogPage(val items: List<MediaItem>, val total: Int?)

class SiloClient(
    val baseUrl: String,
    var accessToken: String = "",
    var refreshToken: String? = null,
    var profileId: String? = null,
    var profileToken: String? = null,
    private val deviceId: String,
    private val deviceName: String,
    private val formFactor: String,
    private val appVersion: String,
    private val osVersion: String,
) {
    suspend fun healthReady(): Boolean = withContext(Dispatchers.IO) {
        val response = call("/api/v1/health", authorized = false)
        if (response.status !in 200..299) return@withContext false
        val json = SiloJson.objectOrNull(response.body) ?: return@withContext false
        val status = json.str("status")?.lowercase()
        status == "ok" || status == "healthy" || status == "ready"
    }

    suspend fun serverLabel(): Pair<String, String>? = withContext(Dispatchers.IO) {
        val response = call("/api/v1/health", authorized = false)
        val json = SiloJson.objectOrNull(response.body) ?: return@withContext null
        val status = json.str("status")?.lowercase()
        if (status != "ok" && status != "healthy" && status != "ready") return@withContext null
        SiloMapper.serverName(json) to SiloMapper.version(json)
    }

    suspend fun login(username: String, password: String): SiloAuth = withContext(Dispatchers.IO) {
        val body = """{"username":${jsonString(username)},"password":${jsonString(password)}}"""
        val response = call("/api/v1/auth/login", method = "POST", body = body, authorized = false)
        val auth = SiloJson.objectOrNull(response.body)?.let(SiloMapper::auth)
            ?: throw ZelefinException.server(errorMessage(response.body, response.status))
        accessToken = auth.accessToken
        refreshToken = auth.refreshToken
        auth
    }

    suspend fun profiles(): List<HouseholdProfile> = withContext(Dispatchers.IO) {
        for (path in listOf("/api/v2/profiles", "/api/v1/profiles")) {
            val response = call(path)
            if (response.status !in 200..299) continue
            val parsed = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val profiles = SiloMapper.profiles(parsed, baseUrl)
            if (profiles.isNotEmpty() || response.status in 200..299) return@withContext profiles
        }
        emptyList()
    }

    suspend fun changePassword(current: String, new: String) = withContext(Dispatchers.IO) {
        val body = """{"current_password":${jsonString(current)},"new_password":${jsonString(new)}}"""
        var response = call("/api/v2/account/password", method = "POST", body = body)
        if (response.status !in 200..299) response = call("/api/v1/auth/account/password", method = "POST", body = body)
        if (response.status !in 200..299) throw ZelefinException.server(errorMessage(response.body, response.status))
    }

    suspend fun verifyPin(profileId: String, pin: String): String? = withContext(Dispatchers.IO) {
        val encoded = urlPath(profileId)
        val response = call(
            "/api/v1/profiles/$encoded/verify-pin",
            method = "POST",
            body = """{"pin":${jsonString(pin)}}""",
        )
        if (response.status !in 200..299) {
            throw ZelefinException.server(errorMessage(response.body, response.status))
        }
        val json = SiloJson.objectOrNull(response.body)
        if (json?.bool("valid") == false) throw ZelefinException.server("That PIN is not right.")
        json?.str("profile_token")
    }

    suspend fun home(): HomeFeed = withContext(Dispatchers.IO) {
        for (path in listOf("/api/v2/home/sections", "/api/v1/home/sections")) {
            val response = call(path, query = mapOf("image_size" to "large"))
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            var feed = SiloMapper.home(element, baseUrl)
            if (feed.featured.isEmpty() && feed.continueWatching.isEmpty() && feed.recentMovies.isEmpty()) {
                feed = hydrate(element, feed)
            }
            if (feed.recentMovies.isEmpty()) {
                feed = feed.copy(recentMovies = catalog("movie"))
            }
            if (feed.recentShows.isEmpty()) {
                feed = feed.copy(recentShows = catalog("series"))
            }
            if (feed.featured.isEmpty()) {
                feed = feed.copy(
                    featured = (feed.recentMovies + feed.recentShows).filter { it.hasHeroBackdrop }.take(8),
                )
            }
            return@withContext feed
        }
        HomeFeed(recentMovies = catalog("movie"), recentShows = catalog("series"))
    }

    suspend fun libraries(): List<LibraryRoom> = withContext(Dispatchers.IO) {
        val response = call("/api/v1/user/libraries")
        if (response.status !in 200..299) return@withContext emptyList()
        val rooms = SiloJson.objectOrNull(response.body)?.objects("libraries").orEmpty()
        rooms.mapNotNull { room ->
            val name = room.str("name") ?: return@mapNotNull null
            val id = room.str("id") ?: room.int("id")?.toString() ?: return@mapNotNull null
            val kind = LibraryKind.fromSilo(room.str("type") ?: room.str("kind") ?: room.str("media_type"))
            LibraryRoom(id = id, name = name, kind = kind)
        }
    }

    fun catalogType(kind: LibraryKind): String? = when (kind) {
        LibraryKind.Movies -> "movie"
        LibraryKind.Shows -> "series"
        LibraryKind.Collections -> "collection"
        else -> null
    }

    /** Silo has no server-stats route, so totals come from the catalog `total` with `limit=1`. */
    suspend fun serverCounts(): LibraryCounts = withContext(Dispatchers.IO) {
        LibraryCounts(
            movies = catalogTotal(listOf("movie")),
            shows = catalogTotal(listOf("series", "show")),
            episodes = catalogTotal(listOf("episode")),
        )
    }

    suspend fun roomCounts(room: LibraryRoom): LibraryCounts = withContext(Dispatchers.IO) {
        when (room.kind) {
            LibraryKind.Movies -> LibraryCounts(movies = catalogTotal(listOf("movie"), room.id))
            LibraryKind.Shows -> LibraryCounts(
                shows = catalogTotal(listOf("series", "show"), room.id),
                episodes = catalogTotal(listOf("episode"), room.id),
            )
            LibraryKind.LiveTV -> LibraryCounts()
            else -> LibraryCounts(
                catalogTotal(listOf("movie"), room.id),
                catalogTotal(listOf("series", "show"), room.id),
                catalogTotal(listOf("episode"), room.id),
            )
        }
    }

    private fun catalogTotal(types: List<String>, libraryId: String? = null): Int {
        for (type in types) {
            val query = buildMap {
                put("type", type)
                put("limit", "1")
                if (libraryId != null) put("library_id", libraryId)
            }
            val total = catalogPage(query).total ?: continue
            if (total > 0) return total
        }
        return 0
    }

    suspend fun previewItems(room: LibraryRoom, limit: Int = 8): List<MediaItem> = withContext(Dispatchers.IO) {
        val query = buildMap {
            catalogType(room.kind)?.let { put("type", it) }
            put("sort", "added_at")
            put("order", "desc")
            put("limit", limit.toString())
            put("image_size", "large")
            put("library_id", room.id)
        }
        runCatching { firstCatalog(query) }.getOrDefault(emptyList()).take(limit)
    }

    suspend fun catalog(type: String?, libraryId: String? = null, browse: CatalogBrowseQuery? = null): List<MediaItem> =
        withContext(Dispatchers.IO) {
            if (browse == null) {
                val query = buildMap {
                    type?.let { put("type", it) }
                    put("sort", "added_at")
                    put("order", "desc")
                    put("limit", "80")
                    put("image_size", "large")
                    if (!libraryId.isNullOrBlank()) put("library_id", libraryId)
                }
                return@withContext firstCatalog(query)
            }
            val collected = mutableListOf<MediaItem>()
            val seen = mutableSetOf<String>()
            var offset = 0
            val pageSize = 200
            while (collected.size < 20_000) {
                val page = catalogPage(browseQuery(type, libraryId, browse, offset, pageSize))
                if (page.items.isEmpty()) break
                val fresh = page.items.filter { seen.add(it.id) }
                if (fresh.isEmpty()) break
                collected += fresh
                val next = offset + page.items.size
                val total = page.total
                val finished = if (total != null && total > 0) next >= total else page.items.size < pageSize
                if (finished) break
                offset = next
            }
            collected.matchesCatalog(browse).orderedForCatalog(browse)
        }

    suspend fun search(term: String): List<SearchHit> = withContext(Dispatchers.IO) {
        firstCatalog(mapOf("q" to term, "limit" to "40", "image_size" to "large")).map { item ->
            SearchHit(item.id, item.name, item.searchSubtitle(), SearchHitKind.Title, item)
        }
    }

    private fun browseQuery(type: String?, libraryId: String?, browse: CatalogBrowseQuery, offset: Int, pageSize: Int): Map<String, String> {
        val pair = siloSort(browse.sort)
        val order = if (browse.sortAscending) pair.second else if (pair.second == "asc") "desc" else "asc"
        return buildMap {
            type?.let { put("type", it) }
            put("sort", pair.first)
            put("order", order)
            put("limit", pageSize.toString())
            put("offset", offset.toString())
            put("image_size", "large")
            if (!libraryId.isNullOrBlank()) put("library_id", libraryId)
            if (CatalogStatusFilter.Favorite in browse.statuses) put("favorite", "true")
            browse.genres.firstOrNull()?.let { put("genre", it) }
            browse.years.firstOrNull()?.let { put("year", it.toString()) }
        }
    }

    private fun siloSort(field: CatalogSortField): Pair<String, String> = when (field) {
        CatalogSortField.Name -> "title" to "asc"
        CatalogSortField.DateAdded -> "added_at" to "desc"
        CatalogSortField.ReleaseDate -> "year" to "desc"
        CatalogSortField.CommunityRating, CatalogSortField.CriticRating -> "rating" to "desc"
        CatalogSortField.Runtime -> "runtime" to "desc"
        CatalogSortField.DatePlayed -> "date_viewed" to "desc"
        else -> "title" to "asc"
    }

    private fun firstCatalog(query: Map<String, String>): List<MediaItem> {
        for (path in listOf("/api/v2/catalog", "/api/v1/catalog")) {
            val response = call(path, query = query)
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val items = SiloMapper.catalogItems(element, baseUrl)
            if (items.isNotEmpty()) return items
        }
        return emptyList()
    }

    private fun catalogPage(query: Map<String, String>): SiloCatalogPage {
        for (path in listOf("/api/v2/catalog", "/api/v1/catalog")) {
            val response = call(path, query = query)
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val items = SiloMapper.catalogItems(element, baseUrl)
            val total = (element as? JsonObject)?.let { obj ->
                obj.int("total") ?: obj.int("total_count") ?: obj.int("totalCount")
            }
            if (items.isNotEmpty() || total == 0) return SiloCatalogPage(items, total)
        }
        return SiloCatalogPage(emptyList(), null)
    }

    suspend fun detail(id: String): TitleDetail = withContext(Dispatchers.IO) {
        val hit = catalogHit(id) ?: throw ZelefinException.server("This title was not found on the Silo server.")
        val item = hit.item
        val episodes = if (item.kind == MediaKind.Series || item.kind == MediaKind.Season) episodes(item) else emptyList()
        val seasons = episodes.groupBy { it.seasonIndex ?: 0 }.keys.sorted().map { number ->
            MediaItem(id = "$id-season-$number", name = if (number == 0) "Specials" else "Season $number", kind = MediaKind.Season, seasonIndex = number, seriesId = id)
        }
        TitleDetail(
            item = item,
            seasons = seasons,
            episodes = episodes,
            related = similar(id),
            trailers = hit.trailers,
            moreInfo = app.zelefin.core.TitleMoreInfo.fromItem(item),
        )
    }

    /**
     * [maxBitrate] is the start cap in bits per second; null or the Auto ceiling asks for the
     * original file. Language codes pick the audio / subtitle track Silo starts with.
     */
    suspend fun playback(
        item: MediaItem,
        appVersion: String,
        osVersion: String,
        model: String,
        maxBitrate: Int? = null,
        audioLanguage: String = app.zelefin.client.PlaybackPreferences.AUTOMATIC,
        subtitleLanguage: String = app.zelefin.client.PlaybackPreferences.AUTOMATIC,
    ): PlaybackPlan =
        withContext(Dispatchers.IO) {
            val profile = profileId?.trim().orEmpty()
            if (profile.isEmpty()) throw ZelefinException.server("Select a profile before playing.")
            val playable = resolvePlayable(item)
            val fileId = playable.mediaSourceId?.toIntOrNull()
                ?: catalogItem(playable.id)?.mediaSourceId?.toIntOrNull()
                ?: throw ZelefinException.server("Silo did not return a playable file for this title.")
            val automatic = app.zelefin.client.PlaybackPreferences.AUTOMATIC
            val off = app.zelefin.client.PlaybackPreferences.OFF
            val needsTracks = audioLanguage != automatic || (subtitleLanguage != automatic && subtitleLanguage != off)
            val tracks = if (needsTracks) streamTracks(playable.id, fileId) else null
            val audioIndex = if (audioLanguage == automatic) null else tracks?.let { app.zelefin.client.PlaybackLanguage.audioIndex(it.first, audioLanguage) }
            val subtitleIndex = when (subtitleLanguage) {
                off -> -1
                automatic -> null
                else -> tracks?.let { app.zelefin.client.PlaybackLanguage.subtitleIndex(it.second, subtitleLanguage) }
            }
            val capKbps = maxBitrate?.takeIf { it in 1 until app.zelefin.client.PlaybackQuality.MAX_BITRATE }
                ?.let { (it / 1_000).coerceIn(100, 1_000_000) }
            val body = SiloMapper.playbackStart(
                fileId = fileId,
                profileId = profile,
                startPosition = playable.playbackPosition,
                attemptId = "zelefin:${UUID.randomUUID()}",
                appVersion = appVersion,
                osVersion = osVersion,
                model = model,
                formFactor = formFactor,
                bandwidthCapKbps = capKbps,
                audioIndex = audioIndex,
                subtitleIndex = subtitleIndex,
            )
            val response = call("/api/v1/playback/start", method = "POST", body = body)
            val json = SiloJson.objectOrNull(response.body)
                ?: throw ZelefinException.server(errorMessage(response.body, response.status))
            if (response.status !in 200..299) {
                throw ZelefinException.server(errorMessage(response.body, response.status))
            }
            val path = SiloMapper.streamPath(json) ?: throw ZelefinException.missingStreamUrl()
            val url = SiloMediaUrl.resolve(baseUrl, path) ?: throw ZelefinException.missingStreamUrl()
            val method = SiloMapper.playbackMethod(json)
            val owns = SiloMapper.clientOwnsPlayhead(json)
            val start = PlaybackResumePolicy.clientStartPosition(method, playable.playbackPosition, owns) ?: playable.playbackPosition
            PlaybackPlan(
                item = playable,
                streamUrl = url,
                playSessionId = SiloMapper.sessionId(json),
                mediaSourceId = fileId.toString(),
                method = method,
                container = json.obj("playback_plan")?.obj("stream")?.str("container"),
                videoCodec = json.obj("playback_plan")?.obj("source")?.str("video_codec"),
                startTimeSeconds = start,
                headers = streamHeaders(),
                clientOwnsPlayhead = owns || method == PlaybackMethod.DirectPlay,
                appliedBitrate = maxBitrate ?: app.zelefin.client.PlaybackQuality.MAX_BITRATE,
                sourceBitrate = json.obj("playback_plan")?.obj("source")?.let { source ->
                    source.int("bitrate") ?: source.int("bit_rate") ?: source.int("bitrate_kbps")?.times(1_000)
                }?.takeIf { it > 0 },
            )
        }

    /** Audio and subtitle tracks for [fileId], read from the catalog versions (like iOS `versions(itemID:)`). */
    private fun streamTracks(itemId: String, fileId: Int): Pair<List<app.zelefin.client.LanguageTrack>, List<app.zelefin.client.LanguageTrack>>? {
        val encoded = urlPath(itemId)
        val paths = listOf(
            "/api/v2/catalog/items/$encoded/versions",
            "/api/v2/catalog/items/$encoded",
            "/api/v1/catalog/items/$encoded/versions",
            "/api/v1/catalog/items/$encoded",
        )
        for (path in paths) {
            val response = runCatching { call(path) }.getOrNull() ?: continue
            if (response.status !in 200..299) continue
            val root = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val versions = mutableListOf<JsonObject>()
            collectVersions(root, versions)
            if (versions.isEmpty()) continue
            val version = versions.firstOrNull { (it.int("file_id") ?: it.int("id")) == fileId } ?: versions.first()
            fun tracks(key: String) = version.arr(key).orEmpty().mapIndexedNotNull { ordinal, element ->
                val track = element as? JsonObject ?: return@mapIndexedNotNull null
                app.zelefin.client.LanguageTrack(
                    index = track.int("index") ?: ordinal,
                    language = track.str("language"),
                    isSelected = track.bool("default") == true,
                )
            }
            return tracks("audio_tracks") to tracks("subtitle_tracks")
        }
        return null
    }

    private fun collectVersions(element: kotlinx.serialization.json.JsonElement, into: MutableList<JsonObject>) {
        when (element) {
            is JsonObject -> {
                if (element.containsKey("audio_tracks") || element.containsKey("subtitle_tracks")) into += element
                element.values.forEach { collectVersions(it, into) }
            }
            is kotlinx.serialization.json.JsonArray -> element.forEach { collectVersions(it, into) }
            else -> Unit
        }
    }

    /** Times a download from Silo, like iOS `bitrateTestBytes`: the probe endpoint, else repeated home fetches. */
    suspend fun measureBitrate(
        size: Int,
        timeoutMillis: Long,
        transport: app.zelefin.client.NetworkTransport,
    ): app.zelefin.client.BitrateProbeResult? = withContext(Dispatchers.IO) {
        val bounded = size.coerceIn(32_000, 8_000_000)
        val deadline = System.nanoTime() + timeoutMillis * 1_000_000
        val client = GatewayHttp.client.newBuilder()
            .callTimeout(timeoutMillis, java.util.concurrent.TimeUnit.MILLISECONDS)
            .build()
        fun fetch(path: String, query: Map<String, String>): Int? {
            val builder = Request.Builder().url(buildUrl(path, query))
            identity().forEach { (name, value) -> builder.header(name, value) }
            if (accessToken.isNotBlank()) builder.header("Authorization", "Bearer $accessToken")
            profileId?.let { builder.header("X-Profile-Id", it) }
            profileToken?.let { builder.header("X-Profile-Token", it) }
            return runCatching {
                client.newCall(builder.build()).execute().use { response ->
                    if (response.isSuccessful) response.body?.bytes()?.size else null
                }
            }.getOrNull()
        }
        val started = System.nanoTime()
        val direct = fetch("/api/v1/playback/bitrate-test", mapOf("size" to bounded.toString()))
        if (direct != null && direct >= 16_000) {
            return@withContext app.zelefin.client.BitrateProbeResult.from(direct, System.nanoTime() - started, transport)
        }
        val fallbackStart = System.nanoTime()
        var collected = 0
        var round = 0
        while (collected < bounded && round < 24 && System.nanoTime() < deadline) {
            round += 1
            val chunk = fetch(
                "/api/v2/home/sections",
                mapOf("image_size" to "large", "_probe" to "${System.currentTimeMillis() / 1000}-$round"),
            ) ?: break
            collected += chunk
        }
        if (collected < 16_000) return@withContext null
        app.zelefin.client.BitrateProbeResult.from(collected, System.nanoTime() - fallbackStart, transport)
    }

    suspend fun report(sessionId: String, position: Double, paused: Boolean) = withContext(Dispatchers.IO) {
        val encoded = urlPath(sessionId)
        call(
            "/api/v1/playback/$encoded/progress",
            method = "POST",
            body = """{"position":$position,"is_paused":$paused}""",
        )
        Unit
    }

    suspend fun markWatched(id: String) = withContext(Dispatchers.IO) {
        val result = call("/api/v1/watched/${encode(id)}", method = "POST", body = "{}")
        if (result.status !in 200..299) throw ZelefinException.server(errorMessage(result.body, result.status))
    }

    suspend fun markUnwatched(id: String) = withContext(Dispatchers.IO) {
        val result = call("/api/v1/watched/${encode(id)}", method = "DELETE")
        if (result.status !in 200..299) throw ZelefinException.server(errorMessage(result.body, result.status))
    }

    suspend fun setFavorite(id: String, favorite: Boolean) = withContext(Dispatchers.IO) {
        val result = if (favorite) {
            call("/api/v1/favorites/${encode(id)}", method = "PUT", body = "{}")
        } else {
            call("/api/v1/favorites/${encode(id)}", method = "DELETE")
        }
        if (result.status !in 200..299) throw ZelefinException.server(errorMessage(result.body, result.status))
    }

    suspend fun stop(sessionId: String) = withContext(Dispatchers.IO) {
        call("/api/v1/playback/${urlPath(sessionId)}", method = "DELETE")
        Unit
    }

    data class ManagedDownload(val id: String, val contentId: String?, val status: String, val fileSize: Long?) {
        val isReady: Boolean get() = status.equals("ready", ignoreCase = true)
        val isRevoked: Boolean get() = status.equals("revoked", ignoreCase = true)
    }

    /** `GET /api/v1/downloads/capability`: whether this profile may download, and the quality to request. */
    suspend fun downloadCapability(): Pair<Boolean, String> = withContext(Dispatchers.IO) {
        val response = call("/api/v1/downloads/capability")
        val json = SiloJson.objectOrNull(response.body)
        if (response.status !in 200..299 || json == null) return@withContext false to "original"
        val usable = json.bool("enabled") == true && json.bool("download_allowed") == true
        val presets = (json.arr("quality_presets") ?: json.arr("formats"))
            ?.mapNotNull { (it as? kotlinx.serialization.json.JsonPrimitive)?.content?.trim()?.ifEmpty { null } }
            .orEmpty()
        val quality = presets.firstOrNull { it.equals("original", ignoreCase = true) } ?: presets.firstOrNull() ?: "original"
        usable to quality
    }

    suspend fun downloadFileId(item: MediaItem): Int? = withContext(Dispatchers.IO) {
        item.mediaSourceId?.toIntOrNull() ?: runCatching { catalogItem(item.id)?.mediaSourceId?.toIntOrNull() }.getOrNull()
    }

    /** `POST /api/v1/downloads`; returns the rows the server echoes back. */
    suspend fun createDownload(contentId: String, fileId: Int?, quality: String): List<ManagedDownload> = withContext(Dispatchers.IO) {
        val file = fileId?.let { ""","file_id":$it""" }.orEmpty()
        val body = """{"content_id":${jsonString(contentId)}$file,"quality":${jsonString(quality)}}"""
        val response = call("/api/v1/downloads", method = "POST", body = body)
        if (response.status !in 200..299) throw ZelefinException.server(errorMessage(response.body, response.status))
        managedDownloads(response.body)
    }

    suspend fun downloadRows(): List<ManagedDownload> = withContext(Dispatchers.IO) {
        val response = call("/api/v1/downloads")
        if (response.status !in 200..299) return@withContext emptyList()
        managedDownloads(response.body)
    }

    fun downloadFileUrl(id: String): String? = SiloMediaUrl.resolve(baseUrl, "/api/v1/downloads/${urlPath(id)}/file")

    suspend fun completeDownload(id: String) = withContext(Dispatchers.IO) {
        call("/api/v1/downloads/${urlPath(id)}", method = "PATCH", body = """{"status":"completed"}""")
        Unit
    }

    suspend fun deleteDownload(id: String) = withContext(Dispatchers.IO) {
        call("/api/v1/downloads/${urlPath(id)}", method = "DELETE")
        Unit
    }

    fun mediaHeaders(): Map<String, String> = streamHeaders()

    suspend fun itemPosterUrl(id: String): String? = withContext(Dispatchers.IO) { catalogItem(id)?.posterUrl }

    private fun managedDownloads(body: String): List<ManagedDownload> {
        val element = runCatching { SiloJson.parse(body) }.getOrNull() ?: return emptyList()
        val rows = when (element) {
            is kotlinx.serialization.json.JsonArray -> element.mapNotNull { it as? JsonObject }
            is JsonObject -> when {
                element.arr("downloads") != null -> element.objects("downloads")
                element.arr("items") != null -> element.objects("items")
                else -> listOf(element.obj("download") ?: element)
            }
            else -> emptyList()
        }
        return rows.mapNotNull { row ->
            val id = row.str("id") ?: row.int("id")?.toString() ?: return@mapNotNull null
            ManagedDownload(
                id = id,
                contentId = row.str("content_id") ?: row.int("content_id")?.toString(),
                status = row.str("status") ?: "preparing",
                fileSize = row.dbl("file_size")?.toLong(),
            )
        }
    }

    private suspend fun resolvePlayable(item: MediaItem): MediaItem {
        if (item.kind != MediaKind.Series && item.kind != MediaKind.Season) return item
        val episodes = episodes(item)
        return MediaItem.heroPlaybackItem(item, episodes)
    }

    private suspend fun catalogItem(id: String): MediaItem? = catalogHit(id)?.item

    private suspend fun catalogHit(id: String): CatalogHit? {
        val encoded = urlPath(id)
        for (path in listOf("/api/v2/catalog/items/$encoded", "/api/v1/catalog/items/$encoded")) {
            val response = call(path)
            if (response.status !in 200..299) continue
            val json = SiloJson.objectOrNull(response.body) ?: continue
            val wrapped = json.obj("item") ?: json
            val item = SiloMapper.mediaItem(wrapped, baseUrl) ?: continue
            return CatalogHit(item, SiloMapper.trailers(wrapped))
        }
        return null
    }

    private suspend fun episodes(item: MediaItem): List<MediaItem> {
        val seriesId = item.seriesId ?: item.id
        val encoded = urlPath(seriesId)
        val paths = listOf(
            "/api/v2/catalog/series/$encoded/episodes",
            "/api/v1/catalog/items/$encoded/episodes",
        )
        for (path in paths) {
            val response = call(path)
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val episodes = SiloMapper.episodes(element, baseUrl, seriesId, item.seriesName ?: item.name)
            if (episodes.isNotEmpty()) return MediaItem.orderedEpisodes(episodes)
        }
        return emptyList()
    }

    private suspend fun similar(id: String): List<MediaItem> {
        val encoded = urlPath(id)
        for (path in listOf("/api/v1/recommendations/similar/$encoded", "/api/v2/recommendations/similar/$encoded")) {
            val response = call(path, query = mapOf("limit" to "12"))
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val direct = SiloMapper.catalogItems(element, baseUrl)
            if (direct.isNotEmpty()) return direct
        }
        return emptyList()
    }

    private suspend fun hydrate(element: kotlinx.serialization.json.JsonElement, feed: HomeFeed): HomeFeed {
        val root = element as? JsonObject ?: return feed
        val sections = root.arr("sections") ?: root.arr("items") ?: return feed
        if (sections.isEmpty()) return feed
        return SiloMapper.home(element, baseUrl)
    }

    private fun streamHeaders(): Map<String, String> {
        val headers = identity().toMutableMap()
        headers["Authorization"] = "Bearer $accessToken"
        profileId?.let { headers["X-Profile-Id"] = it }
        profileToken?.let { headers["X-Profile-Token"] = it }
        headers.putAll(AccessGateway.headers(app.zelefin.client.network.GatewayCredentials.clientId, app.zelefin.client.network.GatewayCredentials.clientSecret))
        return headers
    }

    fun identity(): Map<String, String> = mapOf(
        "X-Silo-Device-Id" to deviceId,
        "X-Silo-Device-Name" to deviceName,
        "X-Silo-Device-Platform" to "Android",
        "X-Silo-Client-Family" to formFactor,
        "X-Silo-Client" to "Zelefin",
        "X-Silo-Client-Version" to appVersion,
        "X-Silo-Client-Build" to "6",
        "X-Silo-Client-Channel" to "release",
    )

    private data class HttpResult(val status: Int, val body: String)

    private fun call(
        path: String,
        method: String = "GET",
        query: Map<String, String> = emptyMap(),
        body: String? = null,
        authorized: Boolean = true,
        allowRefresh: Boolean = true,
    ): HttpResult {
        val result = execute(path, method, query, body, authorized)
        if (result.status == 401 && authorized && allowRefresh && !refreshToken.isNullOrBlank()) {
            refresh()
            return execute(path, method, query, body, authorized)
        }
        return result
    }

    private fun refresh() {
        val token = refreshToken ?: return
        val result = execute(
            "/api/v1/auth/refresh",
            method = "POST",
            body = """{"refresh_token":${jsonString(token)}}""",
            authorized = false,
        )
        val auth = SiloJson.objectOrNull(result.body)?.let(SiloMapper::auth) ?: return
        accessToken = auth.accessToken
        refreshToken = auth.refreshToken ?: token
    }

    private fun execute(
        path: String,
        method: String = "GET",
        query: Map<String, String> = emptyMap(),
        body: String? = null,
        authorized: Boolean = true,
    ): HttpResult {
        val url = buildUrl(path, query)
        val builder = Request.Builder().url(url).header("Accept", "application/json")
        identity().forEach { (name, value) -> builder.header(name, value) }
        if (authorized && accessToken.isNotBlank()) {
            builder.header("Authorization", "Bearer $accessToken")
            profileId?.let { builder.header("X-Profile-Id", it) }
            profileToken?.let { builder.header("X-Profile-Token", it) }
        }
        val requestBody = body?.toRequestBody(JSON)
        builder.method(method, if (method == "GET" || method == "DELETE") null else requestBody ?: "{}".toRequestBody(JSON))
        if (body != null) builder.header("Content-Type", "application/json")
        GatewayHttp.client.newCall(builder.build()).execute().use { response ->
            return HttpResult(response.code, response.body?.string().orEmpty())
        }
    }

    private fun buildUrl(path: String, query: Map<String, String>): String {
        val joined = SiloMediaUrl.resolve(baseUrl, path) ?: "$baseUrl$path"
        if (query.isEmpty()) return joined
        val joiner = if (joined.contains("?")) "&" else "?"
        val encoded = query.entries.joinToString("&") { (key, value) ->
            "${URLEncoder.encode(key, "UTF-8")}=${URLEncoder.encode(value, "UTF-8")}"
        }
        return joined + joiner + encoded
    }

    private fun errorMessage(body: String, status: Int): String {
        val json = SiloJson.objectOrNull(body)
        val message = json?.str("message") ?: json?.str("error") ?: json?.obj("error")?.str("message")
        if (!message.isNullOrBlank() && !message.trimStart().startsWith("<")) return message
        if (AccessGateway.isChallenge(status, emptyMap(), body)) return ZelefinException.accessGateway().message.orEmpty()
        return "The Silo server returned HTTP $status."
    }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")

    private fun jsonString(value: String): String = buildString {
        append('"')
        value.forEach { char ->
            when (char) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\n' -> append("\\n")
                else -> append(char)
            }
        }
        append('"')
    }

    private fun urlPath(value: String): String = URLEncoder.encode(value, "UTF-8").replace("+", "%20")

    private companion object {
        val JSON = "application/json".toMediaType()
    }
}

private data class CatalogHit(val item: MediaItem, val trailers: List<TitleTrailer>)
