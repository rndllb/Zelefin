package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class SignInRoutingTest {
    @Test
    fun jellyfinSignsInUnlessTheAddressIsSilosMainOne() {
        var askedCompat = false
        val compat = { askedCompat = true; true }
        assertEquals(SignInRoute.Jellyfin, SignInRouting.route(SignInServerType.Jellyfin, isSiloMainAddress = false, isSiloCompatAddress = compat))
        assertEquals(
            SignInRoute.Refused("This is Silo's main address. Choose Silo, or enter Silo's Jellyfin-compatible address."),
            SignInRouting.route(SignInServerType.Jellyfin, isSiloMainAddress = true, isSiloCompatAddress = compat),
        )
        assertFalse(askedCompat)
    }

    @Test
    fun siloUsesTheNativeFlowOnItsMainAddress() {
        var askedCompat = false
        assertEquals(
            SignInRoute.SiloNative,
            SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = true, isSiloCompatAddress = { askedCompat = true; false }),
        )
        assertFalse(askedCompat)
    }

    @Test
    fun siloFallsBackToItsJellyfinCompatibleAddress() {
        assertEquals(SignInRoute.Jellyfin, SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = false, isSiloCompatAddress = { true }))
    }

    @Test
    fun siloRefusesOtherServers() {
        assertEquals(
            SignInRoute.Refused("This isn't a Silo server. Choose Jellyfin, or check the address."),
            SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = false, isSiloCompatAddress = { false }),
        )
    }

    @Test
    fun jellyfinRefusesAnEmbyAddress() {
        assertEquals(
            SignInRoute.Refused("This is an Emby server. Choose Emby."),
            SignInRouting.route(SignInServerType.Jellyfin, isSiloMainAddress = false, isSiloCompatAddress = { false }, isEmbyAddress = { true }),
        )
    }

    @Test
    fun embySignsInOnAnEmbyAddress() {
        var askedCompat = false
        assertEquals(
            SignInRoute.Emby,
            SignInRouting.route(
                SignInServerType.Emby,
                isSiloMainAddress = false,
                isSiloCompatAddress = { askedCompat = true; false },
                isEmbyAddress = { true },
            ),
        )
        assertFalse(askedCompat)
    }

    @Test
    fun embyRefusesOtherServers() {
        val notEmby = SignInRoute.Refused("This isn't an Emby server. Choose Jellyfin, or check the address.")
        assertEquals(notEmby, SignInRouting.route(SignInServerType.Emby, isSiloMainAddress = false, isSiloCompatAddress = { false }, isEmbyAddress = { false }))
        assertEquals(notEmby, SignInRouting.route(SignInServerType.Emby, isSiloMainAddress = true, isSiloCompatAddress = { false }, isEmbyAddress = { true }))
    }

    @Test
    fun siloNeverAsksTheEmbyProbe() {
        var askedEmby = false
        SignInRouting.route(SignInServerType.Silo, isSiloMainAddress = false, isSiloCompatAddress = { true }, isEmbyAddress = { askedEmby = true; true })
        assertFalse(askedEmby)
    }
}
