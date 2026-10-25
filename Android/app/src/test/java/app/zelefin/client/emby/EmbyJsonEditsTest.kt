package app.zelefin.client.emby

import app.zelefin.client.jellyfin.ItemMetadataDraft
import app.zelefin.core.EmbyJson
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.jellyfin.sdk.model.api.UnratedItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbyJsonEditsTest {
    private fun obj(text: String): JsonObject = EmbyJson.parser.parseToJsonElement(text).jsonObject

    private val policy = obj(
        """{"IsAdministrator":true,"IsHidden":true,"IsDisabled":false,"MaxParentalRating":null,"BlockedTags":["gore"],
            "BlockUnratedItems":["Movie","Game"],"EnableSubtitleManagement":true,"EnableSubtitleDownloading":true,
            "EnableAllFolders":false,"EnabledFolders":["c0863accd66a4d89b2c4a78aea20c386"],"RemoteClientBitrateLimit":8000000,
            "AuthenticationProviderId":"Emby.Server.Implementations.Library.DefaultAuthenticationProvider","SimultaneousStreamLimit":0}""",
    )

    @Test
    fun policyReadsIntoTheSharedDraft() {
        val draft = EmbyJsonEdits.policyDraft(policy)
        assertTrue(draft.isAdministrator)
        assertFalse(draft.isDisabled)
        assertTrue(draft.enableSubtitleManagement)
        assertEquals(8_000_000, draft.remoteClientBitrateLimit)
        assertEquals(null, draft.maxParentalRating)
        assertEquals(setOf(UnratedItem.MOVIE), draft.blockUnratedItems)
        assertFalse(draft.enableAllFolders)
        assertEquals(setOf("c0863accd66a4d89b2c4a78aea20c386"), draft.enabledFolders)
    }

    @Test
    fun policySaveKeepsEveryFieldTheEditorDoesNotShow() {
        val draft = EmbyJsonEdits.policyDraft(policy).copy(
            isDisabled = true,
            maxParentalRating = 10,
            blockUnratedItems = setOf(UnratedItem.SERIES, UnratedItem.LIVE_TV_CHANNEL),
            enabledFolders = setOf("b", "a"),
        )
        val saved = EmbyJsonEdits.policy(policy, draft)
        assertEquals(JsonPrimitive(true), saved["IsDisabled"])
        assertEquals(JsonPrimitive(10), saved["MaxParentalRating"])
        assertEquals(JsonArray(listOf(JsonPrimitive("LiveTvChannel"), JsonPrimitive("Series"))), saved["BlockUnratedItems"])
        assertEquals(JsonArray(listOf(JsonPrimitive("a"), JsonPrimitive("b"))), saved["EnabledFolders"])
        assertEquals(policy["BlockedTags"], saved["BlockedTags"])
        assertEquals(policy["AuthenticationProviderId"], saved["AuthenticationProviderId"])
        assertEquals(policy["IsHidden"], saved["IsHidden"])
        val all = EmbyJsonEdits.policy(policy, draft.copy(enableAllFolders = true, maxParentalRating = null))
        assertEquals(JsonArray(emptyList()), all["EnabledFolders"])
        assertEquals(JsonNull, all["MaxParentalRating"])
    }

    @Test
    fun displayPreferencesMergeIntoWhateverIsStored() {
        assertEquals(emptyMap<String, String>(), EmbyJsonEdits.customPrefs(obj("""{"Id":"zelefin","CustomPrefs":[]}""")))
        val stored = obj("""{"Id":"zelefin","SortBy":"SortName","CustomPrefs":{"tabOrder":"home","homeRowHidden":"none"},"Client":"Zelefin"}""")
        assertEquals(mapOf("tabOrder" to "home", "homeRowHidden" to "none"), EmbyJsonEdits.customPrefs(stored))
        val merged = EmbyJsonEdits.displayPreferences(stored, mapOf("tabOrder" to "home,movies"))
        assertEquals(obj("""{"tabOrder":"home,movies","homeRowHidden":"none"}"""), merged["CustomPrefs"])
        assertEquals(JsonPrimitive("SortName"), merged["SortBy"])
        assertEquals(stored, EmbyJsonEdits.displayPreferences(stored, EmbyJsonEdits.customPrefs(stored)))
    }

    @Test
    fun metadataEditSetsTheEditorFieldsOnly() {
        val current = obj(
            """{"Id":"1093","Name":"Halloween Kills","Overview":"old","ProductionYear":2021,"OfficialRating":"R",
                "Genres":["Horror"],"GenreItems":[{"Name":"Horror","Id":2070}],"TagItems":[{"Name":"slasher","Id":2097}],
                "ProviderIds":{"Tmdb":"610253"},"LockedFields":[]}""",
        )
        val draft = ItemMetadataDraft(name = " ", overview = "", year = "2022", officialRating = "", genres = "Horror, Thriller", tags = "slasher")
        val edited = EmbyJsonEdits.metadata(current, draft)
        assertEquals(JsonPrimitive("Halloween Kills"), edited["Name"])
        assertEquals(JsonNull, edited["Overview"])
        assertEquals(JsonPrimitive(2022), edited["ProductionYear"])
        assertEquals(JsonNull, edited["OfficialRating"])
        assertEquals(JsonArray(listOf(JsonPrimitive("Horror"), JsonPrimitive("Thriller"))), edited["Genres"])
        assertEquals(EmbyJson.parser.parseToJsonElement("""[{"Name":"Horror"},{"Name":"Thriller"}]"""), edited["GenreItems"])
        assertEquals(EmbyJson.parser.parseToJsonElement("""[{"Name":"slasher"}]"""), edited["TagItems"])
        assertEquals(current["ProviderIds"], edited["ProviderIds"])
        assertEquals(current["LockedFields"], edited["LockedFields"])
    }

    @Test
    fun identifyResultsKeepTheRawMatch() {
        val results = EmbyJson.parser.parseToJsonElement(
            """[{"Name":"Halloween Kills","ProductionYear":2021,"ProviderIds":{"Tmdb":"610253","Imdb":""},"ImageUrl":"https://img/p.jpg","SearchProviderName":"TheMovieDb"},
                {"ProductionYear":1978},"junk"]""",
        )
        val hits = EmbyJsonEdits.identifyHits(results)
        assertEquals(2, hits.size)
        assertEquals("Halloween Kills", hits[0].name)
        assertEquals(2021, hits[0].year)
        assertEquals(mapOf("Tmdb" to "610253"), hits[0].providerIds)
        assertEquals("https://img/p.jpg", hits[0].imageUrl)
        assertEquals(results.let { (it as JsonArray)[0] }, hits[0].raw)
        assertEquals("Untitled", hits[1].name)
    }
}
