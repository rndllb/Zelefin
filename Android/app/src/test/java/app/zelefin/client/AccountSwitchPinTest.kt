package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AccountSwitchPinTest {
    @Test
    fun pinIsFourToSixDigits() {
        assertTrue(AccountSwitchPin.isValid("1234"))
        assertTrue(AccountSwitchPin.isValid("123456"))
        assertFalse(AccountSwitchPin.isValid("123"))
        assertFalse(AccountSwitchPin.isValid("1234567"))
        assertFalse(AccountSwitchPin.isValid("12ab"))
        assertFalse(AccountSwitchPin.isValid("1234 "))
    }

    @Test
    fun digestIsStableAndBoundToTheAccount() {
        val first = AccountSwitchPin.digest("1234", "media.example|user-a")
        val again = AccountSwitchPin.digest("1234", "media.example|user-a")
        val otherAccount = AccountSwitchPin.digest("1234", "media.example|user-b")
        val otherPin = AccountSwitchPin.digest("4321", "media.example|user-a")
        assertEquals(first, again)
        assertNotEquals(first, otherAccount)
        assertNotEquals(first, otherPin)
        assertEquals(64, first.length)
    }
}
