package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class SiloAccountsTest {
    private val base = "https://silo.example.com"

    @Test
    fun decodesTokenPair() {
        val text = """
            {"access_token":"acc","refresh_token":"ref","expires_in":3600,
             "user":{"id":"7","username":"alice","email":"","role":"admin","permissions":["marker_edit"],
                     "download_allowed":true,"password_change_required":false}}
        """.trimIndent()
        val signIn = SiloJson.signIn(text, nowMillis = 1_000)!!
        assertEquals(SiloTokens("acc", "ref", 3_601_000), signIn.tokens)
        assertEquals("7", signIn.account.id)
        assertEquals("alice", signIn.account.username)
        assertNull(signIn.account.email)
        assertEquals("admin", signIn.account.role)
        assertEquals(listOf("marker_edit"), signIn.account.permissions)
        assertTrue(signIn.account.downloadAllowed)
        assertFalse(signIn.account.passwordChangeRequired)
    }

    @Test
    fun tokenPairWithoutUserOrTokenIsUnreadable() {
        assertNull(SiloJson.signIn("""{"access_token":"a","refresh_token":"r","expires_in":60}""", 0))
        assertNull(SiloJson.signIn("""{"refresh_token":"r","user":{"id":"1","username":"a"}}""", 0))
        assertNull(SiloJson.signIn("<html></html>", 0))
    }

    @Test
    fun decodesRefreshedTokens() {
        val tokens = SiloJson.refreshed("""{"access_token":"a2","refresh_token":"r2","expires_in":900}""", nowMillis = 0)
        assertEquals(SiloTokens("a2", "r2", 900_000), tokens)
    }

    @Test
    fun tokensExpireThirtySecondsEarly() {
        val tokens = SiloTokens("a", "r", expiresAt = 100_000)
        assertFalse(tokens.isExpired(60_000))
        assertTrue(tokens.isExpired(70_000))
        assertFalse(SiloTokens("a", "r", null).isExpired(Long.MAX_VALUE))
        assertTrue(SiloTokens("", "r", null).isExpired(0))
    }

    @Test
    fun decodesProfileCollectionAndResolvesAvatars() {
        val text = """
            {"items":[
              {"id":"1","name":"Alice","avatar":"preset:fox","avatar_source":"preset","avatar_url":"/avatars/presets/fox.png",
               "has_pin":true,"is_child":false,"is_primary":true},
              {"id":"2","name":"Kids","avatar":"","avatar_source":"none","has_pin":false,"is_child":true,"is_primary":false},
              {"id":"3","name":"Guest","avatar_url":"https://cdn.example.com/a.jpg"},
              {"name":"No id"}
             ],
             "avatar_upload_enabled":true,"max_advisory_age_supported":true,"require_advisory_age_supported":false}
        """.trimIndent()
        val collection = SiloJson.profiles(text, "$base/silo")!!
        assertTrue(collection.avatarUploadEnabled)
        assertEquals(listOf("1", "2", "3"), collection.items.map { it.id })
        val alice = collection.items[0]
        assertEquals("https://silo.example.com/silo/avatars/presets/fox.png", alice.avatarUrl)
        assertEquals("preset", alice.avatarSource)
        assertTrue(alice.hasPin)
        assertTrue(alice.isPrimary)
        assertFalse(alice.isChild)
        val kids = collection.items[1]
        assertNull(kids.avatarUrl)
        assertTrue(kids.isChild)
        assertEquals("https://cdn.example.com/a.jpg", collection.items[2].avatarUrl)
    }

    @Test
    fun emptyProfileCollection() {
        val collection = SiloJson.profiles("""{"items":[],"avatar_upload_enabled":false}""", base)!!
        assertTrue(collection.items.isEmpty())
        assertFalse(collection.avatarUploadEnabled)
    }

    @Test
    fun decodesPinVerification() {
        val unlocked = SiloJson.pinVerification("""{"valid":true,"profile_token":"pvt_1","expires_at":"2026-01-02T15:04:05.000Z"}""")!!
        assertTrue(unlocked.valid)
        assertEquals("pvt_1", unlocked.profileToken)
        assertEquals("2026-01-02T15:04:05.000Z", unlocked.expiresAt)
        val wrong = SiloJson.pinVerification("""{"valid":false,"expires_at":null}""")!!
        assertFalse(wrong.valid)
        assertNull(wrong.profileToken)
        assertNull(wrong.expiresAt)
        assertNull(SiloJson.pinVerification("""{"expires_at":null}"""))
    }

    @Test
    fun decodesConnectInfo() {
        val info = SiloJson.connectInfo(
            """{"jellyfin":{"enabled":true,"pending_restart":false,"public_url":"jf.example.com:8097/","server_name":"Home"},
               "account":{"password_login_available":true}}""",
        )!!
        assertTrue(info.jellyfinEnabled)
        assertFalse(info.pendingRestart)
        assertEquals("Home", info.serverName)
        assertTrue(info.passwordLoginAvailable)
        assertNull(info.blocker)
        assertEquals("https://jf.example.com:8097", info.requireJellyfinUrl())
    }

    @Test
    fun connectInfoGatingMessages() {
        fun info(enabled: Boolean, restart: Boolean, url: String) = SiloJson.connectInfo(
            """{"jellyfin":{"enabled":$enabled,"pending_restart":$restart,"public_url":"$url","server_name":"S"},"account":{"password_login_available":false}}""",
        )!!
        assertEquals(SiloConnectInfo.TurnOnJellyfinMessage, info(false, false, "https://jf.example.com").blocker)
        assertEquals(SiloConnectInfo.TurnOnJellyfinMessage, info(false, true, "").blocker)
        assertEquals(SiloConnectInfo.RestartMessage, info(true, true, "https://jf.example.com").blocker)
        assertEquals(SiloConnectInfo.PublicAddressMessage, info(true, false, "").blocker)
        assertEquals(SiloConnectInfo.PublicAddressMessage, info(true, false, "   ").blocker)
        try {
            info(false, false, "").requireJellyfinUrl()
            fail("Expected the disabled API to stop sign-in")
        } catch (error: ZelefinException) {
            assertEquals("Turn on Silo's Jellyfin-compatible API in its admin settings, then sign in again.", error.message)
        }
    }

    @Test
    fun problemDetailMessages() {
        val problem = """{"type":"https://siloserver.org/docs/api/v2/problems/rate_limited","title":"Too Many Requests","status":429,
            "detail":"Too many incorrect PINs. Try again in 5 minutes.","instance":"urn:silo:request:1"}"""
        assertEquals("Too many incorrect PINs. Try again in 5 minutes.", SiloProblem.message(problem, 429))
        val validation = """{"type":"t","title":"Validation failed","status":422,"detail":"","instance":"i",
            "errors":[{"location":"body.pin","code":"pattern","detail":"PIN must be 4 to 8 digits"}]}"""
        assertEquals("PIN must be 4 to 8 digits", SiloProblem.message(validation, 422))
        assertEquals("Unauthorized", SiloProblem.message("""{"title":"Unauthorized","status":401}""", 401))
        assertEquals("Silo did not accept that username or password.", SiloProblem.message("", 401, "Silo did not accept that username or password."))
        assertEquals("Silo had a problem (502). Try again.", SiloProblem.message("<html>Bad gateway</html>", 502))
        assertNull(SiloProblem.detail(null))
    }

    @Test
    fun recognisesSiloNativeAddress() {
        assertTrue(SiloJson.isSetupStatus("""{"needs_setup":false,"wizard_completed":true}"""))
        assertFalse(SiloJson.isSetupStatus("""<!doctype html><html></html>"""))
        assertFalse(SiloJson.isSetupStatus("""{"ServerName":"Jellyfin"}"""))
        assertTrue(SiloJson.isHealth("""{"status":"ok"}"""))
        assertFalse(SiloJson.isHealth("""[]"""))
    }

    @Test
    fun readsHandoffStatus() {
        assertEquals("approved", SiloJson.handoffStatus("""{"status":"Approved"}"""))
        assertEquals("denied", SiloJson.handoffStatus("""{"status":"denied"}"""))
        assertNull(SiloJson.handoffStatus("nope"))
    }
}

