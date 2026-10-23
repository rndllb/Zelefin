package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdaptiveBitrateTest {
    private fun path(transport: NetworkTransport, metered: Boolean = false) =
        NetworkPathSnapshot(transport, isExpensive = metered, isConstrained = false, isSatisfied = true)

    @Test
    fun homeWifiClaimsSeventyPercent() {
        assertEquals(7_000_000, AdaptiveBitratePolicy.budgetBitsPerSecond(10_000_000, path(NetworkTransport.Wifi)))
    }

    @Test
    fun cellularAndMeteredLinksClaimHalf() {
        assertEquals(5_000_000, AdaptiveBitratePolicy.budgetBitsPerSecond(10_000_000, path(NetworkTransport.Cellular)))
        assertEquals(5_000_000, AdaptiveBitratePolicy.budgetBitsPerSecond(10_000_000, path(NetworkTransport.Wifi, metered = true)))
    }

    @Test
    fun quickProbeFailureCarriesNoSpeed() {
        assertNull(AdaptiveBitratePolicy.timedOutProbe(750_000, 4_000, 300, NetworkTransport.Wifi))
    }
}
