package app.zelefin.client.plugins

import app.zelefin.core.ZelefinException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SeerrSessionPersistenceTest {
    @Test
    fun relaunchDoesNotClearSeerr() {
        assertFalse(PluginSettings.shouldClearSession(null, "ada"))
        assertFalse(PluginSettings.shouldClearSession("ada", "ada", "ada"))
    }

    @Test
    fun updateKeepsSeerrForTheSameUser() {
        assertFalse(PluginSettings.shouldClearSession(null, "ada", "ada"))
    }

    @Test
    fun switchingJellyfinUserClearsSeerr() {
        assertTrue(PluginSettings.shouldClearSession("ada", "bob", "ada"))
    }

    @Test
    fun signingInAsADifferentUserAfterSignOutClearsSeerr() {
        assertTrue(PluginSettings.shouldClearSession(null, "bob", "ada"))
    }

    @Test
    fun unauthorizedIsDistinctFromAServerError() {
        assertTrue(ZelefinException.seerrUnauthorized().isSeerrUnauthorized)
        assertFalse(ZelefinException.server("Seerr is unreachable.").isSeerrUnauthorized)
    }

    @Test
    fun credentialsRoundTrip() {
        val raw = SeerrCredentials("ada", "secret").toJson()
        val parsed = SeerrCredentials.fromJson(raw)
        assertEquals("ada", parsed?.username)
        assertEquals("secret", parsed?.password)
    }
}