class SiloAddressCheckTest {
    @Test
    fun warnsWhenAnOutsideAddressHandsOutAHomeJellyfinAddress() {
        val warning = SiloAddressCheck.remoteWarning("https://silo.example.com", "http://192.168.1.144:8096")
        assertNotNull(warning)
        assertTrue(warning!!.contains("192.168.1.144"))
    }

    @Test
    fun quietWhenBothAddressesAreOutsideOrBothAtHome() {
        assertNull(SiloAddressCheck.remoteWarning("https://silo.example.com", "https://jf.example.com"))
        assertNull(SiloAddressCheck.remoteWarning("http://192.168.1.144:8080", "http://192.168.1.144:8096"))
        assertNull(SiloAddressCheck.remoteWarning("http://silo.local:8080", "http://10.0.0.5:8096"))
    }

    @Test
    fun recognisesHomeNetworkHosts() {
        listOf("10.1.2.3", "172.20.0.1", "192.168.0.9", "127.0.0.1", "169.254.1.1", "localhost", "nas.local", "media", "fd12::1", "[::1]")
            .forEach { assertTrue(it, SiloAddressCheck.isHomeNetworkHost(it)) }
        listOf("172.32.0.1", "8.8.8.8", "silo.example.com", "100.100.1.1")
            .forEach { assertFalse(it, SiloAddressCheck.isHomeNetworkHost(it)) }
    }
}
