package app.zelefin.client.silo

import app.zelefin.client.LibraryRoom
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
            LibraryRoom(id = id, name = name)
        }
    }

    suspend fun libraryItems(libraryId: String): List<MediaItem> {
        val movies = catalog("movie", libraryId)
        val shows = catalog("series", libraryId)
        return (movies + shows).distinctBy { it.id }
    }

    suspend fun catalog(type: String, libraryId: String? = null): List<MediaItem> = withContext(Dispatchers.IO) {
        val query = buildMap {
            put("type", type)
            put("sort", "added_at")
            put("order", "desc")
            put("limit", "80")
            put("image_size", "large")
            if (!libraryId.isNullOrBlank()) put("library_id", libraryId)
        }
        for (path in listOf("/api/v2/catalog", "/api/v1/catalog")) {
            val response = call(path, query = query)
            if (response.status !in 200..299) continue
            val element = runCatching { SiloJson.parse(response.body) }.getOrNull() ?: continue
            val items = SiloMapper.catalogItems(element, baseUrl)
            if (items.isNotEmpty()) return@withContext items
        }
        emptyList()
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

    suspend fun playback(item: MediaItem, appVersion: String, osVersion: String, model: String): PlaybackPlan =
        withContext(Dispatchers.IO) {
            val profile = profileId?.trim().orEmpty()
            if (profile.isEmpty()) throw ZelefinException.server("Select a profile before playing.")
            val playable = resolvePlayable(item)
            val fileId = playable.mediaSourceId?.toIntOrNull()
                ?: catalogItem(playable.id)?.mediaSourceId?.toIntOrNull()
                ?: throw ZelefinException.server("Silo did not return a playable file for this title.")
            val body = SiloMapper.playbackStart(
                fileId = fileId,
                profileId = profile,
                startPosition = playable.playbackPosition,
                attemptId = "zelefin:${UUID.randomUUID()}",
                appVersion = appVersion,
                osVersion = osVersion,
                model = model,
                formFactor = formFactor,
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
            )
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

    private fun identity(): Map<String, String> = mapOf(
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
