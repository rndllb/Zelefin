package app.zelefin.core

import kotlin.math.floor

/**
 * Roku BIF scrub previews: an 8-byte magic, the frame count at offset 12 and the interval in
 * milliseconds at 16 (0 means 1000), then from offset 64 one (timestamp, offset) pair of
 * little-endian uint32s per frame and a closing pair whose offset marks the end of the last JPEG.
 */
class BifIndex private constructor(
    private val data: ByteArray,
    private val offsets: IntArray,
    val intervalSeconds: Double,
) {
    val frameCount: Int get() = offsets.size - 1

    fun frameIndex(seconds: Double): Int {
        if (frameCount <= 0) return 0
        return floor(seconds.coerceAtLeast(0.0) / intervalSeconds).toInt().coerceIn(0, frameCount - 1)
    }

    fun frame(index: Int): ByteArray? {
        if (index !in 0 until frameCount) return null
        val start = offsets[index]
        val end = offsets[index + 1]
        if (start < 0 || end > data.size || end <= start) return null
        return data.copyOfRange(start, end)
    }

    fun frameAt(seconds: Double): ByteArray? = frame(frameIndex(seconds))

    companion object {
        private val Magic = byteArrayOf(0x89.toByte(), 0x42, 0x49, 0x46, 0x0d, 0x0a, 0x1a, 0x0a)
        private const val IndexStart = 64

        /** Null for anything that is not a BIF with at least one frame. */
        fun parse(data: ByteArray): BifIndex? {
            if (data.size < IndexStart || !data.copyOfRange(0, Magic.size).contentEquals(Magic)) return null
            val count = uint32(data, 12)
            if (count <= 0 || IndexStart + (count + 1) * 8 > data.size) return null
            val intervalMillis = uint32(data, 16).takeIf { it > 0 } ?: 1000L
            val offsets = IntArray(count.toInt() + 1)
            for (entry in offsets.indices) {
                val offset = uint32(data, IndexStart + entry * 8 + 4)
                if (offset > data.size) return null
                offsets[entry] = offset.toInt()
            }
            return BifIndex(data, offsets, intervalMillis / 1000.0)
        }

        private fun uint32(data: ByteArray, at: Int): Long =
            (data[at].toLong() and 0xFF) or
                ((data[at + 1].toLong() and 0xFF) shl 8) or
                ((data[at + 2].toLong() and 0xFF) shl 16) or
                ((data[at + 3].toLong() and 0xFF) shl 24)
    }
}
