package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CatalogQueryStoreTest {
    @Test
    fun roundTrip() {
        val query = CatalogBrowseQuery(
            statuses = setOf(CatalogStatusFilter.Favorite),
            sort = CatalogSortField.ReleaseDate,
            sortAscending = false,
            years = setOf(2024),
        )
        val encoded = CatalogQueryStore.encode(query)
        val decoded = CatalogQueryStore.decode(encoded)
        assertEquals(query.sort, decoded.sort)
        assertEquals(query.sortAscending, decoded.sortAscending)
        assertEquals(query.statuses, decoded.statuses)
        assertEquals(query.years, decoded.years)
    }

    @Test
    fun emptyDecodesDefault() {
        assertTrue(CatalogQueryStore.decode("").isDefault)
    }
}
