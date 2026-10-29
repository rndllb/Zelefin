package app.zelefin.client.plugins

import app.zelefin.core.ZelefinException
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** A request backend the Discover UI can drive. */
/** The request server Search, Discover, and the request sheet talk to. */
enum class RequestService(val raw: String, val title: String) {
    Seerr("seerr", "Seerr"),
    Ombi("ombi", "Ombi"),
    ;

    companion object {
        fun from(raw: String?): RequestService = entries.firstOrNull { it.raw == raw } ?: Seerr
    }
}

/**
 * Mirrors iOS `RequestServiceClient`: what Search, Discover, and the request sheet need from Seerr
 * or Ombi. Ombi's titles and requests are mapped onto the Seerr types, which the screens already draw.
 */
interface RequestCatalog {
    val service: RequestService

    /** Seerr lets a request pick its Radarr or Sonarr server, quality, and folder. Ombi uses its defaults. */
    val choosesDownloadServer: Boolean

    suspend fun search(term: String): List<SeerrTitle>

    /** The title as it stands now: whether it's on the server, and its open request, if any. */
    suspend fun requestStatus(title: SeerrTitle): SeerrTitle

    suspend fun discoverHome(): List<DiscoverSection>

    suspend fun discover(query: DiscoverQuery, page: Int): DiscoverPage

    suspend fun request(title: SeerrTitle)

    suspend fun currentUser(): SeerrUser

    suspend fun radarrServers(): List<SeerrServiceServer>

    suspend fun sonarrServers(): List<SeerrServiceServer>

    suspend fun radarrDetails(id: Int): SeerrServiceDetails

    suspend fun sonarrDetails(id: Int): SeerrServiceDetails

    suspend fun tvDetails(id: Int): SeerrTvDetails

    suspend fun requestDetails(id: Int): SeerrStoredRequest

    suspend fun request(draft: SeerrRequestDraft)

    suspend fun approveRequest(id: Int, draft: SeerrRequestDraft)

    suspend fun declineRequest(id: Int, kind: SeerrTitle.Kind)
}

sealed class DiscoverQuery {
    data object Requests : DiscoverQuery()
    data object Trending : DiscoverQuery()
    data object PopularMovies : DiscoverQuery()
    data object UpcomingMovies : DiscoverQuery()
    data object PopularTv : DiscoverQuery()
    data object UpcomingTv : DiscoverQuery()
    data class MovieGenre(val id: Int, val name: String) : DiscoverQuery()
    data class TvGenre(val id: Int, val name: String) : DiscoverQuery()
    data class Studio(val id: Int, val name: String) : DiscoverQuery()
    data class Network(val id: Int, val name: String) : DiscoverQuery()

    val title: String
        get() = when (this) {
            Requests -> "Recent Requests"
            Trending -> "Trending"
            PopularMovies -> "Popular Movies"
            UpcomingMovies -> "Upcoming Movies"
            PopularTv -> "Popular TV"
            UpcomingTv -> "Upcoming TV"
            is MovieGenre -> name
            is TvGenre -> name
            is Studio -> name
            is Network -> name
        }

    /** Stable key for navigation and list identity. */
    val key: String
        get() = when (this) {
            Requests -> "requests"
            Trending -> "trending"
            PopularMovies -> "popular-movies"
            UpcomingMovies -> "upcoming-movies"
            PopularTv -> "popular-tv"
            UpcomingTv -> "upcoming-tv"
            is MovieGenre -> "movie-genre-$id"
            is TvGenre -> "tv-genre-$id"
            is Studio -> "studio-$id"
            is Network -> "network-$id"
        }

    val path: String
        get() = when (this) {
            Requests -> "api/v1/request"
            Trending -> "api/v1/discover/trending"
            PopularMovies -> "api/v1/discover/movies"
            UpcomingMovies -> "api/v1/discover/movies/upcoming"
            PopularTv -> "api/v1/discover/tv"
            UpcomingTv -> "api/v1/discover/tv/upcoming"
            is MovieGenre -> "api/v1/discover/movies/genre/$id"
            is TvGenre -> "api/v1/discover/tv/genre/$id"
            is Studio -> "api/v1/discover/movies/studio/$id"
            is Network -> "api/v1/discover/tv/network/$id"
        }

