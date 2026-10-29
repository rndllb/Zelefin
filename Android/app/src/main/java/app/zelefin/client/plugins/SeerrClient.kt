package app.zelefin.client.plugins

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.LenientJson
import app.zelefin.core.ZelefinException
import app.zelefin.core.arr
import app.zelefin.core.bool
import app.zelefin.core.dbl
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import java.net.URLDecoder
import java.util.Locale
import kotlin.coroutines.cancellation.CancellationException
import kotlin.math.roundToLong
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.Cookie
import okhttp3.Headers
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class SeerrTitle(
    val tmdbId: Int,
    val kind: Kind,
    val name: String,
    val year: Int?,
    val overview: String?,
    val posterUrl: String?,
    val availability: Availability,
    val requestedByName: String? = null,
    val requestId: Int? = null,
    /** Seerr's own request status, separate from whether the title is on the server. */
    val review: Review? = null,
    /** Ombi's show request that holds [requestId], which is one batch of its seasons. */
    val parentRequestId: Int? = null,
) {
    enum class Kind(val raw: String, val accessibilityName: String) {
        Movie("movie", "Movie"),
        Tv("tv", "Show"),
        ;
    }

    enum class Availability {
        Unknown,
        Pending,
        Processing,
        Partial,
        Available,
        Missing,
        ;

        val isOnServer: Boolean get() = this == Available || this == Partial
        val isRequested: Boolean get() = this == Pending || this == Processing || this == Partial

        val canRequest: Boolean
            get() = when (this) {
                Missing, Unknown, Partial -> true
                Available, Pending, Processing -> false
            }

        val buttonTitle: String
            get() = when (this) {
                Available -> "In Library"
                Pending, Processing -> "Requested"
                Partial -> "Request More"
                Unknown, Missing -> "Request"
            }

        companion object {
            fun fromStatus(status: Int?): Availability = when (status) {
                2 -> Pending
                3 -> Processing
                4 -> Partial
                5 -> Available
                1 -> Unknown
                else -> Missing
            }
        }
    }

    enum class Review {
        PendingApproval,
        Approved,
        Declined,
        ;

        companion object {
            fun fromStatus(status: Int?): Review? = when (status) {
                1 -> PendingApproval
                2 -> Approved
                3 -> Declined
                else -> null
            }
        }
    }

    val id: String get() = requestId?.let { "request-$it" } ?: "${kind.raw}-$tmdbId"

    val canRequest: Boolean get() = availability.canRequest

    val buttonTitle: String get() = availability.buttonTitle

    /** True when this title is already on the Jellyfin server. */
    fun isInJellyfin(catalog: JellyfinTmdbCatalog): Boolean = availability.isOnServer || catalog.contains(this)
}

data class SeerrUser(
    val id: Int? = null,
    val email: String? = null,
    val username: String? = null,
    val displayName: String? = null,
    val jellyfinUsername: String? = null,
    val plexUsername: String? = null,
    val permissions: Int? = null,
) {
    /** Overseerr/Seerr: admin is bit 2, manage requests is bit 16. */
    val canManageRequests: Boolean
        get() {
            val bits = permissions ?: 0
            return bits and 2 != 0 || bits and 16 != 0
        }

    val displayLabel: String
        get() = listOf(username, jellyfinUsername, displayName, plexUsername, email)
            .mapNotNull { it?.trim() }
            .firstOrNull { it.isNotEmpty() } ?: "Seerr"

    /** A name suitable for a Recent Requests poster, or null when Seerr has no identity. */
    val requestLabel: String? get() = displayLabel.takeIf { it != "Seerr" }

    companion object {
        fun parse(json: JsonObject): SeerrUser = SeerrUser(
            id = json.int("id"),
            email = json.str("email"),
            username = json.str("username"),
            displayName = json.str("displayName"),
            jellyfinUsername = json.str("jellyfinUsername"),
            plexUsername = json.str("plexUsername"),
            permissions = json.int("permissions"),
        )
    }
}

