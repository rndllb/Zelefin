package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class SignInRoutingTest {
    @Test
    fun jellyfinSignsInUnlessTheAddressIsSilosMainOne() {
        var askedCompat = false
        val compat = { askedCompat = true; true }
        assertEquals(SignInRoute.Jellyfin, SignInRouting.route(SignInServerType.Jellyfin, isSiloMainAddress = false, compat))
        assertEquals(
            SignInRoute.Refused("This is Silo's main address. Choose Silo, or enter Silo's Jellyfin-compatible address."),
            SignInRouting.route(SignInServerType.Jellyfin, isSiloMainAddress = true, compat),
        )
        assertFalse(askedCompat)
    }

    @Test
    fun siloUsesTheNativeFlowOnItsMainAddress() {
        var askedCompat = false
        assertEquals(SignInRoute.SiloNative, SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = true) { askedCompat = true; false })
        assertFalse(askedCompat)
    }

    @Test
    fun siloFallsBackToItsJellyfinCompatibleAddress() {
        assertEquals(SignInRoute.Jellyfin, SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = false) { true })
    }

    @Test
    fun siloRefusesOtherServers() {
        assertEquals(
            SignInRoute.Refused("This isn't a Silo server. Choose Jellyfin, or check the address."),
            SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = false) { false },
        )
    }
}
