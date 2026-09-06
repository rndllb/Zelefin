import Foundation

enum HTTPRangeSupport {
    /// Inclusive RFC 7233 range for a half-open `[offset, offset + length)` window.
    static func rangeHeader(offset: Int64, length: Int) -> String {
        "bytes=\(offset)-\(offset + Int64(length) - 1)"
    }

    /// Total size from `Content-Range: bytes 0-0/12345`.
    static func parseContentRangeTotal(_ value: String) -> Int64? {
        guard let slash = value.lastIndex(of: "/") else { return nil }
        let total = value[value.index(after: slash)...].trimmingCharacters(in: .whitespaces)
        guard total != "*" else { return nil }
        return Int64(total)
    }

    static let avSeekSize: Int32 = 0x10000
    static let avSeekForce: Int32 = 0x20000

    /// Prefer the library's file size. HTTP probes through a reverse proxy often report a
    /// truncated total, which makes Matroska Cues look like they sit past EOF.
    static func preferredSize(known: Int64?, probed: Int64?) -> Int64? {
        if let known, known > 0 { return known }
        if let probed, probed > 0 { return probed }
        return nil
    }

    /// FFmpeg can combine `AVSEEK_SIZE` with `AVSEEK_FORCE`; both mean "report length, don't move".
    static func reportsSize(_ whence: Int32) -> Bool {
        (whence & avSeekSize) != 0
    }

    /// Strip FFmpeg seek flags so the remainder is `SEEK_SET` / `SEEK_CUR` / `SEEK_END`.
    static func seekWhence(_ whence: Int32) -> Int32 {
        whence & ~(avSeekSize | avSeekForce)
    }

    /// True when a read does not continue the previous one, i.e. the cursor was just
    /// repositioned by a seek. The first fetch after a seek must fail fast (see `readTimeout`).
    static func isSeekFill(position: Int64, lastFetchEnd: Int64) -> Bool {
        !(position == lastFetchEnd && lastFetchEnd >= 0)
    }

    /// Read-ahead window: doubles while reads stay sequential, otherwise resets to `base`.
    static func nextChunkSize(
        position: Int64,
        lastFetchEnd: Int64,
        current: Int,
        base: Int,
        maxChunk: Int
    ) -> Int {
        guard !isSeekFill(position: position, lastFetchEnd: lastFetchEnd) else { return base }
        return min(current * 2, maxChunk)
    }

    /// Per-request timeout for one range GET. A seek fill gets a tight budget so a stalled
    /// connection is abandoned well inside FFmpeg's ~8s Matroska reposition window and retried
    /// on a fresh connection; sequential reads keep the generous budget for slow WAN links.
    static func readTimeout(
        seekFill: Bool,
        sequentialTimeout: TimeInterval,
        seekFillTimeout: TimeInterval
    ) -> TimeInterval {
        seekFill ? min(seekFillTimeout, sequentialTimeout) : sequentialTimeout
    }
}