    fun queryItems(page: Int): List<Pair<String, String>> = when (this) {
        Requests -> listOf(
            "filter" to "all",
            "take" to "20",
            "skip" to "${(page - 1) * 20}",
            "sort" to "modified",
        )
        else -> listOf("page" to "$page", "language" to "en")
    }
}

typealias SeerrDiscoverQuery = DiscoverQuery

data class DiscoverPage(
    val titles: List<SeerrTitle>,
    val page: Int,
    val totalPages: Int,
) {
    val hasMore: Boolean get() = page < totalPages
}

typealias SeerrDiscoverPage = DiscoverPage

enum class DiscoverBrandKind { Genre, Studio, Network }

/** A genre, studio, or network tile that opens [query]. */
data class DiscoverBrand(
    val id: String,
    val name: String,
    val imageUrl: String?,
    val kind: DiscoverBrandKind,
    val query: DiscoverQuery,
)

/** One Discover row: either poster [titles] or [brands] tiles. [query] backs "See All" when present. */
data class DiscoverSection(
    val id: String,
    val title: String,
    val query: DiscoverQuery?,
    val titles: List<SeerrTitle> = emptyList(),
    val brands: List<DiscoverBrand> = emptyList(),
) {
    val isBrandRow: Boolean get() = brands.isNotEmpty()
    val isEmpty: Boolean get() = titles.isEmpty() && brands.isEmpty()
}

data class SeerrGenreSliderItem(
    val id: Int,
    val name: String,
    val backdrops: List<String>? = null,
    val mediaType: String? = null,
) {
    val imageUrl: String? get() = SeerrClient.tmdbImageUrl(backdrops?.firstOrNull(), size = "w780")

    val discoverQuery: DiscoverQuery
        get() = if (mediaType == "tv") DiscoverQuery.TvGenre(id, name) else DiscoverQuery.MovieGenre(id, name)

    fun brand(): DiscoverBrand = DiscoverBrand(
        id = "genre-${mediaType ?: "movie"}-$id",
        name = name,
        imageUrl = imageUrl,
        kind = DiscoverBrandKind.Genre,
        query = discoverQuery,
    )

    companion object {
        fun parse(json: JsonObject): SeerrGenreSliderItem? {
            val id = json.int("id") ?: return null
            val name = json.str("name") ?: return null
            val backdrops = (json["backdrops"] as? JsonArray)?.mapNotNull {
                (it as? JsonPrimitive)?.contentOrNull
            }
            return SeerrGenreSliderItem(id, name, backdrops)
        }
    }
}

