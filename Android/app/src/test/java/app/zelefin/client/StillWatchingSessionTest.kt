package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class StillWatchingSessionTest {
    @Before
    fun reset() {
        StillWatchingSession.reset()
    }

    @Test
    fun promptsAfterThreeAutoAdvancesAndContinueStartsOver() {
        StillWatchingSession.onOpened("a")
        assertFalse(StillWatchingSession.shouldPrompt(enabled = true, episode = true))
        listOf("b", "c", "d").forEach { id ->
            assertFalse(StillWatchingSession.shouldPrompt(enabled = true, episode = true))
            StillWatchingSession.armAuto(id)
            StillWatchingSession.onOpened(id)
        }
        assertEquals(3, StillWatchingSession.count)
        assertTrue(StillWatchingSession.shouldPrompt(enabled = true, episode = true))
        StillWatchingSession.continueWatching()
        StillWatchingSession.armAuto("e")
        StillWatchingSession.onOpened("e")
        assertEquals(1, StillWatchingSession.count)
        assertFalse(StillWatchingSession.shouldPrompt(enabled = true, episode = true))
    }

    @Test
    fun manualNextKeepsTheStreak() {
        StillWatchingSession.onOpened("a")
        StillWatchingSession.armAuto("b")
        StillWatchingSession.onOpened("b")
        StillWatchingSession.armManual("c")
        StillWatchingSession.onOpened("c")
        assertEquals(1, StillWatchingSession.count)
    }

    @Test
    fun aDifferentTitleClearsTheStreak() {
        StillWatchingSession.armAuto("b")
        StillWatchingSession.onOpened("b")
        StillWatchingSession.onOpened("z")
        assertEquals(0, StillWatchingSession.count)
    }

    @Test
    fun moviesAndTheOffSwitchNeverPrompt() {
        repeat(3) {
            StillWatchingSession.armAuto("e$it")
            StillWatchingSession.onOpened("e$it")
        }
        assertFalse(StillWatchingSession.shouldPrompt(enabled = false, episode = true))
        assertFalse(StillWatchingSession.shouldPrompt(enabled = true, episode = false))
        assertTrue(StillWatchingSession.shouldPrompt(enabled = true, episode = true))
    }
}
