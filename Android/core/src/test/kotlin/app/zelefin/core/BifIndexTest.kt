package app.zelefin.core

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BifIndexTest {
    private fun bif(frames: List<ByteArray>, intervalMillis: Int): ByteArray {
        val header = ByteArray(64)
        byteArrayOf(0x89.toByte(), 0x42, 0x49, 0x46, 0x0d, 0x0a, 0x1a, 0x0a).copyInto(header)
        fun put(target: ByteArray, at: Int, value: Long) {
            for (shift in 0 until 4) target[at + shift] = ((value shr (8 * shift)) and 0xFF).toByte()
        }
        put(header, 12, frames.size.toLong())
        put(header, 16, intervalMillis.toLong())
        val index = ByteArray((frames.size + 1) * 8)
        var offset = 64L + index.size
        frames.forEachIndexed { entry, frame ->
            put(index, entry * 8, entry.toLong())
            put(index, entry * 8 + 4, offset)
            offset += frame.size
        }
        put(index, frames.size * 8, 0xFFFFFFFFL)
        put(index, frames.size * 8 + 4, offset)
        return header + index + frames.fold(ByteArray(0)) { all, frame -> all + frame }
    }

    private val frames = listOf(byteArrayOf(1, 1, 1), byteArrayOf(2, 2), byteArrayOf(3, 3, 3, 3))

    @Test
    fun readsFramesByTime() {
        val parsed = BifIndex.parse(bif(frames, intervalMillis = 2000))!!
        assertEquals(3, parsed.frameCount)
        assertEquals(2.0, parsed.intervalSeconds, 0.0)
        assertArrayEquals(frames[0], parsed.frameAt(0.0))
        assertArrayEquals(frames[0], parsed.frameAt(1.9))
        assertArrayEquals(frames[1], parsed.frameAt(2.0))
        assertArrayEquals(frames[2], parsed.frameAt(4.5))
        assertArrayEquals(frames[2], parsed.frameAt(600.0))
        assertArrayEquals(frames[0], parsed.frameAt(-3.0))
        assertNull(parsed.frame(3))
    }

    @Test
    fun zeroIntervalMeansOneSecond() {
        assertEquals(1.0, BifIndex.parse(bif(frames, intervalMillis = 0))!!.intervalSeconds, 0.0)
    }

    @Test
    fun emptyOrForeignFilesHaveNoPreviews() {
        assertNull(BifIndex.parse(bif(emptyList(), intervalMillis = 1000)))
        assertNull(BifIndex.parse(ByteArray(72)))
        assertNull(BifIndex.parse("not a bif".toByteArray()))
        val truncated = bif(frames, intervalMillis = 1000).copyOf(70)
        assertNull(BifIndex.parse(truncated))
    }
}
