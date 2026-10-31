package app.zelefin.client.plugins

import app.zelefin.core.TitleMoreRow
import app.zelefin.core.dbl
import app.zelefin.core.int
import app.zelefin.core.obj
import app.zelefin.core.objects
import app.zelefin.core.str
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

/** Mirrors iOS `RequestTitleDetails`: a Discover title's page, from Seerr or Ombi. */
data class RequestTitleDetails(
    val backdropUrl: String? = null,
    val posterUrl: String? = null,
    val tagline: String? = null,
    val overview: String? = null,
    val genres: List<String> = emptyList(),
    val releaseDate: LocalDate? = null,
    val runtimeMinutes: Int? = null,
    val seasonCount: Int? = null,
    /** The studio for a movie, the network for a show. */
    val studio: String? = null,
    val studioLabel: String = "Studio",
    val status: String? = null,
    /** TMDB's score out of 10. */
    val voteAverage: Double? = null,
    val directors: List<String> = emptyList(),
    val creators: List<String> = emptyList(),
    val cast: List<RequestCastMember> = emptyList(),
    val videos: List<RequestVideo> = emptyList(),
    val related: List<SeerrTitle> = emptyList(),
    val homepage: String? = null,
    val imdbId: String? = null,
) {
    /** The rows under Information, in the order the Jellyfin detail page shows them. */
    val facts: List<TitleMoreRow>
        get() = buildList {
            releaseDate?.let { add(TitleMoreRow("Released", it.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.LONG).withLocale(Locale.getDefault())))) }
            runtimeMinutes?.takeIf { it > 0 }?.let { minutes ->
                val hours = minutes / 60
                add(TitleMoreRow("Run Time", if (hours > 0) "$hours hr ${minutes % 60} min" else "$minutes min"))
            }
            seasonCount?.takeIf { it > 0 }?.let { add(TitleMoreRow("Seasons", "$it")) }
            if (genres.isNotEmpty()) add(TitleMoreRow("Genre", genres.joinToString(", ")))
            if (directors.isNotEmpty()) add(TitleMoreRow(if (directors.size > 1) "Directors" else "Director", directors.joinToString(", ")))
            if (creators.isNotEmpty()) add(TitleMoreRow("Created By", creators.joinToString(", ")))
            studio?.takeIf { it.isNotBlank() }?.let { add(TitleMoreRow(studioLabel, it)) }
            status?.takeIf { it.isNotBlank() }?.let { add(TitleMoreRow("Status", it)) }
            voteAverage?.takeIf { it > 0 }?.let { add(TitleMoreRow("TMDB Rating", String.format(Locale.getDefault(), "%.1f / 10", it))) }
        }

    /** Trailers first, then teasers, then everything else YouTube has. */
    val trailers: List<RequestVideo> get() = videos.sortedBy { it.rank }

    companion object {
        fun date(raw: String?): LocalDate? {
            if (raw == null || raw.length < 10) return null
            return runCatching { LocalDate.parse(raw.take(10)) }.getOrNull()?.takeIf { it.year > 1900 }
        }

        private fun names(json: JsonObject, key: String): List<String> = json.objects(key).mapNotNull { it.str("name") }

        private fun cast(members: List<JsonObject>, name: String, image: String): List<RequestCastMember> =
            members.take(30).mapNotNull { person ->
                val id = person.int("id") ?: return@mapNotNull null
                val label = person.str(name) ?: return@mapNotNull null
                RequestCastMember(id, label, person.str("character"), SeerrClient.tmdbImageUrl(person.str(image), "w185"))
            }

        private fun directors(crew: List<JsonObject>): List<String> =
            crew.filter { it.str("job") == "Director" }.mapNotNull { it.str("name") }

        private fun videos(list: List<JsonObject>): List<RequestVideo> =
            list.mapNotNull { RequestVideo.from(it.str("key"), it.str("name"), it.str("type"), it.str("site")) }

        fun seerrMovie(json: JsonObject) = RequestTitleDetails(
            backdropUrl = SeerrClient.tmdbImageUrl(json.str("backdropPath"), "w1280"),
            posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath"), "w500"),
            tagline = json.str("tagline"),
            overview = json.str("overview"),
            genres = names(json, "genres"),
            releaseDate = date(json.str("releaseDate")),
            runtimeMinutes = json.int("runtime"),
            studio = names(json, "productionCompanies").firstOrNull(),
            status = json.str("status"),
            voteAverage = json.dbl("voteAverage"),
            directors = directors(json.obj("credits")?.objects("crew").orEmpty()),
            cast = cast(json.obj("credits")?.objects("cast").orEmpty(), "name", "profilePath"),
            videos = videos(json.objects("relatedVideos")),
            homepage = json.str("homepage"),
            imdbId = json.obj("externalIds")?.str("imdbId") ?: json.str("imdbId"),
        )

        fun seerrShow(json: JsonObject) = RequestTitleDetails(
            backdropUrl = SeerrClient.tmdbImageUrl(json.str("backdropPath"), "w1280"),
            posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath"), "w500"),
            tagline = json.str("tagline"),
            overview = json.str("overview"),
            genres = names(json, "genres"),
            releaseDate = date(json.str("firstAirDate")),
            runtimeMinutes = ((json["episodeRunTime"] as? JsonArray)?.firstOrNull() as? JsonPrimitive)?.contentOrNull?.toIntOrNull(),
            seasonCount = json.int("numberOfSeasons"),
            studio = names(json, "networks").firstOrNull(),
            studioLabel = "Network",
            status = json.str("status"),
            voteAverage = json.dbl("voteAverage"),
            creators = names(json, "createdBy"),
            cast = cast(json.obj("credits")?.objects("cast").orEmpty(), "name", "profilePath"),
            videos = videos(json.objects("relatedVideos")),
            homepage = json.str("homepage"),
            imdbId = json.obj("externalIds")?.str("imdbId"),
        )

        /** Ombi's movie page carries TMDB's credits, videos, and recommendations in snake case. */
        fun ombiMovie(json: JsonObject) = RequestTitleDetails(
            backdropUrl = SeerrClient.tmdbImageUrl(json.str("backdropPath"), "w1280"),
            posterUrl = SeerrClient.tmdbImageUrl(json.str("posterPath"), "w500"),
            tagline = json.str("tagline"),
            overview = json.str("overview"),
            genres = names(json, "genres"),
            releaseDate = date(json.str("releaseDate")),
            runtimeMinutes = json.int("runtime"),
            studio = names(json, "productionCompanies").firstOrNull(),
            status = json.str("status"),
            voteAverage = json.dbl("voteAverage"),
            directors = directors(json.obj("credits")?.objects("crew").orEmpty()),
            cast = cast(json.obj("credits")?.objects("cast").orEmpty(), "name", "profile_path"),
            videos = videos(json.obj("videos")?.objects("results").orEmpty()),
            related = json.obj("recommendations")?.objects("results").orEmpty().mapNotNull { movie ->
                val id = movie.int("id") ?: return@mapNotNull null
                val name = movie.str("title") ?: return@mapNotNull null
                SeerrTitle(
                    tmdbId = id,
                    kind = SeerrTitle.Kind.Movie,
                    name = name,
                    year = movie.str("release_date")?.take(4)?.toIntOrNull(),
                    overview = movie.str("overview"),
                    posterUrl = SeerrClient.tmdbImageUrl(movie.str("poster_path")),
                    availability = SeerrTitle.Availability.Missing,
                )
            },
            homepage = json.str("homepage"),
            imdbId = json.obj("externalIds")?.str("imdbId") ?: json.str("imdbId"),
        )

        /** Ombi calls a show's backdrop `banner` and keeps its poster in `images.original`. */
        fun ombiShow(json: JsonObject) = RequestTitleDetails(
            backdropUrl = SeerrClient.tmdbImageUrl(json.str("banner"), "w1280"),
            posterUrl = SeerrClient.tmdbImageUrl(json.obj("images")?.str("original"), "w500"),
            tagline = json.str("tagline"),
            overview = json.str("overview"),
            genres = names(json, "genres"),
            releaseDate = date(json.str("firstAired")),
            runtimeMinutes = json.int("runtime"),
            seasonCount = json.objects("seasonRequests").count { (it.int("seasonNumber") ?: 0) > 0 }.takeIf { json["seasonRequests"] != null },
            studio = json.obj("network")?.str("name"),
            studioLabel = "Network",
            status = json.str("status"),
            voteAverage = json.dbl("rating"),
            cast = cast(json.objects("cast"), "person", "image"),
            videos = listOfNotNull(RequestVideo.from(json.str("trailer"), "Trailer", "Trailer", null)),
            homepage = json.str("homepage"),
            imdbId = json.obj("externalIds")?.str("imdbId") ?: json.str("imdbId"),
        )
    }
}

data class RequestCastMember(val id: Int, val name: String, val role: String?, val imageUrl: String?)

/** A YouTube video on TMDB: a trailer, teaser, or featurette. */
data class RequestVideo(val key: String, val name: String, val type: String?) {
    val watchUrl: String get() = "https://www.youtube.com/watch?v=$key"
    val thumbnailUrl: String get() = "https://img.youtube.com/vi/$key/hqdefault.jpg"

    val rank: Int
        get() = when (type) {
            "Trailer" -> 0
            "Teaser" -> 1
            else -> 2
        }

    companion object {
        fun from(key: String?, name: String?, type: String?, site: String?): RequestVideo? {
            if (key.isNullOrEmpty() || (site != null && site != "YouTube")) return null
            return RequestVideo(key, name?.ifEmpty { null } ?: "Trailer", type)
        }
    }
}