data class SeerrCredentials(
    val username: String,
    val password: String,
) {
    fun toJson(): String = buildJsonObject {
        put("username", username)
        put("password", password)
    }.toString()

    companion object {
        fun fromJson(raw: String?): SeerrCredentials? {
            val json = raw?.let(LenientJson::objectOrNull) ?: return null
            val username = json.str("username").orEmpty()
            val password = json.str("password").orEmpty()
            if (username.isEmpty() || password.isEmpty()) return null
            return SeerrCredentials(username, password)
        }
    }
}

data class SeerrSession(
    val cookieName: String,
    val cookieValue: String,
    val displayName: String,
) {
    fun toJson(): String = buildJsonObject {
        put("cookieName", cookieName)
        put("cookieValue", cookieValue)
        put("displayName", displayName)
    }.toString()

    companion object {
        fun fromJson(raw: String?): SeerrSession? {
            val json = raw?.let(LenientJson::objectOrNull) ?: return null
            val name = json.str("cookieName") ?: return null
            val value = json.str("cookieValue") ?: return null
            return SeerrSession(name, value, json.str("displayName") ?: "Seerr")
        }
    }
}

class SeerrClient(
    val baseUrl: String,
    val session: SeerrSession?,
) {
    suspend fun search(term: String): List<SeerrTitle> {
        val payload = fetch(
            "api/v1/search",
            listOf("query" to term, "page" to "1", "language" to "en"),
        ) as? JsonObject ?: return emptyList()
        return SeerrSearchResponse.parse(payload).results.mapNotNull { title(it) }
    }

    suspend fun request(title: SeerrTitle) {
        request(
            SeerrRequestDraft(
                kind = title.kind,
                tmdbId = title.tmdbId,
                seasons = if (title.kind == SeerrTitle.Kind.Tv) SeerrSeasonSelection.All else null,
            ),
        )
    }

    suspend fun request(draft: SeerrRequestDraft) {
        post("api/v1/request", draft.toJson())
    }

    suspend fun approveRequest(id: Int, draft: SeerrRequestDraft) {
        post("api/v1/request/$id/approve", draft.toJson())
    }

    suspend fun requestDetails(id: Int): SeerrStoredRequest =
        SeerrStoredRequest.parse(fetchObject("api/v1/request/$id"))

    suspend fun declineRequest(id: Int) {
        post("api/v1/request/$id/decline", JsonObject(emptyMap()))
    }

    suspend fun radarrServers(): List<SeerrServiceServer> =
        (fetch("api/v1/service/radarr") as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(SeerrServiceServer::parse) }

    suspend fun sonarrServers(): List<SeerrServiceServer> =
        (fetch("api/v1/service/sonarr") as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(SeerrServiceServer::parse) }

    suspend fun radarrDetails(id: Int): SeerrServiceDetails =
        SeerrServiceDetails.parse(fetchObject("api/v1/service/radarr/$id")) ?: throw unexpected()

    suspend fun sonarrDetails(id: Int): SeerrServiceDetails =
        SeerrServiceDetails.parse(fetchObject("api/v1/service/sonarr/$id")) ?: throw unexpected()

    suspend fun tvDetails(id: Int): SeerrTvDetails =
        SeerrTvDetails.parse(fetchObject("api/v1/tv/$id")) ?: throw unexpected()

    suspend fun currentUser(): SeerrUser = SeerrUser.parse(fetchObject("api/v1/auth/me"))

    /** The title as it stands now: whether it's on the server, and its open request, if any. */
    suspend fun requestStatus(title: SeerrTitle): SeerrTitle {
        val path = if (title.kind == SeerrTitle.Kind.Movie) "api/v1/movie/${title.tmdbId}" else "api/v1/tv/${title.tmdbId}"
        val info = SeerrSearchResult.parse(fetchObject(path, listOf("language" to "en")))?.mediaInfo
        val availability = SeerrTitle.Availability.fromStatus(info?.status)
        val base = title.copy(availability = availability, review = null, requestId = null, requestedByName = null)
        if (availability == SeerrTitle.Availability.Available) return base
        val requests = info?.requests.orEmpty().filter { it.status != 3 }
        // A request waiting for approval comes first, then the newest approved one.
        val open = requests.lastOrNull { it.status == 1 } ?: requests.lastOrNull() ?: return base
        val review = SeerrTitle.Review.fromStatus(open.status)
        val waiting = review == SeerrTitle.Review.PendingApproval &&
            (availability == SeerrTitle.Availability.Missing || availability == SeerrTitle.Availability.Unknown)
        return base.copy(
            requestId = open.id,
            review = review,
            requestedByName = open.requestedBy?.requestLabel,
            availability = if (waiting) SeerrTitle.Availability.Pending else availability,
        )
    }

    suspend fun titleDetails(kind: SeerrTitle.Kind, tmdbId: Int): SeerrTitle {
        val path = if (kind == SeerrTitle.Kind.Movie) "api/v1/movie/$tmdbId" else "api/v1/tv/$tmdbId"
        val payload = SeerrSearchResult.parse(fetchObject(path, listOf("language" to "en")))
        return payload?.let { title(it, defaultKind = kind) }
            ?: throw ZelefinException.server("Seerr did not return that title.")
    }

    /** GETs [path] relative to the Seerr base URL and returns the parsed JSON body. */
    suspend fun fetch(path: String, query: List<Pair<String, String>> = emptyList()): JsonElement {
        val url = url(baseUrl, path, query)
        val response = withContext(Dispatchers.IO) { execute(url, "GET", null, cookieHeader()) }
        throwIfNeeded(response)
        return runCatching { LenientJson.parse(response.body) }.getOrElse { throw unexpected() }
    }

    private suspend fun fetchObject(path: String, query: List<Pair<String, String>> = emptyList()): JsonObject =
        fetch(path, query) as? JsonObject ?: throw unexpected()

    private suspend fun post(path: String, body: JsonObject) {
        val url = url(baseUrl, path, emptyList())
        val response = withContext(Dispatchers.IO) { execute(url, "POST", body.toString(), cookieHeader()) }
        throwIfNeeded(response)
    }

    private fun cookieHeader(): String? = session?.let(SeerrCookie::header)

    internal data class RawResponse(val status: Int, val headers: Headers, val body: String, val url: HttpUrl)

    companion object {
        private val JSON = "application/json".toMediaType()

        suspend fun signIn(baseUrl: String, username: String, password: String): SeerrSession {
            val trimmedName = username.trim()
            val trimmedPassword = password.trim()
            if (trimmedName.isEmpty()) throw ZelefinException.server("Enter your Seerr username.")
            if (trimmedPassword.isEmpty()) throw ZelefinException.server("Enter your Jellyfin or Seerr password.")
            return try {
                authenticate(baseUrl, "api/v1/auth/jellyfin", jellyfinBody(trimmedName, trimmedPassword))
            } catch (cancel: CancellationException) {
                throw cancel
            } catch (jellyfinError: Exception) {
                try {
                    authenticate(
                        baseUrl,
                        "api/v1/auth/local",
                        buildJsonObject {
                            put("email", trimmedName)
                            put("password", trimmedPassword)
                        },
                    )
                } catch (cancel: CancellationException) {
                    throw cancel
                } catch (_: Exception) {
                    throw jellyfinError
                }
            }
        }

        fun jellyfinBody(username: String, password: String): JsonObject = buildJsonObject {
            put("username", username)
            put("password", password)
        }

        private suspend fun authenticate(baseUrl: String, path: String, body: JsonObject): SeerrSession {
            val url = url(baseUrl, path, emptyList())
            val response = withContext(Dispatchers.IO) { execute(url, "POST", body.toString(), null) }
            throwIfNeeded(response)
            val cookie = SeerrCookie.parse(response.headers, response.url)
                ?: SeerrCookie.parse(response.headers, url)
                ?: throw ZelefinException.server("Seerr signed in but did not return a session cookie.")
            val user = LenientJson.objectOrNull(response.body)?.let(SeerrUser::parse)
            return SeerrSession(
                cookieName = cookie.first,
                cookieValue = cookie.second,
                displayName = user?.displayLabel ?: "Seerr",
            )
        }

        private fun url(baseUrl: String, path: String, query: List<Pair<String, String>>): HttpUrl {
            val base = baseUrl.trim().toHttpUrlOrNull() ?: throw ZelefinException.invalidServerUrl()
            val builder = base.newBuilder()
            val trimmed = path.trim('/')
            if (trimmed.isNotEmpty()) builder.addPathSegments(trimmed)
            query.forEach { (name, value) -> builder.addQueryParameter(name, value) }
            return builder.build()
        }

        private fun execute(url: HttpUrl, method: String, body: String?, cookie: String?): RawResponse {
            val builder = Request.Builder().url(url).header("Accept", "application/json")
            cookie?.let { builder.header("Cookie", it) }
            if (method == "GET") {
                builder.get()
            } else {
                builder.header("Content-Type", "application/json")
                builder.method(method, (body ?: "{}").toRequestBody(JSON))
            }
            GatewayHttp.client.newCall(builder.build()).execute().use { response ->
                return RawResponse(response.code, response.headers, response.body?.string().orEmpty(), response.request.url)
            }
        }

        private fun throwIfNeeded(response: RawResponse) {
            val headers = response.headers.names().associateWith { response.headers[it].orEmpty() }
            if (AccessGateway.isChallenge(response.status, headers, response.body)) {
                throw ZelefinException.accessGateway()
            }
            if (response.status == 401 || response.status == 403) {
                throw ZelefinException.seerrUnauthorized()
            }
            if (response.status !in 200..299) {
                throw ZelefinException.server(errorMessage(response.body, response.status))
            }
        }

        fun errorMessage(body: String, status: Int): String {
            val json = LenientJson.objectOrNull(body)
            if (json != null) {
                for (key in listOf("message", "error")) {
                    val value = (json[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                    if (!value.isNullOrBlank()) return value
                }
            }
            val raw = body.trim()
            if (raw.isNotEmpty()) return raw
            return "Seerr returned $status."
        }

        private fun unexpected() = ZelefinException.server("Seerr returned an unexpected response.")

        fun tmdbImageUrl(path: String?, size: String = "w342"): String? {
            if (path.isNullOrEmpty()) return null
            if (path.startsWith("http://") || path.startsWith("https://")) return path
            val trimmed = if (path.startsWith("/")) path else "/$path"
            return "https://image.tmdb.org/t/p/$size$trimmed"
        }

        fun title(result: SeerrSearchResult, defaultKind: SeerrTitle.Kind? = null): SeerrTitle? {
            if (result.mediaType == "person") return null
            val kind = when {
                result.mediaType == "tv" -> SeerrTitle.Kind.Tv
                result.mediaType == "movie" -> SeerrTitle.Kind.Movie
                defaultKind != null -> defaultKind
                else -> return null
            }
            val name = result.title ?: result.name ?: ""
            if (name.isEmpty()) return null
            val date = result.releaseDate ?: result.firstAirDate
            val year = date?.take(4)?.toIntOrNull()
            return SeerrTitle(
                tmdbId = result.id,
                kind = kind,
                name = name,
                year = year,
                overview = result.overview,
                posterUrl = tmdbImageUrl(result.posterPath),
                availability = SeerrTitle.Availability.fromStatus(result.mediaInfo?.status),
            )
        }
    }
}

object SeerrCookie {
    fun parse(setCookie: String): Pair<String, String>? {
        val firstPair = setCookie.split(";").firstOrNull { it.isNotEmpty() }?.trim().orEmpty()
        val separator = firstPair.indexOf('=')
        if (separator < 0) return null
        val name = firstPair.substring(0, separator).trim()
        var value = firstPair.substring(separator + 1)
        runCatching { URLDecoder.decode(value.replace("+", "%2B"), "UTF-8") }.getOrNull()?.let { value = it }
        if (name.isEmpty() || value.isEmpty()) return null
        return name to value
    }

    fun preferred(cookies: List<Pair<String, String>>): Pair<String, String>? {
        val match = cookies.firstOrNull { it.first == "connect.sid" } ?: cookies.firstOrNull() ?: return null
        return match.takeIf { it.second.isNotEmpty() }
    }

    fun parse(headers: Headers, url: HttpUrl): Pair<String, String>? {
        preferred(Cookie.parseAll(url, headers).map { it.name to it.value })?.let { return it }
        return headers.values("Set-Cookie").firstNotNullOfOrNull(::parse)
    }

    fun header(session: SeerrSession): String = "${session.cookieName}=${session.cookieValue}"
}

data class SeerrSearchResponse(
    val page: Int?,
    val totalPages: Int?,
    val results: List<SeerrSearchResult>,
) {
    companion object {
        fun parse(json: JsonObject) = SeerrSearchResponse(
            page = json.int("page"),
            totalPages = json.int("totalPages"),
            results = json.objects("results").mapNotNull(SeerrSearchResult::parse),
        )
    }
}

data class SeerrSearchResult(
    val id: Int,
    val mediaType: String? = null,
    val title: String? = null,
    val name: String? = null,
    val releaseDate: String? = null,
    val firstAirDate: String? = null,
    val overview: String? = null,
    val posterPath: String? = null,
    val mediaInfo: SeerrMediaInfo? = null,
) {
    companion object {
        fun parse(json: JsonObject): SeerrSearchResult? {
            val id = json.int("id") ?: return null
            return SeerrSearchResult(
                id = id,
                mediaType = json.str("mediaType"),
                title = json.str("title"),
                name = json.str("name"),
                releaseDate = json.str("releaseDate"),
                firstAirDate = json.str("firstAirDate"),
                overview = json.str("overview"),
                posterPath = json.str("posterPath"),
                mediaInfo = json.obj("mediaInfo")?.let(SeerrMediaInfo::parse),
            )
        }
    }
}

data class SeerrMediaInfo(
    val status: Int?,
    val seasons: List<SeerrMediaSeason>? = null,
    val tmdbId: Int? = null,
    val mediaType: String? = null,
    /** The title's requests, on a movie or show's own page. */
    val requests: List<SeerrMediaRequest>? = null,
) {
    companion object {
        fun parse(json: JsonObject) = SeerrMediaInfo(
            status = json.int("status"),
            seasons = json.arr("seasons")?.let { json.objects("seasons").mapNotNull(SeerrMediaSeason::parse) },
            tmdbId = json.int("tmdbId"),
            mediaType = json.str("mediaType"),
            requests = json.arr("requests")?.let { json.objects("requests").mapNotNull(SeerrMediaRequest::parse) },
        )
    }
}

data class SeerrMediaRequest(val id: Int, val status: Int?, val requestedBy: SeerrUser?) {
    companion object {
        fun parse(json: JsonObject): SeerrMediaRequest? {
            val id = json.int("id") ?: return null
            return SeerrMediaRequest(id, json.int("status"), json.obj("requestedBy")?.let(SeerrUser::parse))
        }
    }
}

data class SeerrMediaSeason(
    val seasonNumber: Int,
    val status: Int? = null,
    val status4k: Int? = null,
) {
    fun isOccupied(is4k: Boolean): Boolean {
        val value = if (is4k) status4k ?: status else status
        return value in listOf(2, 3, 4, 5)
    }

    companion object {
        fun parse(json: JsonObject): SeerrMediaSeason? {
            val number = json.int("seasonNumber") ?: return null
            return SeerrMediaSeason(number, json.int("status"), json.int("status4k"))
        }
    }
}

sealed class SeerrSeasonSelection {
    data object All : SeerrSeasonSelection()
    data class Numbers(val values: List<Int>) : SeerrSeasonSelection()
}

data class SeerrStoredRequest(
    val is4k: Boolean? = null,
    val serverId: Int? = null,
    val profileId: Int? = null,
    val rootFolder: String? = null,
    val languageProfileId: Int? = null,
    val seasons: List<SeerrStoredSeason>? = null,
) {
    companion object {
        fun parse(json: JsonObject) = SeerrStoredRequest(
            is4k = json.bool("is4k"),
            serverId = json.int("serverId"),
            profileId = json.int("profileId"),
            rootFolder = json.str("rootFolder"),
            languageProfileId = json.int("languageProfileId"),
            seasons = json.arr("seasons")?.let {
                json.objects("seasons").mapNotNull { season -> season.int("seasonNumber")?.let(::SeerrStoredSeason) }
            },
        )
    }
}

data class SeerrStoredSeason(val seasonNumber: Int)

data class SeerrRequestDraft(
    val kind: SeerrTitle.Kind,
    val tmdbId: Int,
    val seasons: SeerrSeasonSelection? = null,
    val is4k: Boolean = false,
    val serverId: Int? = null,
    val profileId: Int? = null,
    val rootFolder: String? = null,
    val languageProfileId: Int? = null,
    /** Ombi names a folder by its Radarr or Sonarr ID rather than its path. */
    val rootFolderId: Int? = null,
    /** Ombi's show request, whose quality and folder an admin changes before approving. */
    val parentRequestId: Int? = null,
) {
    fun toJson(): JsonObject = buildJsonObject {
        put("mediaType", kind.raw)
        put("mediaId", tmdbId)
        put("is4k", is4k)
        when (seasons) {
            SeerrSeasonSelection.All -> put("seasons", "all")
            is SeerrSeasonSelection.Numbers -> putJsonArray("seasons") { seasons.values.forEach { add(JsonPrimitive(it)) } }
            null -> Unit
        }
        serverId?.let { put("serverId", it) }
        profileId?.let { put("profileId", it) }
        rootFolder?.takeIf { it.isNotEmpty() }?.let { put("rootFolder", it) }
        languageProfileId?.let { put("languageProfileId", it) }
    }
}

data class SeerrServiceServer(
    val id: Int,
    val name: String,
    val is4k: Boolean? = null,
    val isDefault: Boolean? = null,
    val activeDirectory: String? = null,
    val activeProfileId: Int? = null,
    val activeLanguageProfileId: Int? = null,
) {
    val uses4K: Boolean get() = is4k ?: false
    val isDefaultServer: Boolean get() = isDefault ?: false

    companion object {
        fun parse(json: JsonObject): SeerrServiceServer? {
            val id = json.int("id") ?: return null
            return SeerrServiceServer(
                id = id,
                name = json.str("name") ?: "Server $id",
                is4k = json.bool("is4k"),
                isDefault = json.bool("isDefault"),
                activeDirectory = json.str("activeDirectory"),
                activeProfileId = json.int("activeProfileId"),
                activeLanguageProfileId = json.int("activeLanguageProfileId"),
            )
        }
    }
}

data class SeerrServiceProfile(val id: Int, val name: String) {
    companion object {
        fun parse(json: JsonObject): SeerrServiceProfile? {
            val id = json.int("id") ?: return null
            val name = json.str("name") ?: return null
            return SeerrServiceProfile(id, name)
        }
    }
}

data class SeerrRootFolder(
    val folderId: Int? = null,
    val path: String,
    val freeSpace: Double? = null,
) {
    val id: String get() = path

    val pickerTitle: String
        get() {
            val free = freeSpace ?: return path
            return "$path · ${formatBytes(free)} free"
        }

    companion object {
        fun parse(json: JsonObject): SeerrRootFolder? {
            val path = json.str("path") ?: return null
            return SeerrRootFolder(json.int("id"), path, json.dbl("freeSpace"))
        }

        private fun formatBytes(bytes: Double): String {
            val units = listOf("bytes", "KB", "MB", "GB", "TB", "PB")
            var value = bytes
            var index = 0
            while (value >= 1000 && index < units.lastIndex) {
                value /= 1000
                index++
            }
            return when {
                index == 0 -> "${value.roundToLong()} bytes"
                value >= 100 || value % 1.0 == 0.0 -> "${value.roundToLong()} ${units[index]}"
                else -> String.format(Locale.US, "%.1f %s", value, units[index])
            }
        }
    }
}

data class SeerrServiceDetails(
    val server: SeerrServiceServer,
    val profiles: List<SeerrServiceProfile>,
    val rootFolders: List<SeerrRootFolder>,
    val languageProfiles: List<SeerrServiceProfile>? = null,
) {
    companion object {
        fun parse(json: JsonObject): SeerrServiceDetails? {
            val server = json.obj("server")?.let(SeerrServiceServer::parse) ?: return null
            return SeerrServiceDetails(
                server = server,
                profiles = json.objects("profiles").mapNotNull(SeerrServiceProfile::parse),
                rootFolders = json.objects("rootFolders").mapNotNull(SeerrRootFolder::parse),
                languageProfiles = json.arr("languageProfiles")?.let {
                    json.objects("languageProfiles").mapNotNull(SeerrServiceProfile::parse)
                },
            )
        }
    }
}

data class SeerrTvDetails(
    val id: Int,
    val name: String?,
    val seasons: List<SeerrSeason>,
    val mediaInfo: SeerrMediaInfo?,
    val relatedVideos: List<SeerrRelatedVideo>?,
) {
    companion object {
        fun parse(json: JsonObject): SeerrTvDetails? {
            val id = json.int("id") ?: return null
            return SeerrTvDetails(
                id = id,
                name = json.str("name"),
                seasons = json.objects("seasons").mapNotNull(SeerrSeason::parse),
                mediaInfo = json.obj("mediaInfo")?.let(SeerrMediaInfo::parse),
                relatedVideos = json.arr("relatedVideos")?.let {
                    json.objects("relatedVideos").map(SeerrRelatedVideo::parse)
                },
            )
        }
    }
}

data class SeerrRelatedVideo(
    val key: String? = null,
    val name: String? = null,
    val site: String? = null,
    val type: String? = null,
    val url: String? = null,
    val official: Boolean? = null,
) {
    companion object {
        fun parse(json: JsonObject) = SeerrRelatedVideo(
            key = json.str("key"),
            name = json.str("name"),
            site = json.str("site"),
            type = json.str("type"),
            url = json.str("url"),
            official = json.bool("official"),
        )
    }
}

data class SeerrSeason(
    val name: String?,
    val seasonNumber: Int,
    val episodeCount: Int? = null,
    val airDate: String? = null,
) {
    val id: Int get() = seasonNumber
    val isSpecials: Boolean get() = seasonNumber == 0

    val title: String
        get() {
            if (isSpecials) return name ?: "Specials"
            if (!name.isNullOrEmpty() && name != "Season $seasonNumber") return "Season $seasonNumber · $name"
            return "Season $seasonNumber"
        }

    companion object {
        fun parse(json: JsonObject): SeerrSeason? {
            val number = json.int("seasonNumber") ?: return null
            return SeerrSeason(json.str("name"), number, json.int("episodeCount"), json.str("airDate"))
        }
    }
}

object SeerrRequestDefaults {
    fun preferredServer(servers: List<SeerrServiceServer>, is4k: Boolean): SeerrServiceServer? {
        val matching = servers.filter { it.uses4K == is4k }
        return matching.firstOrNull { it.isDefaultServer } ?: matching.firstOrNull() ?: servers.firstOrNull()
    }
}
