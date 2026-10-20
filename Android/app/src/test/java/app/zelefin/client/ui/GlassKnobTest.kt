package app.zelefin.client.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class GlassKnobTest {
    @Test
    fun everyKnobReadsBackWhatItWrote() {
        GlassKnob.entries.forEach { knob ->
            val middle = (knob.range.start + knob.range.endInclusive) / 2f
            assertEquals(knob.title, middle, knob.read(knob.write(GlassStyle(), middle)), 0.001f)
        }
    }

    @Test
    fun knobsClampToTheirRange() {
        assertEquals(GlassKnob.Refraction.range.endInclusive, GlassKnob.Refraction.read(GlassKnob.Refraction.write(GlassStyle(), 500f)), 0.001f)
        assertEquals(GlassKnob.Frost.range.start, GlassKnob.Frost.read(GlassKnob.Frost.write(GlassStyle(), -3f)), 0.001f)
    }

    @Test
    fun darkerGlassGetsAMoreOpaqueFallback() {
        val light = GlassKnob.Darkness.write(GlassStyle(), 0f).fallbackFill.alpha
        val dark = GlassKnob.Darkness.write(GlassStyle(), 0.85f).fallbackFill.alpha
        assert(dark > light)
    }
}
