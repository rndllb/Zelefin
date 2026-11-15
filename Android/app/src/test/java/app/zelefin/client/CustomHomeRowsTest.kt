package app.zelefin.client

import app.zelefin.client.ui.HomeRowKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CustomHomeRowsTest {
    @Test
    fun homeRowSlotParsesCustomAndBuiltIn() {
        assertEquals(HomeRowSlot.Custom("abc"), HomeRowSlot.parse("custom:abc"))
        assertEquals(HomeRowSlot.BuiltIn(HomeRowKind.Featured), HomeRowSlot.parse("featured"))
        assertEquals(null, HomeRowSlot.parse("custom:"))
        assertEquals(null, HomeRowSlot.parse("nope"))
    }

    @Test
    fun homeRowSlotOrderedKeepsCustomTokensAndAppendsMissing() {
        val ids = setOf("a", "b")
        val ordered = HomeRowSlot.ordered("custom:b,featured,custom:missing", ids)
        assertEquals(HomeRowSlot.Custom("b"), ordered.first())
        assertEquals(HomeRowSlot.BuiltIn(HomeRowKind.Featured), ordered[1])
        assertTrue(ordered.any { it is HomeRowSlot.Custom && it.id == "a" })
        assertTrue(ordered.none { it is HomeRowSlot.Custom && it.id == "missing" })
        assertEquals(HomeRowKind.entries.size + 2, ordered.size)
    }

    @Test
    fun customHomeRowsEncodeDecodeRoundTrip() {
        val row = CustomHomeRow(
            id = "row-1",
            title = "4K Action",
            scope = CustomHomeRowScope.Movies.raw,
            query = CatalogBrowseQueryDto(
                videoKinds = listOf(CatalogVideoKind.FourK.name),
                genres = listOf("Action"),
                sort = CatalogSortField.DateAdded.name,
                sortAscending = false,
            ),
            enabled = true,
        )
        val raw = CustomHomeRows.encode(listOf(row))
        val decoded = CustomHomeRows.decode(raw)
        assertEquals(1, decoded.size)
        assertEquals(row, decoded.first())
        assertEquals(setOf(CatalogVideoKind.FourK), decoded.first().browseQuery.videoKinds)
        assertEquals(setOf("Action"), decoded.first().browseQuery.genres)
    }

    @Test
    fun filterSummaryIncludesScopeAndCounts() {
        val row = CustomHomeRow(
            title = "Unwatched",
            scope = CustomHomeRowScope.Both.raw,
            query = CatalogBrowseQueryDto(statuses = listOf(CatalogStatusFilter.Unplayed.name)),
        )
        val summary = CustomHomeRows.filterSummary(row)
        assertTrue(summary.contains("Movies & Shows"))
        assertTrue(summary.contains("1 filters"))
    }
}
