package app.zelefin.client.ui

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DockChromeStateTest {
    private fun DockChromeState.scrolled(consumedY: Float, availableY: Float = 0f) {
        scroll.onPostScroll(Offset(0f, consumedY), Offset(0f, availableY), NestedScrollSource.UserInput)
    }

    @Test
    fun scrollingDownThePageCollapsesTheDock() {
        val chrome = DockChromeState()
        chrome.scrolled(-20f)
        assertFalse("a small nudge keeps the dock open", chrome.minimized)
        chrome.scrolled(-20f)
        assertTrue(chrome.minimized)
    }

    @Test
    fun scrollingBackUpExpandsTheDock() {
        val chrome = DockChromeState()
        chrome.scrolled(-80f)
        chrome.scrolled(40f)
        assertFalse(chrome.minimized)
    }

    @Test
    fun pullingPastTheTopExpandsTheDock() {
        val chrome = DockChromeState()
        chrome.scrolled(-80f)
        chrome.scrolled(consumedY = 0f, availableY = 12f)
        assertFalse(chrome.minimized)
    }

    @Test
    fun sidewaysRowsDoNotMoveTheDock() {
        val chrome = DockChromeState()
        chrome.scroll.onPostScroll(Offset(-300f, 0f), Offset.Zero, NestedScrollSource.UserInput)
        assertFalse(chrome.minimized)
    }
}
