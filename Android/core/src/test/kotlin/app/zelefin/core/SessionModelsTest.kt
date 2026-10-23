package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionModelsTest {
    @Test
    fun siloUsersShowOnlyTheProfileName() {
        assertEquals("Kids", SavedSession.displayName("ada#Kids", isSiloServer = true))
        assertEquals("ada", SavedSession.displayName("ada", isSiloServer = true))
        assertEquals("ada#", SavedSession.displayName("ada#", isSiloServer = true))
        assertEquals("ada#Kids", SavedSession.displayName("ada#Kids", isSiloServer = false))
        val loaded = SavedAccountsCodec.decode(
            """{"currentId":"silo.example|u","accounts":[{"serverUrl":"https://silo.example:8097","accessToken":"t","userId":"u","userName":"ada#Kids","deviceId":"d","isSiloServer":true}]}""",
        )
        assertEquals("Kids", loaded.box?.current?.userName)
    }

    private val jellyfin = """
        {"serverUrl":"https://jf.example.com","accessToken":"t1","userId":"u1","userName":"ana","deviceId":"d"}
    """.trimIndent()

    private val legacySilo = """
        {"serverUrl":"https://silo.example.com","accessToken":"t2","userId":"7","userName":"bo","deviceId":"d",
         "backend":"Silo","refreshToken":"r","profileId":"p","profileToken":"pt","profileName":"Kids",
         "userRole":"admin","isPrimaryProfile":true}
    """.trimIndent()

    @Test
    fun dropsLegacySiloSessionsAndKeepsJellyfin() {
        val loaded = SavedAccountsCodec.decode("""{"accounts":[$jellyfin,$legacySilo],"currentId":"jf.example.com|u1"}""")
        assertEquals(1, loaded.droppedSilo)
        assertFalse(loaded.droppedCurrent)
        assertEquals(listOf("u1"), loaded.box?.accounts?.map { it.userId })
        assertEquals("u1", loaded.box?.current?.userId)
    }

    @Test
    fun reportsWhenTheCurrentAccountWasSilo() {
        val loaded = SavedAccountsCodec.decode("""{"accounts":[$jellyfin,$legacySilo],"currentId":"silo.example.com|7"}""")
        assertTrue(loaded.droppedCurrent)
        assertEquals("u1", loaded.box?.current?.userId)
    }

    @Test
    fun explicitJellyfinBackendStillDecodes() {
        val tagged = jellyfin.replace("\"deviceId\":\"d\"", "\"deviceId\":\"d\",\"backend\":\"Jellyfin\"")
        val loaded = SavedAccountsCodec.decode("""{"accounts":[$tagged],"currentId":""}""")
        assertEquals(0, loaded.droppedSilo)
        assertEquals(1, loaded.box?.accounts?.size)
        assertFalse(loaded.box?.accounts?.single()?.isSiloServer ?: true)
    }

    @Test
    fun brokenDataNeverThrows() {
        assertNull(SavedAccountsCodec.decode("not json").box)
        val loaded = SavedAccountsCodec.decode("""{"accounts":[{"serverUrl":1},$jellyfin]}""")
        assertEquals(listOf("u1"), loaded.box?.accounts?.map { it.userId })
    }

    @Test
    fun isSiloServerRoundTrips() {
        val session = SavedSession("https://s.example.com", "t", "u", "n", "d", isSiloServer = true)
        val encoded = SavedAccountsCodec.encode(SavedAccountBox(listOf(session), session.accountId))
        assertTrue(SavedAccountsCodec.decode(encoded).box?.current?.isSiloServer == true)
    }

    private val link = SiloLink(
        nativeUrl = "https://silo.example.com",
        refreshToken = "r1",
        accessToken = "a1",
        accessExpiresAt = 42,
        accountId = "7",
        accountName = "alice",
        role = "admin",
        profileId = "2",
        profileName = "Kids",
        isPrimaryProfile = false,
        profileHasPin = true,
        profileToken = "pvt",
        profileAvatarUrl = "https://silo.example.com/avatars/presets/fox.png",
    )

    @Test
    fun sessionWithoutSiloLinkRoundTrips() {
        val loaded = SavedAccountsCodec.decode("""{"accounts":[$jellyfin],"currentId":"jf.example.com|u1"}""")
        assertNull(loaded.box?.current?.siloLink)
        val encoded = SavedAccountsCodec.encode(loaded.box!!)
        assertFalse(encoded.contains("siloLink"))
        assertEquals(loaded.box, SavedAccountsCodec.decode(encoded).box)
    }

    @Test
    fun sessionWithSiloLinkRoundTrips() {
        val session = SavedSession("https://jf.example.com", "t", "u", "Kids", "d", isSiloServer = true, siloLink = link)
        val decoded = SavedAccountsCodec.decode(SavedAccountsCodec.encode(SavedAccountBox(listOf(session), session.accountId)))
        assertEquals(0, decoded.droppedSilo)
        assertEquals(session, decoded.box?.current)
        assertEquals(link, decoded.box?.current?.siloLink)
    }

    @Test
    fun linkedSessionsSurviveTheLegacySiloMigration() {
        val linked = SavedSession("https://jf.example.com", "t", "u9", "Kids", "d", isSiloServer = true, siloLink = link)
        val linkedJson = SavedAccountsCodec.encode(SavedAccountBox(listOf(linked), linked.accountId))
            .substringAfter("[").substringBeforeLast("]")
        val loaded = SavedAccountsCodec.decode("""{"accounts":[$linkedJson,$legacySilo],"currentId":"jf.example.com|u9"}""")
        assertEquals(1, loaded.droppedSilo)
        assertFalse(loaded.droppedCurrent)
        assertEquals(link, loaded.box?.current?.siloLink)
    }

    @Test
    fun linkTokensAndProfileUpdate() {
        val refreshed = link.withTokens(SiloTokens("a2", "r2", 99))
        assertEquals(SiloTokens("a2", "r2", 99), refreshed.tokens)
        val moved = link.withProfile(SiloProfile("2", "Kiddo", avatarUrl = null, hasPin = false, isPrimary = true))
        assertEquals("Kiddo", moved.profileName)
        assertNull(moved.profileAvatarUrl)
        assertTrue(moved.isPrimaryProfile)
        assertFalse(moved.profileHasPin)
        assertEquals(SiloAccount(id = "7", username = "alice", role = "admin"), link.account)
    }

    @Test
    fun replacingSwapsTheAccountInPlace() {
        val first = SavedSession("https://a.example.com", "t", "u1", "A", "d")
        val kids = SavedSession("https://jf.example.com", "t", "kids", "Kids", "d", siloLink = link)
        val other = SavedSession("https://b.example.com", "t", "u3", "B", "d")
        val parent = kids.copy(userId = "parent", userName = "Alice")
        val box = SavedAccountBox(listOf(first, kids, other), kids.accountId).replacing(kids.accountId, parent)
        assertEquals(listOf("u1", "parent", "u3"), box.accounts.map { it.userId })
        assertEquals(parent.accountId, box.currentId)
        val again = box.replacing(parent.accountId, kids).replacing(kids.accountId, parent.copy(accessToken = "new"))
        assertEquals(3, again.accounts.size)
        assertEquals("new", again.current?.accessToken)
    }

    @Test
    fun replacingDropsAnOlderCopyOfTheIncomingProfile() {
        val kids = SavedSession("https://jf.example.com", "t", "kids", "Kids", "d")
        val parent = SavedSession("https://jf.example.com", "t", "parent", "Alice", "d")
        val box = SavedAccountBox(listOf(kids, parent), kids.accountId).replacing(kids.accountId, parent.copy(accessToken = "fresh"))
        assertEquals(listOf("parent"), box.accounts.map { it.userId })
        assertEquals("fresh", box.current?.accessToken)
    }

    @Test
    fun detectsSiloFromItsLoginDisclaimer() {
        assertTrue(SiloCompat.isSiloDisclaimer("Silo provides Jellyfin-compatible app support."))
        assertTrue(SiloCompat.isSiloDisclaimer("powered by SILO"))
        assertFalse(SiloCompat.isSiloDisclaimer("Welcome to our Jellyfin server"))
        assertFalse(SiloCompat.isSiloDisclaimer(null))
    }
}
