package app.zelefin.client

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        // Fill changes where the picture sits; ExoPlayer size stays tied to the window. MPV's
        // sub-scale shrinks by the panscan zoom so image captions do not grow with the crop.
        assertEquals(portrait.fractionalTextSize, filled.fractionalTextSize, 0.001f)
        assertTrue(filled.mpvSubScale < style.sizeScale)
        assertEquals(style.sizeScale / SubtitlePictureLayout.fillZoom(1080f, 2400f, 1920f, 1080f), filled.mpvSubScale, 0.01f)
        val portraitPx = portrait.fractionalTextSize * 2400f
        val landscapePx = landscape.fractionalTextSize * 1080f
        assertTrue(portraitPx > landscapePx * 0.85f)
        assertTrue(portrait.mpvFontSize >= style.mpvFontSize)
    }

    @Test
    fun fillScreenDoesNotGrowOrCropCaptions() {
        val style = SubtitleAppearance.Snapshot()
        val windowW = 1920
        val windowH = 1080
        val fourByThree = SubtitlePictureLayout.placement(
            viewWidth = windowW,
            viewHeight = windowH,
            videoWidth = 1440f,
            videoHeight = 1080f,
            fill = false,
            style = style,
        )
        val filled = SubtitlePictureLayout.placement(
            viewWidth = windowW,
            viewHeight = windowH,
            videoWidth = 1440f,
            videoHeight = 1080f,
            fill = true,
            style = style,
        )
        assertEquals(1.333f, SubtitlePictureLayout.fillZoom(1920f, 1080f, 1440f, 1080f), 0.01f)
        assertEquals(style.sizeScale / (1920f / 1440f), filled.mpvSubScale, 0.01f)
        assertTrue(filled.mpvSubScale < fourByThree.mpvSubScale)
        assertEquals(fourByThree.fractionalTextSize, filled.fractionalTextSize, 0.001f)
        assertTrue(filled.mpvSubPos <= 100)
        assertTrue(filled.bottomPaddingFraction >= 0.05f)

        val matching = SubtitlePictureLayout.placement(
            viewWidth = windowW,
            viewHeight = windowH,
            videoWidth = 1920f,
            videoHeight = 1080f,
            fill = true,
            style = SubtitleAppearance.Snapshot(size = SubtitleAppearance.SIZE_LARGE),
        )
        assertEquals(1.28f, matching.mpvSubScale, 0.001f)
        assertTrue(matching.mpvSubPos in 90..100)
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

    @Test
    fun pictureSubtitlesAreRecognised() {
        listOf("hdmv_pgs_subtitle", "application/pgs", "dvd_subtitle", "application/vobsub", "application/dvbsubs", "PGSSUB")
            .forEach { assertTrue(it, SubtitleAppearance.isPictureCodec(it)) }
        listOf("subrip", "ass", "application/x-subrip", "text/x-ssa", "text/vtt", null)
            .forEach { assertFalse(it.toString(), SubtitleAppearance.isPictureCodec(it)) }
    }

    @Test
    fun captionsRiseAboveVisibleControlsOnly() {
        val style = SubtitleAppearance.Snapshot()
        fun place(controlsTop: Float?, videoHeight: Float = 1080f) = SubtitlePictureLayout.placement(
            viewWidth = 2400,
            viewHeight = 1080,
            videoWidth = 1920f,
            videoHeight = videoHeight,
            fill = false,
            style = style,
            controlsTop = controlsTop,
        )
        val hidden = place(null)
        val shown = place(900f)
        assertEquals(83, shown.mpvSubPos)
        assertEquals((1080f - 900f) / 1080f, shown.bottomPaddingFraction, 0.001f)
        assertTrue(shown.mpvSubPos < hidden.mpvSubPos)
        // Controls that end below where captions already sit leave them alone.
        assertEquals(hidden.mpvSubPos, place(1070f).mpvSubPos)
    }
}

