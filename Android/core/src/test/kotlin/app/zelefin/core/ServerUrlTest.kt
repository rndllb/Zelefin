package app.zelefin.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerUrlTest {
    @Test
    fun normalizeDefaultsToHttpsAndKeepsSubpath() {
        assertEquals(
            "https://jellyfin.example.com/jellyfin",
            ServerUrl.normalize("jellyfin.example.com/jellyfin/"),
        )
    }

    @Test
    fun normalizeRepairsCapitalizedOrMistypedScheme() {
        assertEquals("https://jellyfin.example.de", ServerUrl.normalize("Https://jellyfin.example.de"))
        assertEquals("https://jellyfin.example.de", ServerUrl.normalize("HTTPS://jellyfin.example.de/"))
        assertEquals("http://192.168.1.12:8096", ServerUrl.normalize("Http://192.168.1.12:8096"))
        assertEquals("https://jellyfin.example.de", ServerUrl.normalize("https:/jellyfin.example.de"))
        assertEquals("https://jellyfin.example.de", ServerUrl.normalize("https//jellyfin.example.de"))
        assertEquals("http://192.168.1.12:8096", ServerUrl.normalizeLanAddress("Http://192.168.1.12:8096"))
        assertEquals("https://httpbin.example.com", ServerUrl.normalize("httpbin.example.com"))
        assertEquals("https://http.example.com", ServerUrl.normalize("http.example.com"))
    }

    @Test
    fun normalizeKeepsHttpForLan() {
        assertEquals("http://192.168.1.12:8096", ServerUrl.normalize("http://192.168.1.12:8096/"))
    }

    @Test
    fun joinKeepsReverseProxySubpath() {
        val url = ServerUrl.resolve("https://media.example.com/jellyfin", "/Items/abc/Images/Primary")
        assertEquals("https://media.example.com/jellyfin/Items/abc/Images/Primary", url)
    }

    @Test
    fun rewritesLocalhostTranscodeOntoPublicOrigin() {
        val url = ServerUrl.resolve(
            "https://jellyfin.example.com/jellyfin",
            "http://127.0.0.1:8096/Videos/abc/stream.m3u8?PlaySessionId=1",
            token = "secret",
        )
        assertEquals(
            "https://jellyfin.example.com/jellyfin/Videos/abc/stream.m3u8?PlaySessionId=1&api_key=secret",
            url,
        )
    }

    @Test
    fun rewritesPrivateLanHost() {
        val url = ServerUrl.rewriteIfNeeded(
            "http://192.168.4.20:8096/Videos/x",
            "https://cf.example.com",
        )
        assertEquals("https://cf.example.com/Videos/x", url)
    }

    @Test
    fun doesNotRewriteMatchingPublicHost() {
        val original = "https://jellyfin.example.com/Videos/x"
        assertEquals(original, ServerUrl.rewriteIfNeeded(original, "https://jellyfin.example.com"))
    }

    @Test
    fun dockerHostnameIsInternal() {
        assertTrue(ServerUrl.isInternalHost("jellyfin"))
        assertTrue(ServerUrl.isInternalHost("localhost"))
        assertTrue(ServerUrl.isInternalHost("10.8.0.2"))
        assertFalse(ServerUrl.isInternalHost("jellyfin.example.com"))
    }

    @Test
    fun lanIpCountsAsLocalOnlyOnItsSubnet() {
        val home = listOf(ServerUrl.LocalSubnet("192.168.1.42", 24))
        assertTrue(ServerUrl.isOnLocalNetwork("192.168.1.153", home))
        // Cellular with a Tailscale subnet route: no Wi-Fi subnet, so the LAN IP is remote.
        assertFalse(ServerUrl.isOnLocalNetwork("192.168.1.153", emptyList()))
        assertFalse(ServerUrl.isOnLocalNetwork("192.168.2.10", home))
        assertFalse(ServerUrl.isOnLocalNetwork("100.101.102.103", home))
        assertTrue(ServerUrl.isOnLocalNetwork("127.0.0.1", emptyList()))
        assertTrue(ServerUrl.isOnLocalNetwork("jellyfin.local", emptyList()))
        assertFalse(ServerUrl.isOnLocalNetwork("jellyfin.example.com", home))
    }

    @Test
    fun appendsApiKeyWithoutDroppingQuery() {
        val url = ServerUrl.resolve("https://example.com", "/Videos/1/stream.ts?static=true", token = "tok")
        assertEquals("https://example.com/Videos/1/stream.ts?static=true&api_key=tok", url)
    }

    @Test
    fun joinsEnhancedTmdbPathWithoutInjectingApiKey() {
        val url = ServerUrl.resolve(
            "https://example.com",
            "/JellyfinEnhanced/tmdb/movie/27205/reviews?language=en-US&page=1",
        )
        assertEquals(
            "https://example.com/JellyfinEnhanced/tmdb/movie/27205/reviews?language=en-US&page=1",
            url,
        )
    }

    @Test
    fun appendingQueryKeepsReverseProxyPath() {
        val path = ServerUrl.resolve("https://media.example.com/jellyfin", "/Items")!!
        val url = ServerUrl.appending(
            listOf("recursive" to "true", "includeItemTypes" to "Series", "parentId" to "abc"),
            path,
        )
        assertEquals(
            "https://media.example.com/jellyfin/Items?recursive=true&includeItemTypes=Series&parentId=abc",
            url,
        )
    }

    @Test
    fun appendingQueryKeepsExistingItems() {
        val result = ServerUrl.appending(listOf("recursive" to "true"), "https://example.com/Items?userId=1")
        assertEquals("https://example.com/Items?userId=1&recursive=true", result)
    }

    @Test
    fun appendingEmptyQueryLeavesUrlUnchanged() {
        val url = "https://example.com/Items"
        assertEquals(url, ServerUrl.appending(emptyList(), url))
    }

    @Test
    fun sessionSocketUsesWebSocketSchemeAndAuthQuery() {
        val socket = ServerUrl.sessionSocket("https://media.example.com/jellyfin/", "tok", "dev-1")
        assertTrue(socket!!.startsWith("wss://"))
        assertTrue(socket.contains("/jellyfin/socket"))
        assertTrue(socket.contains("api_key=tok"))
        assertTrue(socket.contains("deviceId=dev-1"))
        assertTrue(
            ServerUrl.sessionSocket("http://192.168.1.12:8096", "tok", "dev-1")!!.startsWith("ws://"),
        )
    }

    @Test
    fun lanAddressDefaultsToHttp() {
        assertEquals("http://192.168.1.100:8096", ServerUrl.normalizeLanAddress("192.168.1.100:8096"))
        assertEquals("https://jellyfin.example.com", ServerUrl.normalizeLanAddress("jellyfin.example.com"))
    }
}