data class SeerrCompany(
    val id: Int,
    val name: String,
    val kind: Kind,
    val imageUrl: String?,
) {
    enum class Kind { Studio, Network }

    val query: DiscoverQuery
        get() = when (kind) {
            Kind.Studio -> DiscoverQuery.Studio(id, name)
            Kind.Network -> DiscoverQuery.Network(id, name)
        }

    fun brand(): DiscoverBrand = DiscoverBrand(
        id = "${kind.name.lowercase()}-$id",
        name = name,
        imageUrl = imageUrl,
        kind = if (kind == Kind.Studio) DiscoverBrandKind.Studio else DiscoverBrandKind.Network,
        query = query,
    )

    companion object {
        private fun tmdbLogo(path: String): String =
            "https://image.tmdb.org/t/p/w780_filter(duotone,ffffff,2e2e2e)/$path"

        val studios: List<SeerrCompany> = listOf(
            SeerrCompany(2, "Disney", Kind.Studio, tmdbLogo("wdrCwmRnLFJhEoH8GSfymY85KHT.png")),
            SeerrCompany(127928, "20th Century Studios", Kind.Studio, tmdbLogo("h0rjX5vjW5r8yEnUBStFarjcLT4.png")),
            SeerrCompany(34, "Sony Pictures", Kind.Studio, tmdbLogo("GagSvqWlyPdkFHMfQ3pNq6ix9P.png")),
            SeerrCompany(174, "Warner Bros. Pictures", Kind.Studio, tmdbLogo("ky0xOc5OrhzkZ1N6KyUxacfQsCk.png")),
            SeerrCompany(33, "Universal", Kind.Studio, tmdbLogo("8lvHyhjr8oUKOOy2dKXoALWKdp0.png")),
            SeerrCompany(4, "Paramount", Kind.Studio, tmdbLogo("fycMZt242LVjagMByZOLUGbCvv3.png")),
            SeerrCompany(3, "Pixar", Kind.Studio, tmdbLogo("1TjvGVDMYsj6JBxOAkUHpPEwLf7.png")),
            SeerrCompany(521, "DreamWorks", Kind.Studio, tmdbLogo("kP7t6RwGz2AvvTkvnI1uteEwHet.png")),
            SeerrCompany(420, "Marvel Studios", Kind.Studio, tmdbLogo("hUzeosd33nzE5MCNsZxCGEKTXaQ.png")),
            SeerrCompany(9993, "DC", Kind.Studio, tmdbLogo("2Tc1P3Ac8M479naPp1kYT3izLS5.png")),
            SeerrCompany(41077, "A24", Kind.Studio, tmdbLogo("1ZXsGaFPgrgS6ZZGS37AqD5uU12.png")),
        )

        val networks: List<SeerrCompany> = listOf(
            SeerrCompany(213, "Netflix", Kind.Network, tmdbLogo("wwemzKWzjKYJFfCeiB57q3r4Bcm.png")),
            SeerrCompany(2739, "Disney+", Kind.Network, tmdbLogo("gJ8VX6JSu3ciXHuC2dDGAo2lvwM.png")),
            SeerrCompany(1024, "Prime Video", Kind.Network, tmdbLogo("ifhbNuuVnlwYy5oXA5VIb2YR8AZ.png")),
            SeerrCompany(2552, "Apple TV+", Kind.Network, tmdbLogo("4KAy34EHvRM25Ih8wb82AuGU7zJ.png")),
            SeerrCompany(453, "Hulu", Kind.Network, tmdbLogo("pqUTCleNUiTLAVlelGxUgWn1ELh.png")),
            SeerrCompany(49, "HBO", Kind.Network, tmdbLogo("tuomPhY2UtuPTqqFnKMVHvSb724.png")),
            SeerrCompany(4353, "Discovery+", Kind.Network, tmdbLogo("1D1bS3Dyw4ScYnFWTlBOvJXC3nb.png")),
            SeerrCompany(2, "ABC", Kind.Network, tmdbLogo("ndAvF4JLsliGreX87jAc9GdjmJY.png")),
            SeerrCompany(19, "FOX", Kind.Network, tmdbLogo("1DSpHrWyOORkL9N2QHX7Adt31mQ.png")),
            SeerrCompany(359, "Cinemax", Kind.Network, tmdbLogo("6mSHSquNpfLgDdv6VnOOvC5Uz2h.png")),
            SeerrCompany(174, "AMC", Kind.Network, tmdbLogo("pmvRmATOCaDykE6JrVoeYxlFHw3.png")),
            SeerrCompany(67, "Showtime", Kind.Network, tmdbLogo("Allse9kbjiP6ExaQrnSpIhkurEi.png")),
            SeerrCompany(318, "Starz", Kind.Network, tmdbLogo("8GJjw3HHsAJYwIWKIPBPfqMxlEa.png")),
            SeerrCompany(71, "The CW", Kind.Network, tmdbLogo("ge9hzeaU7nMtQ4PjkFlHlxkurEi.png")),
            SeerrCompany(6, "NBC", Kind.Network, tmdbLogo("o3OedEP0f9mfZr33jz2BfXOUK5.png")),
            SeerrCompany(16, "CBS", Kind.Network, tmdbLogo("nm8d7P7MJNiBLdgIzUK0gkuEA4r.png")),
            SeerrCompany(4330, "Paramount+", Kind.Network, tmdbLogo("fi83B1oztoS47xxcemFdPMhIzK.png")),
            SeerrCompany(4, "BBC One", Kind.Network, tmdbLogo("mVn7xESaTNmjBUyUtGNvDQd3CT1.png")),
            SeerrCompany(56, "Cartoon Network", Kind.Network, tmdbLogo("c5OC6oVCg6QP4eqzW6XIq17CQjI.png")),
            SeerrCompany(80, "Adult Swim", Kind.Network, tmdbLogo("9AKyspxVzywuaMuZ1Bvilu8sXly.png")),
            SeerrCompany(13, "Nickelodeon", Kind.Network, tmdbLogo("ikZXxg6GnwpzqiZbRPhJGaZapqB.png")),
            SeerrCompany(3353, "Peacock", Kind.Network, tmdbLogo("gIAcGTjKKr0KOHL5s4O36roJ8p7.png")),
        )
    }
}

