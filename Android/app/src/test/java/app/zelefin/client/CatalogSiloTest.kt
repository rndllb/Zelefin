package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogSiloTest {
    @Test
    fun siloQueryKeepsOnlyFiltersSiloApplies() {
        val query = CatalogBrowseQuery(
            statuses = setOf(CatalogStatusFilter.Favorite),
            features = setOf(CatalogFeatureFilter.Subtitles),
            videoKinds = setOf(CatalogVideoKind.FourK),
            genres = setOf("Drama"),
            tags = setOf("kids"),
            studios = setOf("A24"),
            years = setOf(2024),
            sort = CatalogSortField.Runtime,
        ).forSiloServer()
        assertEquals(setOf(CatalogStatusFilter.Favorite), query.statuses)
        assertEquals(setOf("Drama"), query.genres)
        assertEquals(setOf(2024), query.years)
        assertTrue(query.features.isEmpty() && query.videoKinds.isEmpty() && query.tags.isEmpty() && query.studios.isEmpty())
        assertEquals(CatalogSortField.Name, query.sort)
    }

    @Test
    fun siloKeepsSupportedSorts() {
        assertEquals(CatalogSortField.ReleaseDate, CatalogBrowseQuery(sort = CatalogSortField.ReleaseDate).forSiloServer().sort)
    }

    @Test
    fun siloOptionsHideUnappliedSections() {
        val options = CatalogFilterOptions(
            tags = listOf(CatalogFilterChoice("a", "a")),
            studios = listOf(CatalogFilterChoice("b", "b")),
            genres = listOf(CatalogFilterChoice("c", "c")),
        ).forSiloServer()
        assertTrue(options.tags.isEmpty() && options.studios.isEmpty())
        assertEquals(1, options.genres.size)
        assertFalse(options.fileFilters)
        assertEquals(CatalogFilterOptions.SiloSorts, options.sorts)
    }
}