class ServerReachabilityTest {
    @Test
    fun reachableMessageAndFlag() {
        val result = ServerReachability.Reachable("Home", "10.10")
        assertTrue(result.isReachable)
        assertEquals("Reached Home (10.10)", result.message)
    }

    @Test
    fun authenticationRequiredIsStillReachable() {
        val result = ServerReachability.ReachableRequiringAuthentication
        assertTrue(result.isReachable)
        assertEquals(
            "Reached the server, but it requires auth at the public-info endpoint.",
            result.message,
        )
    }

    @Test
    fun accessGatewayErrorIsNotReachable() {
        val result = ServerReachability.from(ZelefinException.accessGateway())
        assertTrue(result is ServerReachability.BlockedByAccessGateway)
        assertFalse(result.isReachable)
        assertEquals(ZelefinException.accessGateway().message, result.message)
    }

    @Test
    fun explainsTimedOut() {
        val result = ServerReachability.fromNetwork(NetworkFailure.TimedOut)
        assertEquals("The request timed out.", (result as ServerReachability.Failed).description)
        assertFalse(result.isReachable)
    }

    @Test
    fun explainsUnknownHost() {
        assertEquals(
            "Couldn’t find that host. Check the URL.",
            ServerReachability.explanation(NetworkFailure.CannotFindHost),
        )
    }
}

class AccessGatewayTest {
    @Test
    fun headersCoverCloudflareAndPangolin() {
        val headers = AccessGateway.headers("abc.access", "super-secret")
        assertEquals("abc.access", headers["CF-Access-Client-Id"])
        assertEquals("super-secret", headers["CF-Access-Client-Secret"])
        assertEquals("abc.access", headers["P-Access-Token-Id"])
        assertEquals("super-secret", headers["P-Access-Token"])
    }

    @Test
    fun emptyCredentialsSendNoHeaders() {
        assertTrue(AccessGateway.headers("  ", "").isEmpty())
    }

    @Test
    fun detectsCloudflareAccessRedirect() {
        assertTrue(
            AccessGateway.isChallenge(
                status = 302,
                headers = mapOf(
                    "Location" to "https://jellyfin.example.com.cloudflareaccess.com/cdn-cgi/access/login",
                    "Content-Type" to "text/html",
                ),
                body = "<html></html>",
            ),
        )
    }

    @Test
    fun jsonSuccessIsNotAChallenge() {
        assertFalse(
            AccessGateway.isChallenge(
                status = 200,
                headers = mapOf("Content-Type" to "application/json"),
                body = "{\"ServerName\":\"JF\"}",
            ),
        )
    }
}