data class SeerrDiscoverHome(
    val recentRequests: List<SeerrTitle> = emptyList(),
    val trending: List<SeerrTitle> = emptyList(),
    val popularMovies: List<SeerrTitle> = emptyList(),
    val upcomingMovies: List<SeerrTitle> = emptyList(),
    val popularTv: List<SeerrTitle> = emptyList(),
    val upcomingTv: List<SeerrTitle> = emptyList(),
    val movieGenres: List<SeerrGenreSliderItem> = emptyList(),
    val tvGenres: List<SeerrGenreSliderItem> = emptyList(),
    val studios: List<SeerrCompany> = emptyList(),
    val networks: List<SeerrCompany> = emptyList(),
) {
    val isEmpty: Boolean
        get() = recentRequests.isEmpty() &&
            trending.isEmpty() &&
            popularMovies.isEmpty() &&
            upcomingMovies.isEmpty() &&
            popularTv.isEmpty() &&
            upcomingTv.isEmpty() &&
            movieGenres.isEmpty() &&
            tvGenres.isEmpty()

    fun markRequested(title: SeerrTitle): SeerrDiscoverHome {
        fun patch(items: List<SeerrTitle>) = items.map {
            if (it.id == title.id) it.copy(availability = SeerrTitle.Availability.Pending) else it
        }
        return copy(
            recentRequests = patch(recentRequests),
            trending = patch(trending),
            popularMovies = patch(popularMovies),
            upcomingMovies = patch(upcomingMovies),
            popularTv = patch(popularTv),
            upcomingTv = patch(upcomingTv),
        )
    }

    /** Rows in the iOS Discover order; empty rows are dropped. */
    fun sections(): List<DiscoverSection> {
        if (isEmpty) return emptyList()
        return listOf(
            titleRow(DiscoverQuery.Requests, recentRequests),
            titleRow(DiscoverQuery.Trending, trending),
            titleRow(DiscoverQuery.PopularMovies, popularMovies),
            DiscoverSection("movie-genres", "Movie Genres", null, brands = movieGenres.map { it.brand() }),
            titleRow(DiscoverQuery.UpcomingMovies, upcomingMovies),
            DiscoverSection("studios", "Studios", null, brands = studios.map { it.brand() }),
            titleRow(DiscoverQuery.PopularTv, popularTv),
            DiscoverSection("tv-genres", "TV Genres", null, brands = tvGenres.map { it.brand() }),
            titleRow(DiscoverQuery.UpcomingTv, upcomingTv),
            DiscoverSection("networks", "Networks", null, brands = networks.map { it.brand() }),
        ).filterNot { it.isEmpty }
    }

    private fun titleRow(query: DiscoverQuery, titles: List<SeerrTitle>) =
        DiscoverSection(query.key, query.title, query, titles = titles)
}

data class SeerrPageInfo(val page: Int?, val pages: Int?, val results: Int?)

data class SeerrListedRequest(
    val id: Int,
    val status: Int? = null,
    val media: SeerrMediaInfo,
    val requestedBy: SeerrUser? = null,
) {
    companion object {
        fun parse(json: JsonObject): SeerrListedRequest? {
            val id = json.int("id") ?: return null
            val media = json.obj("media")?.let(SeerrMediaInfo::parse) ?: return null
            return SeerrListedRequest(id, json.int("status"), media, json.obj("requestedBy")?.let(SeerrUser::parse))
        }
    }
}

