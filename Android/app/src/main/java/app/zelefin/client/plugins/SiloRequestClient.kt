package app.zelefin.client.plugins

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.SiloJson
import app.zelefin.core.SiloMapper
import app.zelefin.core.SiloMediaUrl
import app.zelefin.core.ZelefinException
import app.zelefin.core.arr
import app.zelefin.core.bool
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import java.net.URI
import java.net.URLEncoder
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.abs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

enum class SiloRequestSource(val raw: String, val title: String) {
    Seerr("seerr", "Seerr"),
    Arr("arr", "Sonarr & Radarr"),
    ;

    companion object {
        fun fromRaw(raw: String?): SiloRequestSource? = entries.firstOrNull { it.raw == raw }

        fun matches(pluginId: String, source: SiloRequestSource): Boolean {
            val compact = pluginId.lowercase().filter { it.isLetterOrDigit() }
            return when (source) {
                Seerr -> compact.contains("seerr") || compact.contains("jellyseerr") || compact.contains("overseerr")
                Arr -> compact.contains("silo.request.arr") ||
                    compact.contains("silorequestsarr") ||
                    (compact.contains("request") && compact.contains("arr"))
            }
        }

        fun resolved(preferred: SiloRequestSource, seerr: Boolean, arr: Boolean): SiloRequestSource? = when (preferred) {
            Seerr -> if (seerr) Seerr else if (arr) Arr else null
            Arr -> if (arr) Arr else if (seerr) Seerr else null
        }

        fun discoverAvailable(
            requestsEnabled: Boolean,
            seerr: Boolean,
            arr: Boolean,
            preferred: SiloRequestSource,
        ): Boolean {
            if (!requestsEnabled) return false
            if (!seerr && !arr) return true
            return resolved(preferred, seerr, arr) != null
        }
    }
}

data class SiloPluginInstallation(
    val id: String,
    val pluginId: String,
    val version: String?,
    val enabled: Boolean?,
) {
    val isEnabled: Boolean get() = enabled ?: true

    companion object {
        fun parse(json: JsonObject) = SiloPluginInstallation(
            id = json.str("id").orEmpty(),
            pluginId = json.str("plugin_id").orEmpty(),
            version = json.str("version"),
            enabled = json.bool("enabled"),
        )
    }
}

data class SiloRequestFeatureStatus(
    val requestsEnabled: Boolean?,
    val allowed: Boolean?,
) {
    val isEnabled: Boolean get() = requestsEnabled == true

    companion object {
        fun parse(json: JsonObject) = SiloRequestFeatureStatus(
            requestsEnabled = json.bool("requests_enabled"),
            allowed = json.bool("allowed") ?: json.obj("capability")?.bool("allowed"),
        )
    }
}

/** Which request plugins a Silo server exposes, and whether requests are turned on. */
data class SiloRequestCapabilities(
    val seerrPluginAvailable: Boolean,
    val arrPluginAvailable: Boolean,
    val requestsEnabled: Boolean,
) {
    fun discoverAvailable(preferred: SiloRequestSource): Boolean = SiloRequestSource.discoverAvailable(
        requestsEnabled = requestsEnabled,
        seerr = seerrPluginAvailable,
        arr = arrPluginAvailable,
        preferred = preferred,
    )

    companion object {
        val None = SiloRequestCapabilities(seerrPluginAvailable = false, arrPluginAvailable = false, requestsEnabled = false)
    }
}

data class SiloRequestMediaState(
    val status: String?,
    val requestable: Boolean?,
    val requestId: String?,
) {
    companion object {
        fun parse(json: JsonObject) = SiloRequestMediaState(
            status = json.str("status"),
            requestable = json.bool("requestable"),
            requestId = json.str("request_id"),
        )
    }
}

data class SiloRequestMediaResult(
    val mediaType: String?,
    val tmdbId: Int?,
    val title: String?,
    val year: Int?,
    val overview: String?,
    val posterPath: String?,
    val availability: String?,
    val request: SiloRequestMediaState?,
) {
    fun asTitle(): SeerrTitle? {
        val id = tmdbId?.takeIf { it > 0 } ?: return null
        val name = title?.trim().orEmpty()
        if (name.isEmpty()) return null
        return SeerrTitle(
            tmdbId = id,
            kind = SeerrTitle.Kind.fromSilo(mediaType),
            name = name,
            year = year,
            overview = overview,
            posterUrl = SeerrClient.tmdbImageUrl(posterPath),
            availability = SeerrTitle.Availability.fromSilo(availability, request?.status, request?.requestable),
        )
    }

    companion object {
        fun parse(json: JsonObject) = SiloRequestMediaResult(
            mediaType = json.str("media_type"),
            tmdbId = json.int("tmdb_id"),
            title = json.str("title"),
            year = json.int("year"),
            overview = json.str("overview"),
            posterPath = json.str("poster_path"),
            availability = json.str("availability"),
            request = json.obj("request")?.let(SiloRequestMediaState::parse),
        )

        fun titles(json: JsonObject): List<SeerrTitle> = json.objects("results").mapNotNull { parse(it).asTitle() }
    }
}

