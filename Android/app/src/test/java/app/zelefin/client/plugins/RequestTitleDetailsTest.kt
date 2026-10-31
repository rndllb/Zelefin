package app.zelefin.client.plugins

import app.zelefin.core.LenientJson
import java.time.LocalDate
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RequestTitleDetailsTest {
    private fun json(text: String) = LenientJson.parse(text) as JsonObject

    @Test
    fun ombiShowsUseTheBannerAsBackdropAndTheNetworkAsStudio() {
        val details = RequestTitleDetails.ombiShow(
            json(
                """
                {"banner": "/back.jpg", "images": {"original": "/poster.jpg"}, "firstAired": "2024-11-17",
                 "runtime": "0", "rating": "7.205", "network": {"name": "HBO"}, "trailer": "CzVHWNosS2o",
                 "cast": [{"id": 1639, "person": "Emily Watson", "character": "Valya", "image": "/ew.jpg"}],
                 "seasonRequests": [{"seasonNumber": 0}, {"seasonNumber": 1}, {"seasonNumber": 2}]}
                """,
            ),
        )
        assertEquals("https://image.tmdb.org/t/p/w1280/back.jpg", details.backdropUrl)
        assertEquals("https://image.tmdb.org/t/p/w500/poster.jpg", details.posterUrl)
        assertEquals(LocalDate.of(2024, 11, 17), details.releaseDate)
        assertEquals(2, details.seasonCount)
        assertEquals("Network" to "HBO", details.facts.first { it.label == "Network" }.let { it.label to it.value })
        assertNull(details.facts.firstOrNull { it.label == "Run Time" })
        assertEquals("Emily Watson", details.cast.single().name)
        assertEquals("https://www.youtube.com/watch?v=CzVHWNosS2o", details.trailers.single().watchUrl)
    }

    @Test
    fun ombiMoviesReadSnakeCaseCreditsAndRecommendations() {
        val details = RequestTitleDetails.ombiMovie(
            json(
                """
                {"releaseDate": "2021-09-15T00:00:00Z", "runtime": 155,
                 "credits": {"cast": [{"id": 1, "name": "Timothée Chalamet", "character": "Paul", "profile_path": "/tc.jpg"}],
                             "crew": [{"name": "Denis Villeneuve", "job": "Director"}, {"name": "Someone", "job": "Set Dresser"}]},
                 "videos": {"results": [{"key": "a", "name": "Behind", "site": "YouTube", "type": "Featurette"},
                                        {"key": "b", "name": "Final Trailer", "site": "YouTube", "type": "Trailer"},
                                        {"key": "c", "name": "Elsewhere", "site": "Vimeo", "type": "Trailer"}]},
                 "recommendations": {"results": [{"id": 693134, "title": "Dune: Part Two", "release_date": "2024-02-27", "poster_path": "/p2.jpg"}]}}
                """,
            ),
        )
        assertEquals(LocalDate.of(2021, 9, 15), details.releaseDate)
        assertEquals("2 hr 35 min", details.facts.first { it.label == "Run Time" }.value)
        assertEquals(listOf("Denis Villeneuve"), details.directors)
        assertEquals(listOf("b", "a"), details.trailers.map { it.key })
        assertEquals(2024, details.related.single().year)
        assertEquals("https://image.tmdb.org/t/p/w185/tc.jpg", details.cast.single().imageUrl)
    }

    @Test
    fun seerrShowsNameTheirCreators() {
        val details = RequestTitleDetails.seerrShow(
            json("""{"firstAirDate": "2011-04-17", "episodeRunTime": [60], "numberOfSeasons": 8, "createdBy": [{"name": "David Benioff"}], "networks": [{"name": "HBO"}]}"""),
        )
        assertEquals(60, details.runtimeMinutes)
        assertEquals("David Benioff", details.facts.first { it.label == "Created By" }.value)
        assertEquals("HBO", details.facts.first { it.label == "Network" }.value)
    }
}

class JellyfinTmdbCatalogItemTest {
    @Test
    fun discoverTitlesFindTheirLibraryItem() {
        val catalog = JellyfinTmdbCatalog.of(mapOf(438631 to "dune-movie"), mapOf(1399 to "got-series"))
        val dune = SeerrTitle(438631, SeerrTitle.Kind.Movie, "Dune", 2021, null, null, SeerrTitle.Availability.Available)
        val got = SeerrTitle(1399, SeerrTitle.Kind.Tv, "Game of Thrones", 2011, null, null, SeerrTitle.Availability.Available)
        assertEquals("dune-movie", catalog.itemId(dune))
        assertEquals("got-series", catalog.itemId(got))
        assertNull(catalog.itemId(got.copy(kind = SeerrTitle.Kind.Movie)))
        assertEquals(true, catalog.contains(got))
    }
}