data class SeerrRequestListResponse(
    val pageInfo: SeerrPageInfo?,
    val results: List<SeerrListedRequest>,
) {
    companion object {
        fun parse(json: JsonObject) = SeerrRequestListResponse(
            pageInfo = json.obj("pageInfo")?.let { SeerrPageInfo(it.int("page"), it.int("pages"), it.int("results")) },
            results = json.objects("results").mapNotNull(SeerrListedRequest::parse),
        )
    }
}

private suspend fun <T> attempt(block: suspend () -> T): T? = try {
    block()
} catch (cancel: CancellationException) {
    throw cancel
} catch (_: Exception) {
    null
}

suspend fun SeerrClient.discoverHome(): SeerrDiscoverHome = coroutineScope {
    val recentRequests = async { attempt { recentRequestTitles(1) }?.titles.orEmpty() }
    val trending = async { attempt { discover(DiscoverQuery.Trending) }?.titles.orEmpty() }
    val popularMovies = async { attempt { discover(DiscoverQuery.PopularMovies) }?.titles.orEmpty() }
    val upcomingMovies = async { attempt { discover(DiscoverQuery.UpcomingMovies) }?.titles.orEmpty() }
    val popularTv = async { attempt { discover(DiscoverQuery.PopularTv) }?.titles.orEmpty() }
    val upcomingTv = async { attempt { discover(DiscoverQuery.UpcomingTv) }?.titles.orEmpty() }
    val movieGenres = async { attempt { genreSlider(SeerrTitle.Kind.Movie) }.orEmpty() }
    val tvGenres = async { attempt { genreSlider(SeerrTitle.Kind.Tv) }.orEmpty() }
    SeerrDiscoverHome(
        recentRequests = recentRequests.await(),
        trending = trending.await(),
        popularMovies = popularMovies.await(),
        upcomingMovies = upcomingMovies.await(),
        popularTv = popularTv.await(),
        upcomingTv = upcomingTv.await(),
        movieGenres = movieGenres.await(),
        tvGenres = tvGenres.await(),
        studios = SeerrCompany.studios,
        networks = SeerrCompany.networks,
    )
}

suspend fun SeerrClient.listedRequests(page: Int = 1): List<SeerrListedRequest> {
    val json = fetch(DiscoverQuery.Requests.path, DiscoverQuery.Requests.queryItems(page)) as? JsonObject
        ?: return emptyList()
    return SeerrRequestListResponse.parse(json).results
}

suspend fun SeerrClient.discover(query: DiscoverQuery, page: Int = 1): DiscoverPage {
    if (query == DiscoverQuery.Requests) return recentRequestTitles(page)
    val json = fetch(query.path, query.queryItems(page)) as? JsonObject
        ?: throw ZelefinException.server("Seerr returned an unexpected response.")
    val payload = SeerrSearchResponse.parse(json)
    val defaultKind = when (query) {
        DiscoverQuery.PopularMovies, DiscoverQuery.UpcomingMovies, is DiscoverQuery.MovieGenre, is DiscoverQuery.Studio ->
            SeerrTitle.Kind.Movie
        DiscoverQuery.PopularTv, DiscoverQuery.UpcomingTv, is DiscoverQuery.TvGenre, is DiscoverQuery.Network ->
            SeerrTitle.Kind.Tv
        else -> null
    }
    return DiscoverPage(
        titles = payload.results.mapNotNull { SeerrClient.title(it, defaultKind) },
        page = payload.page ?: page,
        totalPages = payload.totalPages ?: page,
    )
}

suspend fun SeerrClient.genreSlider(kind: SeerrTitle.Kind): List<SeerrGenreSliderItem> {
    val path = if (kind == SeerrTitle.Kind.Movie) "api/v1/discover/genreslider/movie" else "api/v1/discover/genreslider/tv"
    val items = (fetch(path, listOf("language" to "en")) as? JsonArray).orEmpty()
        .mapNotNull { (it as? JsonObject)?.let(SeerrGenreSliderItem::parse) }
    if (kind != SeerrTitle.Kind.Tv) return items
    return items.map { it.copy(mediaType = "tv") }
}