data class SiloDiscoverSection(
    val key: String?,
    val title: String?,
    val page: Int?,
    val totalPages: Int?,
    val titles: List<SeerrTitle>,
) {
    companion object {
        fun parse(json: JsonObject) = SiloDiscoverSection(
            key = json.str("key"),
            title = json.str("title"),
            page = json.int("page"),
            totalPages = json.int("total_pages"),
            titles = SiloRequestMediaResult.titles(json),
        )
    }
}

data class SiloDiscoverBrand(
    val tmdbId: Int?,
    val slug: String?,
    val displayName: String?,
    val logoUrl: String?,
    val seriesSupported: Boolean?,
) {
    fun genreItem(mediaType: String): SeerrGenreSliderItem = SeerrGenreSliderItem(
        id = tmdbId ?: abs(slug?.hashCode() ?: 0),
        name = displayName ?: slug ?: "Genre",
        backdrops = null,
        siloSlug = slug,
        siloMediaType = mediaType,
    )

    fun company(kind: SeerrCompany.Kind): SeerrCompany? {
        val name = displayName?.trim().orEmpty()
        val slug = slug ?: return null
        if (name.isEmpty()) return null
        return SeerrCompany(
            id = tmdbId ?: abs(slug.hashCode()),
            name = name,
            kind = kind,
            imageUrl = logoUrl,
            siloSlug = slug,
        )
    }

    companion object {
        fun parse(json: JsonObject) = SiloDiscoverBrand(
            tmdbId = json.int("tmdb_id"),
            slug = json.str("slug"),
            displayName = json.str("display_name"),
            logoUrl = json.str("logo_url"),
            seriesSupported = json.bool("series_supported"),
        )
    }
}

data class SiloMediaRequest(
    val id: String?,
    val mediaType: String?,
    val tmdbId: Int?,
    val title: String?,
    val year: Int?,
    val overview: String?,
    val posterPath: String?,
    val status: String?,
) {
    fun asTitle(): SeerrTitle? {
        val tmdb = tmdbId?.takeIf { it > 0 } ?: return null
        val name = title?.trim().orEmpty()
        if (name.isEmpty()) return null
        return SeerrTitle(
            tmdbId = tmdb,
            kind = SeerrTitle.Kind.fromSilo(mediaType),
            name = name,
            year = year,
            overview = overview,
            posterUrl = SeerrClient.tmdbImageUrl(posterPath),
            availability = SeerrTitle.Availability.fromSiloRequestStatus(status),
            requestId = id?.toIntOrNull(),
        )
    }

    companion object {
        fun parse(json: JsonObject) = SiloMediaRequest(
            id = json.str("id"),
            mediaType = json.str("media_type"),
            tmdbId = json.int("tmdb_id"),
            title = json.str("title"),
            year = json.int("year"),
            overview = json.str("overview"),
            posterPath = json.str("poster_path"),
            status = json.str("status"),
        )
    }
}

