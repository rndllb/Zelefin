package app.zelefin.client.plugins

import app.zelefin.client.network.GatewayHttp
import app.zelefin.core.AccessGateway
import app.zelefin.core.LenientJson
import app.zelefin.core.ZelefinException
import app.zelefin.core.bool
import app.zelefin.core.dbl
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

data class OmbiSession(val token: String, val displayName: String) {
    fun toJson(): String = buildJsonObject {
        put("token", token)
        put("displayName", displayName)
    }.toString()

    companion object {
        fun fromJson(raw: String?): OmbiSession? {
            val json = raw?.let(LenientJson::objectOrNull) ?: return null
            val token = json.str("token") ?: return null
            return OmbiSession(token, json.str("displayName") ?: "Ombi")
        }
    }
}

/**
 * Mirrors iOS `OmbiClient`: Ombi v4's API. Ombi decides the Radarr or Sonarr server, quality, and
 * folder itself, so requests only name the title and, for shows, the seasons.
 */
class OmbiClient(
    val baseUrl: String,
    val session: OmbiSession?,
) : RequestCatalog {
    override val service = RequestService.Ombi

    /** Admins and power users pick the quality and folder from Ombi's Radarr and Sonarr. */
    override val choosesDownloadServer = true

    override suspend fun currentUser(): SeerrUser {
        val user = send("api/v1/Identity") as? JsonObject ?: throw unexpected()
        return SeerrUser(
            email = user.str("emailAddress"),
            username = userLabel(user),
            permissions = if (canManageRequests(user)) 2 else 0,
        )
    }

    /** Ombi's search has no request state, so each result is looked up for it, as Ombi's own site does. */
    override suspend fun search(term: String): List<SeerrTitle> = coroutineScope {
        val filter = buildJsonObject {
            put("movies", true)
            put("tvShows", true)
            put("music", false)
            put("people", false)
        }
        val results = (send("api/v2/Search/multi/${encode(term)}", "POST", filter) as? JsonArray).orEmpty()
        results.mapNotNull { (it as? JsonObject)?.let(::multiTitle) }.take(PAGE_SIZE).map { basic ->
            async {
                val detailed = runCatching { titleDetails(basic.kind, basic.tmdbId) }.getOrNull() ?: basic
                if (detailed.posterUrl == null) detailed.copy(posterUrl = basic.posterUrl) else detailed
            }
        }.awaitAll()
    }

    override suspend fun discoverHome(): List<DiscoverSection> = coroutineScope {
        val queries = listOf(
            DiscoverQuery.Requests,
            DiscoverQuery.Trending,
            DiscoverQuery.PopularMovies,
            DiscoverQuery.UpcomingMovies,
            DiscoverQuery.PopularTv,
            DiscoverQuery.UpcomingTv,
        )
        queries.map { query -> query to async { runCatching { discover(query, 1).titles }.getOrDefault(emptyList()) } }
            .map { (query, titles) -> DiscoverSection(query.key, query.title, query, titles = titles.await()) }
            .filterNot { it.isEmpty }
    }

    override suspend fun discover(query: DiscoverQuery, page: Int): DiscoverPage = coroutineScope {
        val position = (page - 1) * PAGE_SIZE
        val titles = when (query) {
            DiscoverQuery.Requests -> recentRequests(position)
            DiscoverQuery.Trending -> {
                val movies = async { movieList("nowplaying", position) }
                val shows = async { tvList("trending", position) }
                interleave(movies.await(), shows.await())
            }
            DiscoverQuery.PopularMovies -> movieList("popular", position)
            DiscoverQuery.UpcomingMovies -> movieList("upcoming", position)
            DiscoverQuery.PopularTv -> tvList("popular", position)
            DiscoverQuery.UpcomingTv -> tvList("anticipated", position)
            is DiscoverQuery.MovieGenre, is DiscoverQuery.TvGenre, is DiscoverQuery.Studio, is DiscoverQuery.Network -> emptyList()
        }
        DiscoverPage(titles, page, if (titles.size >= PAGE_SIZE) page + 1 else page)
    }

    override suspend fun request(title: SeerrTitle) {
        request(
            SeerrRequestDraft(
                kind = title.kind,
                tmdbId = title.tmdbId,
                seasons = if (title.kind == SeerrTitle.Kind.Tv) SeerrSeasonSelection.All else null,
            ),
        )
    }

    override suspend fun requestStatus(title: SeerrTitle): SeerrTitle {
        // A show's full details carry no poster path, so the poster, year, and overview it came with are kept.
        val current = titleDetails(title.kind, title.tmdbId)?.let { detailed ->
            detailed.copy(
                requestedByName = null,
                posterUrl = detailed.posterUrl ?: title.posterUrl,
                year = detailed.year ?: title.year,
                overview = detailed.overview ?: title.overview,
            )
        } ?: return title
        val requestId = current.requestId
        if (requestId == null || current.availability == SeerrTitle.Availability.Available) return current
        return when (title.kind) {
            SeerrTitle.Kind.Movie -> {
                val request = runCatching { send("api/v1/Request/movie/info/$requestId") as? JsonObject }.getOrNull()
                current.copy(requestedByName = request?.let(::requesterLabel))
            }
            SeerrTitle.Kind.Tv -> {
                // The show's request holds one request per batch of seasons; the one waiting comes first.
                val show = send("api/v1/Request/tv/$requestId") as? JsonObject
                val children = show?.objects("childRequests").orEmpty()
                val open = children.lastOrNull { it.bool("approved") != true && it.bool("denied") != true && it.bool("available") != true }
                    ?: children.lastOrNull { it.bool("denied") != true }
                val base = current.copy(parentRequestId = requestId, requestId = null)
                if (open == null) return base
                val reviewed = base.reviewed(open, open.int("id") ?: return base)
                if (current.availability == SeerrTitle.Availability.Partial) reviewed.copy(availability = SeerrTitle.Availability.Partial) else reviewed
            }
        }
    }

    override suspend fun tvDetails(id: Int): SeerrTvDetails {
        val show = send("api/v2/Search/tv/moviedb/$id") as? JsonObject ?: throw unexpected()
        val seasons = show.objects("seasonRequests").mapNotNull(::season).sortedBy { it.number }
        return SeerrTvDetails(
            id = id,
            name = show.str("title"),
            seasons = seasons.map { SeerrSeason(null, it.number, it.episodes.size) },
            mediaInfo = SeerrMediaInfo(
                status = null,
                seasons = seasons.map { SeerrMediaSeason(it.number, if (it.isTaken) 2 else 1) },
            ),
            relatedVideos = null,
        )
    }

    override suspend fun request(draft: SeerrRequestDraft) {
        when (draft.kind) {
            SeerrTitle.Kind.Movie -> requireAccepted(
                send(
                    "api/v1/Request/movie",
                    "POST",
                    buildJsonObject {
                        put("theMovieDbId", draft.tmdbId)
                        put("languageCode", "en")
                        put("is4kRequest", draft.is4k)
                        putOverrides(draft)
                    },
                ),
            )
            SeerrTitle.Kind.Tv -> requireAccepted(send("api/v2/Requests/tv", "POST", showRequestBody(draft)))
        }
    }

    /** An admin's quality and folder choice. Ombi ignores these from other users. */
    private fun kotlinx.serialization.json.JsonObjectBuilder.putOverrides(draft: SeerrRequestDraft) {
        draft.profileId?.let { put("qualityPathOverride", it) }
        draft.rootFolderId?.let { put("rootFolderOverride", it) }
        if (draft.kind == SeerrTitle.Kind.Tv) draft.languageProfileId?.let { put("languageProfile", it) }
    }

    /** Ombi requests episodes, so each picked season lists the episodes not yet requested or on the server. */
    private suspend fun showRequestBody(draft: SeerrRequestDraft): JsonObject {
        val show = send("api/v2/Search/tv/moviedb/${draft.tmdbId}") as? JsonObject ?: throw unexpected()
        val all = show.objects("seasonRequests").mapNotNull(::season)
        val picked = when (val seasons = draft.seasons) {
            is SeerrSeasonSelection.Numbers -> all.filter { it.number in seasons.values }
            SeerrSeasonSelection.All, null -> all.filter { it.number > 0 }
        }
        return buildJsonObject {
            put("theMovieDbId", draft.tmdbId)
            put("languageCode", "en")
            put("requestAll", false)
            put("latestSeason", false)
            put("firstSeason", false)
            putOverrides(draft)
            putJsonArray("seasons") {
                picked.forEach { season ->
                    val open = season.episodes.filterNot { it.taken }
                    if (open.isEmpty()) return@forEach
                    add(
                        buildJsonObject {
                            put("seasonNumber", season.number)
                            put("episodes", buildJsonArray { open.forEach { add(buildJsonObject { put("episodeNumber", it.number) }) } })
                        },
                    )
                }
            }
        }
    }

    override suspend fun approveRequest(id: Int, draft: SeerrRequestDraft) {
        saveAdvancedOptions(id, draft)
        when (draft.kind) {
            SeerrTitle.Kind.Movie -> requireAccepted(
                send(
                    "api/v1/Request/movie/approve",
                    "POST",
                    buildJsonObject {
                        put("id", id)
                        put("is4K", draft.is4k)
                    },
                ),
            )
            SeerrTitle.Kind.Tv -> requireAccepted(send("api/v1/Request/tv/approve", "POST", buildJsonObject { put("id", id) }))
        }
    }

    override suspend fun declineRequest(id: Int, kind: SeerrTitle.Kind) {
        val body = buildJsonObject {
            put("id", id)
            put("reason", "")
            if (kind == SeerrTitle.Kind.Movie) put("is4K", false)
        }
        val path = if (kind == SeerrTitle.Kind.Movie) "api/v1/Request/movie/deny" else "api/v1/Request/tv/deny"
        requireAccepted(send(path, "PUT", body))
    }

    /** An admin's edit before approving: the quality and folder the request downloads with. */
    private suspend fun saveAdvancedOptions(requestId: Int, draft: SeerrRequestDraft) {
        if (draft.profileId == null && draft.rootFolderId == null && draft.languageProfileId == null) return
        val target = if (draft.kind == SeerrTitle.Kind.Movie) requestId else draft.parentRequestId ?: requestId
        val kind = if (draft.kind == SeerrTitle.Kind.Movie) "movie" else "tv"
        requireAccepted(
            send(
                "api/v2/Requests/$kind/advancedoptions",
                "POST",
                buildJsonObject {
                    put("requestId", target)
                    put("qualityOverride", draft.profileId ?: 0)
                    put("rootPathOverride", draft.rootFolderId ?: 0)
                    put("languageProfile", draft.languageProfileId ?: 0)
                },
            ),
        )
    }

    /** A movie request's quality and folder, for an admin reviewing it. Shows keep theirs on the show's request. */
    override suspend fun requestDetails(id: Int): SeerrStoredRequest {
        val request = send("api/v1/Request/movie/info/$id") as? JsonObject ?: throw unexpected()
        val folderId = request.int("rootPathOverride")?.takeIf { it > 0 }
        val folder = folderId?.let { wanted ->
            runCatching { rootFolders("Radarr") }.getOrDefault(emptyList()).firstOrNull { it.folderId == wanted }?.path
        }
        return SeerrStoredRequest(
            is4k = request.bool("is4kRequest"),
            serverId = 0,
            profileId = request.int("qualityOverride")?.takeIf { it > 0 },
            rootFolder = folder,
        )
    }

    /** Ombi has one Radarr (and one Sonarr), shown as a single server when it's set up. */
    override suspend fun radarrServers(): List<SeerrServiceServer> =
        if (profiles("api/v1/Radarr/Profiles").isEmpty()) emptyList() else listOf(server("Radarr"))

    override suspend fun sonarrServers(): List<SeerrServiceServer> =
        if (profiles("api/v1/Sonarr/Profiles").isEmpty()) emptyList() else listOf(server("Sonarr"))

    override suspend fun radarrDetails(id: Int): SeerrServiceDetails = coroutineScope {
        val profiles = async { profiles("api/v1/Radarr/Profiles") }
        val folders = async { rootFolders("Radarr") }
        SeerrServiceDetails(server("Radarr"), profiles.await(), folders.await())
    }

    override suspend fun sonarrDetails(id: Int): SeerrServiceDetails = coroutineScope {
        val profiles = async { profiles("api/v1/Sonarr/Profiles") }
        val folders = async { rootFolders("Sonarr") }
        // Sonarr v4 has no language profiles and reports a placeholder called Deprecated.
        val languages = async { runCatching { profiles("api/v1/Sonarr/v3/LanguageProfiles") }.getOrNull()?.filter { it.name != "Deprecated" } }
        SeerrServiceDetails(server("Sonarr"), profiles.await(), folders.await(), languages.await())
    }

    private fun server(name: String) = SeerrServiceServer(id = 0, name = name, isDefault = true)

    private suspend fun profiles(path: String): List<SeerrServiceProfile> =
        (send(path) as? JsonArray).orEmpty().mapNotNull { element ->
            val json = element as? JsonObject ?: return@mapNotNull null
            val id = json.int("id") ?: return@mapNotNull null
            SeerrServiceProfile(id, json.str("name") ?: "Profile $id")
        }

    private suspend fun rootFolders(service: String): List<SeerrRootFolder> =
        (send("api/v1/$service/RootFolders") as? JsonArray).orEmpty().mapNotNull { element ->
            val json = element as? JsonObject ?: return@mapNotNull null
            val path = json.str("path") ?: return@mapNotNull null
            SeerrRootFolder(folderId = json.int("id"), path = path, freeSpace = json.dbl("freeSpace"))
        }

    private suspend fun movieList(list: String, position: Int): List<SeerrTitle> =
        (send("api/v2/Search/movie/$list/$position/$PAGE_SIZE") as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::movieTitle) }

    private suspend fun tvList(list: String, position: Int): List<SeerrTitle> =
        (send("api/v2/Search/tv/$list/$position/$PAGE_SIZE") as? JsonArray).orEmpty().mapNotNull { (it as? JsonObject)?.let(::showTitle) }

    private suspend fun titleDetails(kind: SeerrTitle.Kind, tmdbId: Int): SeerrTitle? = when (kind) {
        SeerrTitle.Kind.Movie -> (send("api/v2/Search/movie/$tmdbId") as? JsonObject)?.let(::movieTitle)
        SeerrTitle.Kind.Tv -> (send("api/v2/Search/tv/moviedb/$tmdbId") as? JsonObject)?.let(::showTitle)
    }

    /** Movie and show requests together, newest first. */
    private suspend fun recentRequests(position: Int): List<SeerrTitle> = coroutineScope {
        val movies = async { runCatching { send("api/v2/Requests/movie/$PAGE_SIZE/$position/requestedDate/desc") }.getOrNull() }
        val shows = async { runCatching { send("api/v2/Requests/tv/$PAGE_SIZE/$position/requestedDate/desc") }.getOrNull() }
        val dated = (movies.await() as? JsonObject)?.objects("collection").orEmpty().mapNotNull { request ->
            movieRequestTitle(request)?.let { (request.str("requestedDate") ?: "") to it }
        } + (shows.await() as? JsonObject)?.objects("collection").orEmpty().mapNotNull { request ->
            showRequestTitle(request)?.let { (request.str("requestedDate") ?: "") to it }
        }
        dated.sortedByDescending { it.first }.take(PAGE_SIZE).map { it.second }
    }

    private suspend fun send(path: String, method: String = "GET", body: JsonObject? = null): JsonElement {
        val url = url(baseUrl, path)
        val response = withContext(Dispatchers.IO) { execute(url, method, body?.toString(), session?.token) }
        throwIfNeeded(response)
        return runCatching { LenientJson.parse(response.third) }.getOrElse { throw unexpected() }
    }

    private fun requireAccepted(result: JsonElement) {
        val json = result as? JsonObject ?: return
        if (json.bool("isError") != true && json.bool("result") != false) return
        val message = listOf("errorMessage", "message").firstNotNullOfOrNull { json.str(it) }
        throw ZelefinException.server(message ?: "Ombi didn't take the request.")
    }

    private data class OmbiEpisode(val number: Int, val taken: Boolean)

    private data class OmbiSeason(val number: Int, val episodes: List<OmbiEpisode>) {
        /** Every episode is on the server or already requested. */
        val isTaken: Boolean get() = episodes.isNotEmpty() && episodes.all { it.taken }
    }

    private fun season(json: JsonObject): OmbiSeason? {
        val number = json.int("seasonNumber") ?: return null
        val episodes = json.objects("episodes").mapNotNull { episode ->
            val episodeNumber = episode.int("episodeNumber") ?: return@mapNotNull null
            val taken = episode.bool("available") == true || episode.bool("requested") == true || episode.bool("approved") == true
            OmbiEpisode(episodeNumber, taken)
        }
        return OmbiSeason(number, episodes)
    }

    companion object {
        /** A page of a Discover row. */
        private const val PAGE_SIZE = 20
        private val JSON = "application/json".toMediaType()

        /** Ombi signs in its own users and those imported from Jellyfin or Emby, with that server's password. */
        suspend fun signIn(baseUrl: String, username: String, password: String): OmbiSession {
            val name = username.trim()
            if (name.isEmpty()) throw ZelefinException.server("Enter your Ombi username.")
            if (password.isEmpty()) throw ZelefinException.server("Enter your Ombi password.")
            val body = buildJsonObject {
                put("username", name)
                put("password", password)
                put("rememberMe", true)
                put("usePlexAdminAccount", false)
                put("usePlexOAuth", false)
            }
            val anonymous = OmbiClient(baseUrl, null)
            val token = try {
                (anonymous.send("api/v1/Token", "POST", body) as? JsonObject)?.str("access_token")
            } catch (error: ZelefinException) {
                if (error.code == ZelefinException.Code.SeerrUnauthorized) {
                    throw ZelefinException.server("Ombi didn't accept that username and password.")
                }
                throw error
            } ?: throw ZelefinException.server("Ombi signed in but didn't return a token.")
            val session = OmbiSession(token, name)
            val label = runCatching { (OmbiClient(baseUrl, session).send("api/v1/Identity") as? JsonObject)?.let(::userLabel) }.getOrNull()
            return session.copy(displayName = label ?: name)
        }

        private fun requesterLabel(request: JsonObject): String? =
            request.obj("requestedUser")?.let { user -> listOf("alias", "userName").firstNotNullOfOrNull { user.str(it) } }

        private fun userLabel(user: JsonObject): String? =
            listOf("alias", "userName", "emailAddress").firstNotNullOfOrNull { user.str(it) }

        /** Admins and power users approve and decline requests. */
        private fun canManageRequests(user: JsonObject): Boolean = user.objects("claims").any { claim ->
            claim.bool("enabled") == true && claim.str("value") in setOf("Admin", "PowerUser")
        }

        /** Ombi names search results "Dune (2021)". */
        internal fun splitYear(raw: String): Pair<String, Int?> {
            val match = Regex("^(.*\\S)\\s*\\((\\d{4})\\)$").find(raw) ?: return raw to null
            return match.groupValues[1] to match.groupValues[2].toInt()
        }

        private fun multiTitle(json: JsonObject): SeerrTitle? {
            val tmdbId = json.str("id")?.toIntOrNull() ?: return null
            val (name, year) = splitYear(json.str("title") ?: return null)
            val kind = when (json.str("mediaType")) {
                "movie" -> SeerrTitle.Kind.Movie
                "tv" -> SeerrTitle.Kind.Tv
                else -> return null
            }
            return SeerrTitle(tmdbId, kind, name, year, json.str("overview"), SeerrClient.tmdbImageUrl(json.str("poster")), SeerrTitle.Availability.Missing)
        }

        private fun movieTitle(json: JsonObject): SeerrTitle? {
            val tmdbId = json.str("theMovieDbId")?.toIntOrNull() ?: json.int("id") ?: return null
            val name = json.str("title") ?: return null
            return SeerrTitle(
                tmdbId = tmdbId,
                kind = SeerrTitle.Kind.Movie,
                name = name,
                year = json.str("releaseDate")?.take(4)?.toIntOrNull(),
                overview = json.str("overview"),
                posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath")),
                availability = SeerrTitle.Availability.Missing,
            ).withState(json)
        }

        private fun showTitle(json: JsonObject): SeerrTitle? {
            val tmdbId = json.str("theMovieDbId")?.toIntOrNull() ?: json.int("id") ?: return null
            val name = json.str("title") ?: return null
            val title = SeerrTitle(
                tmdbId = tmdbId,
                kind = SeerrTitle.Kind.Tv,
                name = name,
                year = json.str("firstAired")?.take(4)?.toIntOrNull(),
                overview = json.str("overview"),
                posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath")),
                availability = SeerrTitle.Availability.Missing,
            ).withState(json)
            return title
        }

        /** The request and library state Ombi puts on every movie and show it returns. */
        private fun SeerrTitle.withState(json: JsonObject): SeerrTitle {
            val available = json.bool("available") == true
            val requested = json.bool("requested") == true
            val approved = json.bool("approved") == true
            val denied = json.bool("denied") == true
            // A partly downloaded show is `available` and `partlyAvailable` at once, so the partial check comes first.
            val availability = when {
                json.bool("partlyAvailable") == true -> SeerrTitle.Availability.Partial
                available -> SeerrTitle.Availability.Available
                denied -> SeerrTitle.Availability.Missing
                requested -> if (approved) SeerrTitle.Availability.Processing else SeerrTitle.Availability.Pending
                else -> SeerrTitle.Availability.Missing
            }
            val review = when {
                !requested || available -> null
                denied -> SeerrTitle.Review.Declined
                approved -> SeerrTitle.Review.Approved
                else -> SeerrTitle.Review.PendingApproval
            }
            return copy(availability = availability, review = review, requestId = json.int("requestId")?.takeIf { it > 0 } ?: requestId)
        }

        private fun movieRequestTitle(json: JsonObject): SeerrTitle? {
            val id = json.int("id") ?: return null
            val tmdbId = json.int("theMovieDbId") ?: return null
            val name = json.str("title") ?: return null
            val title = SeerrTitle(
                tmdbId = tmdbId,
                kind = SeerrTitle.Kind.Movie,
                name = name,
                year = json.str("releaseDate")?.take(4)?.toIntOrNull(),
                overview = json.str("overview"),
                posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath")),
                availability = SeerrTitle.Availability.Pending,
            )
            return title.reviewed(json, id)
        }

        private fun showRequestTitle(json: JsonObject): SeerrTitle? {
            val id = json.int("id") ?: return null
            val parentId = json.int("parentRequestId")
            val parent = json.obj("parentRequest") ?: return null
            val tmdbId = parent.int("externalProviderId") ?: return null
            val name = parent.str("title") ?: return null
            val title = SeerrTitle(
                tmdbId = tmdbId,
                kind = SeerrTitle.Kind.Tv,
                name = name,
                year = parent.str("releaseDate")?.take(4)?.toIntOrNull(),
                overview = parent.str("overview"),
                posterUrl = SeerrClient.tmdbImageUrl(parent.str("posterPath")),
                availability = SeerrTitle.Availability.Pending,
                parentRequestId = parentId,
            )
            return title.reviewed(json, id)
        }

        /** A request's review state: approved, declined, or waiting. */
        private fun SeerrTitle.reviewed(json: JsonObject, requestId: Int): SeerrTitle {
            val base = copy(requestId = requestId, requestedByName = requesterLabel(json))
            return when {
                json.bool("available") == true -> base.copy(availability = SeerrTitle.Availability.Available, review = null)
                json.bool("denied") == true -> base.copy(availability = SeerrTitle.Availability.Missing, review = SeerrTitle.Review.Declined)
                json.bool("approved") == true -> base.copy(availability = SeerrTitle.Availability.Processing, review = SeerrTitle.Review.Approved)
                else -> base.copy(availability = SeerrTitle.Availability.Pending, review = SeerrTitle.Review.PendingApproval)
            }
        }

        private fun interleave(first: List<SeerrTitle>, second: List<SeerrTitle>): List<SeerrTitle> =
            (0 until maxOf(first.size, second.size)).flatMap { index -> listOfNotNull(first.getOrNull(index), second.getOrNull(index)) }

        private fun encode(term: String): String =
            java.net.URLEncoder.encode(term, Charsets.UTF_8).replace("+", "%20")

        internal fun url(baseUrl: String, path: String): HttpUrl {
            val base = baseUrl.trim().toHttpUrlOrNull() ?: throw ZelefinException.invalidServerUrl()
            return "${base.toString().trimEnd('/')}/${path.trimStart('/')}".toHttpUrlOrNull()
                ?: throw ZelefinException.invalidServerUrl()
        }

        private fun execute(url: HttpUrl, method: String, body: String?, token: String?): Triple<Int, Map<String, String>, String> {
            val builder = Request.Builder().url(url).header("Accept", "application/json")
            token?.let { builder.header("Authorization", "Bearer $it") }
            if (method == "GET") {
                builder.get()
            } else {
                builder.method(method, (body ?: "{}").toRequestBody(JSON))
            }
            GatewayHttp.client.newCall(builder.build()).execute().use { response ->
                val headers = response.headers.names().associateWith { response.headers[it].orEmpty() }
                return Triple(response.code, headers, response.body?.string().orEmpty())
            }
        }

        private fun throwIfNeeded(response: Triple<Int, Map<String, String>, String>) {
            val (status, headers, body) = response
            if (AccessGateway.isChallenge(status, headers, body)) throw ZelefinException.accessGateway()
            if (status == 401 || status == 403) throw ZelefinException.seerrUnauthorized("Ombi")
            if (status !in 200..299) throw ZelefinException.server(errorMessage(body, status))
        }

        fun errorMessage(body: String, status: Int): String {
            val json = LenientJson.objectOrNull(body)
            if (json != null) {
                for (key in listOf("errorMessage", "message", "error", "title")) {
                    val value = (json[key] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
                    if (!value.isNullOrBlank()) return value
                }
            }
            return "Ombi returned $status."
        }

        private fun unexpected() = ZelefinException.server("Ombi returned an unexpected response.")
    }
}