private suspend fun SeerrClient.recentRequestTitles(page: Int): DiscoverPage {
    val json = fetch(DiscoverQuery.Requests.path, DiscoverQuery.Requests.queryItems(page)) as? JsonObject
        ?: throw ZelefinException.server("Seerr returned an unexpected response.")
    val payload = SeerrRequestListResponse.parse(json)
    val titles = hydrate(payload.results)
    return DiscoverPage(
        titles = titles,
        page = payload.pageInfo?.page ?: page,
        totalPages = maxOf(payload.pageInfo?.pages ?: page, 1),
    )
}

private suspend fun SeerrClient.hydrate(requests: List<SeerrListedRequest>): List<SeerrTitle> = coroutineScope {
    requests.map { request -> async { attempt { title(request) } } }.awaitAll().filterNotNull()
}

private suspend fun SeerrClient.title(request: SeerrListedRequest): SeerrTitle {
    val tmdbId = request.media.tmdbId ?: throw ZelefinException.server("Missing TMDB id.")
    val kind = if (request.media.mediaType == "tv") SeerrTitle.Kind.Tv else SeerrTitle.Kind.Movie
    val base = titleDetails(kind, tmdbId).copy(
        requestId = request.id,
        requestedByName = request.requestedBy?.requestLabel,
    )
    val mediaAvailability = SeerrTitle.Availability.fromStatus(request.media.status)
    if (base.availability == SeerrTitle.Availability.Available || mediaAvailability == SeerrTitle.Availability.Available) {
        return base.copy(availability = SeerrTitle.Availability.Available, review = null)
    }
    val review = SeerrTitle.Review.fromStatus(request.status)
    val availability = when {
        review == SeerrTitle.Review.PendingApproval -> SeerrTitle.Availability.Pending
        base.availability == SeerrTitle.Availability.Missing || base.availability == SeerrTitle.Availability.Unknown ->
            if (mediaAvailability == SeerrTitle.Availability.Missing) SeerrTitle.Availability.Pending else mediaAvailability
        else -> base.availability
    }
    return base.copy(review = review, availability = availability)
}

/** Adapts [SeerrClient] to the shared [RequestCatalog] used by the Discover UI. */
class SeerrRequestCatalog(val client: SeerrClient) : RequestCatalog {
    override val service = RequestService.Seerr
    override val choosesDownloadServer = true

    override suspend fun search(term: String): List<SeerrTitle> = client.search(term)

    override suspend fun requestStatus(title: SeerrTitle): SeerrTitle = client.requestStatus(title)

    override suspend fun discoverHome(): List<DiscoverSection> = client.discoverHome().sections()

    override suspend fun discover(query: DiscoverQuery, page: Int): DiscoverPage = client.discover(query, page)

    override suspend fun request(title: SeerrTitle) = client.request(title)

    override suspend fun currentUser(): SeerrUser = client.currentUser()

    override suspend fun radarrServers(): List<SeerrServiceServer> = client.radarrServers()

    override suspend fun sonarrServers(): List<SeerrServiceServer> = client.sonarrServers()

    override suspend fun radarrDetails(id: Int): SeerrServiceDetails = client.radarrDetails(id)

    override suspend fun sonarrDetails(id: Int): SeerrServiceDetails = client.sonarrDetails(id)

    override suspend fun tvDetails(id: Int): SeerrTvDetails = client.tvDetails(id)

    override suspend fun requestDetails(id: Int): SeerrStoredRequest = client.requestDetails(id)

    override suspend fun request(draft: SeerrRequestDraft) = client.request(draft)

    override suspend fun approveRequest(id: Int, draft: SeerrRequestDraft) = client.approveRequest(id, draft)

    override suspend fun declineRequest(id: Int, kind: SeerrTitle.Kind) = client.declineRequest(id)
}