/** Silo's first-party request API (`/api/v2/requests`), backed by its Seerr or Sonarr/Radarr plugin. */
class SiloRequestClient(
    val baseUrl: String,
    @Volatile var accessToken: String,
    @Volatile var refreshToken: String? = null,
    val profileId: String? = null,
    val profileToken: String? = null,
    private val identityHeaders: Map<String, String> = emptyMap(),
) : RequestCatalog {
    /** Called after a 401 triggers a successful token refresh. */
    var onTokensRefreshed: ((accessToken: String, refreshToken: String?) -> Unit)? = null

    override val oneTapRequests: Boolean = true

    suspend fun pluginSettings(): List<SiloPluginInstallation> =
        entries(getObject("/api/v2/settings/plugins")).map(SiloPluginInstallation::parse).filter { it.pluginId.isNotEmpty() }

    suspend fun adminPluginInstallations(): List<SiloPluginInstallation> =
        entries(getObject("/api/v2/admin/plugins/installations", mapOf("limit" to "100")))
            .map(SiloPluginInstallation::parse)
            .filter { it.pluginId.isNotEmpty() }

    suspend fun requestStatus(): SiloRequestFeatureStatus =
        SiloRequestFeatureStatus.parse(getObject("/api/v2/requests/status"))

    /** Mirrors iOS `detectSiloPlugins`: listed plugins, admin installations, then the request status flag. */
    suspend fun detectCapabilities(isAdministrator: Boolean): SiloRequestCapabilities {
        val pluginIds = mutableListOf<String>()
        attempt { pluginSettings() }?.let { listed -> pluginIds += listed.filter { it.isEnabled }.map { it.pluginId } }
        if (isAdministrator) {
            attempt { adminPluginInstallations() }?.let { admin -> pluginIds += admin.filter { it.isEnabled }.map { it.pluginId } }
        }
        val seerr = pluginIds.any { SiloRequestSource.matches(it, SiloRequestSource.Seerr) }
        val arr = pluginIds.any { SiloRequestSource.matches(it, SiloRequestSource.Arr) }
        val enabled = attempt { requestStatus() }?.isEnabled ?: (seerr || arr)
        return SiloRequestCapabilities(seerr, arr, enabled)
    }

    override suspend fun search(term: String): List<SeerrTitle> =
        SiloRequestMediaResult.titles(getObject("/api/v2/requests/search", mapOf("q" to term, "page" to "1")))

    override suspend fun discoverHome(): List<DiscoverSection> = discoverHomeData().sections()

    suspend fun discoverHomeData(): SeerrDiscoverHome = coroutineScope {
        val sections = async { attempt { discoverSections() }.orEmpty() }
        val mine = async { attempt { myRequests() }.orEmpty() }
        val genres = async { attempt { discoverBrands("genres") }.orEmpty() }
        val studios = async { attempt { discoverBrands("studios") }.orEmpty() }
        val networks = async { attempt { discoverBrands("networks") }.orEmpty() }
        val rows = sections.await()
        fun titles(key: String) = rows.firstOrNull { it.key == key }?.titles.orEmpty()
        val genreList = genres.await()
        SeerrDiscoverHome(
            recentRequests = mine.await().mapNotNull { it.asTitle() },
            trending = titles("trending_movies") + titles("trending_series"),
            popularMovies = titles("popular_movies"),
            upcomingMovies = titles("upcoming_movies"),
            popularTv = titles("popular_series"),
            upcomingTv = titles("on_air_series"),
            movieGenres = genreList.map { it.genreItem("movie") },
            tvGenres = genreList.filter { it.seriesSupported != false }.map { it.genreItem("series") },
            studios = studios.await().mapNotNull { it.company(SeerrCompany.Kind.Studio) },
            networks = networks.await().mapNotNull { it.company(SeerrCompany.Kind.Network) },
        )
    }

    override suspend fun discover(query: DiscoverQuery, page: Int): DiscoverPage = when (query) {
        DiscoverQuery.Requests -> DiscoverPage(myRequests().mapNotNull { it.asTitle() }, page = 1, totalPages = 1)
        is DiscoverQuery.SiloGenre -> browsePage(
            getObject(
                "/api/v2/requests/discover/browse/genre/${pathComponent(query.slug)}",
                mapOf("media_type" to query.mediaType, "page" to "$page"),
            ),
            page,
        )
        is DiscoverQuery.SiloStudio -> browse("studio", query.slug, page)
        is DiscoverQuery.SiloNetwork -> browse("network", query.slug, page)
        else -> {
            val section = query.siloSection
                ?: throw ZelefinException.server("That discovery row is not on this Silo server.")
            browsePage(getObject("/api/v2/requests/discover/$section", mapOf("page" to "$page")), page)
        }
    }

    override suspend fun request(title: SeerrTitle) {
        val body = buildJsonObject {
            put("media_type", if (title.kind == SeerrTitle.Kind.Tv) "series" else "movie")
            put("tmdb_id", title.tmdbId)
            put("title", title.name)
            title.year?.let { put("year", it) }
            title.overview?.let { put("overview", it) }
            title.posterUrl?.let(::tmdbPath)?.let { put("poster_path", it) }
        }
        send("/api/v2/requests", "POST", emptyMap(), body.toString())
    }

    suspend fun discoverSections(): List<SiloDiscoverSection> {
        val json = getObject("/api/v2/requests/discover")
        val rows = json.arr("items")?.let { json.objects("items") }
            ?: json.arr("entries")?.let { json.objects("entries") }
            ?: json.objects("sections")
        return rows.map(SiloDiscoverSection::parse)
    }

    suspend fun discoverBrands(path: String): List<SiloDiscoverBrand> =
        entries(getObject("/api/v2/requests/discover/$path")).map(SiloDiscoverBrand::parse)

    suspend fun myRequests(): List<SiloMediaRequest> =
        entries(getObject("/api/v2/requests/mine", mapOf("limit" to "50"))).map(SiloMediaRequest::parse)

    suspend fun adminRequests(): List<SiloMediaRequest> =
        entries(getObject("/api/v2/admin/requests", mapOf("limit" to "50"))).map(SiloMediaRequest::parse)

    private suspend fun browse(kind: String, slug: String, page: Int): DiscoverPage = browsePage(
        getObject("/api/v2/requests/discover/browse/$kind/${pathComponent(slug)}", mapOf("page" to "$page")),
        page,
    )

    private fun browsePage(json: JsonObject, page: Int) = DiscoverPage(
        titles = SiloRequestMediaResult.titles(json),
        page = json.int("page") ?: page,
        totalPages = maxOf(json.int("total_pages") ?: page, 1),
    )

    private fun entries(json: JsonObject): List<JsonObject> =
        json.arr("items")?.let { json.objects("items") } ?: json.objects("entries")

    private suspend fun getObject(path: String, query: Map<String, String> = emptyMap()): JsonObject {
        val body = send(path, "GET", query, null)
        return SiloJson.objectOrNull(body)
            ?: throw ZelefinException.server("The Silo server returned an unexpected response.")
    }

    private data class HttpResult(val status: Int, val headers: Map<String, String>, val body: String)

    private suspend fun send(path: String, method: String, query: Map<String, String>, body: String?): String =
        withContext(Dispatchers.IO) {
            var result = execute(path, method, query, body, authorized = true)
            if (result.status == 401 && !refreshToken.isNullOrBlank() && refresh()) {
                result = execute(path, method, query, body, authorized = true)
            }
            if (AccessGateway.isChallenge(result.status, result.headers, result.body)) {
                throw ZelefinException.accessGateway()
            }
            if (result.status !in 200..299) {
                throw ZelefinException.server(errorMessage(result.body, result.status))
            }
            result.body
        }

    private fun refresh(): Boolean {
        val token = refreshToken ?: return false
        val result = execute(
            "/api/v1/auth/refresh",
            "POST",
            emptyMap(),
            buildJsonObject { put("refresh_token", token) }.toString(),
            authorized = false,
        )
        val auth = SiloJson.objectOrNull(result.body)?.let(SiloMapper::auth) ?: return false
        accessToken = auth.accessToken
        refreshToken = auth.refreshToken ?: token
        onTokensRefreshed?.invoke(accessToken, refreshToken)
        return true
    }

    private fun execute(
        path: String,
        method: String,
        query: Map<String, String>,
        body: String?,
        authorized: Boolean,
    ): HttpResult {
        val builder = Request.Builder().url(buildUrl(path, query)).header("Accept", "application/json")
        identityHeaders.forEach { (name, value) -> builder.header(name, value) }
        if (authorized && accessToken.isNotBlank()) {
            builder.header("Authorization", "Bearer $accessToken")
            profileId?.let { builder.header("X-Profile-Id", it) }
            profileToken?.let { builder.header("X-Profile-Token", it) }
        }
        if (method == "GET") {
            builder.get()
        } else {
            builder.header("Content-Type", "application/json")
            builder.method(method, (body ?: "{}").toRequestBody(JSON))
        }
        GatewayHttp.client.newCall(builder.build()).execute().use { response ->
            val headers = response.headers.names().associateWith { response.headers[it].orEmpty() }
            return HttpResult(response.code, headers, response.body?.string().orEmpty())
        }
    }

    private fun buildUrl(path: String, query: Map<String, String>): String {
        val joined = SiloMediaUrl.resolve(baseUrl, path) ?: "$baseUrl$path"
        if (query.isEmpty()) return joined
        val joiner = if (joined.contains("?")) "&" else "?"
        return joined + joiner + query.entries.joinToString("&") { (key, value) ->
            "${URLEncoder.encode(key, "UTF-8")}=${URLEncoder.encode(value, "UTF-8")}"
        }
    }

    private fun errorMessage(body: String, status: Int): String {
        val json = SiloJson.objectOrNull(body)
        val message = json?.str("message")
            ?: json?.str("error")
            ?: json?.obj("error")?.str("message")
            ?: json?.str("detail")
        if (!message.isNullOrBlank() && !message.trimStart().startsWith("<")) return message
        val raw = body.trim()
        if (raw.isNotEmpty() && !raw.startsWith("<") && json == null) return raw
        return "The Silo server returned HTTP $status."
    }

    private companion object {
        val JSON = "application/json".toMediaType()

        suspend fun <T> attempt(block: suspend () -> T): T? = try {
            block()
        } catch (cancel: CancellationException) {
            throw cancel
        } catch (_: Exception) {
            null
        }

        fun pathComponent(value: String): String {
            val trimmed = value.trim()
            if (trimmed.isEmpty() || trimmed == "." || trimmed == "..") return trimmed
            return URLEncoder.encode(trimmed, "UTF-8").replace("+", "%20")
        }

        fun tmdbPath(url: String): String? {
            val path = runCatching { URI(url).path }.getOrNull() ?: return null
            val marker = path.indexOf("/t/p/")
            if (marker < 0) return null
            val rest = path.substring(marker + 5)
            val slash = rest.indexOf('/')
            if (slash < 0) return null
            return rest.substring(slash)
        }
    }
}
