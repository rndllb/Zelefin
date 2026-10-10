package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SubtitleAppearanceTest {
    @Test
    fun syncSnapsToQuarterSeconds() {
        assertEquals(0.25, SubtitleAppearance.snappedSync(0.13), 0.001)
        assertEquals(10.0, SubtitleAppearance.snappedSync(12.0), 0.001)
        assertEquals(-10.0, SubtitleAppearance.snappedSync(-12.0), 0.001)
        assertEquals("In Sync", SubtitleAppearance.syncTitle(0.0))
        assertEquals("+1.25 s", SubtitleAppearance.syncTitle(1.25))
        assertEquals("-0.5 s", SubtitleAppearance.syncTitle(-0.5))
    }

    @Test
    fun sizeScaleGrows() {
        val medium = SubtitleAppearance.Snapshot()
        val large = SubtitleAppearance.Snapshot(size = SubtitleAppearance.SIZE_LARGE)
        assertTrue(large.sizeScale > medium.sizeScale)
        assertTrue(large.mpvFontSize > medium.mpvFontSize)
        assertTrue(large.fractionalTextSize > medium.fractionalTextSize)
    }

    @Test
    fun highlightUsesAWindowAndRaisedMovesUp() {
        val highlight = SubtitleAppearance.Snapshot(background = SubtitleAppearance.BACK_HIGHLIGHT)
        val raised = SubtitleAppearance.Snapshot(positionLift = 50)
        assertEquals("Highlight", highlight.backgroundTitle())
        assertEquals("Raised", raised.positionTitle())
        assertTrue(raised.bottomPadding > SubtitleAppearance.Snapshot().bottomPadding)
        assertTrue(raised.mpvMarginY > SubtitleAppearance.Snapshot().mpvMarginY)
    }

    @Test
    fun portraitLetterboxKeepsCaptionsOnThePicture() {
        val style = SubtitleAppearance.Snapshot()
        val portrait = SubtitlePictureLayout.placement(
            viewWidth = 1080,
            viewHeight = 2400,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = false,
            style = style,
        )
        val landscape = SubtitlePictureLayout.placement(
            viewWidth = 2400,
            viewHeight = 1080,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = false,
            style = style,
        )
        val filled = SubtitlePictureLayout.placement(
            viewWidth = 1080,
            viewHeight = 2400,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = true,
            style = style,
        )
        assertTrue(portrait.letterboxBottom > 700f)
        assertTrue(portrait.bottomPaddingFraction > 0.30f)
        assertTrue(portrait.mpvSubPos < 70)
        assertTrue(portrait.mpvSubPos > 50)
        assertTrue(landscape.letterboxBottom < 1f)
        assertTrue(landscape.bottomPaddingFraction < 0.12f)
        assertTrue(landscape.mpvSubPos > 88)
        assertTrue(filled.letterboxBottom < 1f)
        assertTrue(filled.bottomPaddingFraction < portrait.bottomPaddingFraction)
        val portraitPx = portrait.fractionalTextSize * 2400f
        val landscapePx = landscape.fractionalTextSize * 1080f
        assertTrue(portraitPx > landscapePx * 0.85f)
        assertTrue(portrait.mpvFontSize >= style.mpvFontSize)
    }

    @Test
    fun raisedPositionMovesCaptionsUpThePicture() {
        val lowered = SubtitlePictureLayout.placement(
            viewWidth = 1080,
            viewHeight = 2400,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = false,
            style = SubtitleAppearance.Snapshot(),
        )
        val raised = SubtitlePictureLayout.placement(
            viewWidth = 1080,
            viewHeight = 2400,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = false,
            style = SubtitleAppearance.Snapshot(positionLift = 50),
        )
        assertTrue(raised.bottomPaddingFraction > lowered.bottomPaddingFraction)
        assertTrue(raised.mpvSubPos < lowered.mpvSubPos)
    }
}
