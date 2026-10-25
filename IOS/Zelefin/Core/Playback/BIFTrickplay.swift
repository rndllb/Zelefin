import Foundation
import UIKit

/// Roku BIF scrub thumbnails: an 8-byte magic, a 64-byte header, then an index of
/// (timestamp, offset) pairs ending in a 0xFFFFFFFF entry, then the JPEG frames back to back.
struct BIFIndex: Equatable, Sendable {
    struct Frame: Equatable, Sendable {
        let time: TimeInterval
        let bytes: Range<Int>
    }

    static let magic: [UInt8] = [0x89, 0x42, 0x49, 0x46, 0x0D, 0x0A, 0x1A, 0x0A]
    private static let headerSize = 64

    let version: UInt32
    let interval: TimeInterval
    let frames: [Frame]

    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count >= Self.headerSize, Array(bytes.prefix(8)) == Self.magic else { return nil }
        let count = Int(Self.uint32(bytes, at: 12))
        let unit = Self.uint32(bytes, at: 16)
        let millisecondsPerStamp = TimeInterval(unit == 0 ? 1000 : unit)
        let indexEnd = Self.headerSize + (count + 1) * 8
        guard indexEnd <= bytes.count else { return nil }

        var frames: [Frame] = []
        frames.reserveCapacity(count)
        for position in 0 ..< count {
            let entry = Self.headerSize + position * 8
            let stamp = Self.uint32(bytes, at: entry)
            let start = Int(Self.uint32(bytes, at: entry + 4))
            let end = Int(Self.uint32(bytes, at: entry + 12))
            guard start >= indexEnd, start < end, end <= bytes.count else { return nil }
            frames.append(Frame(time: TimeInterval(stamp) * millisecondsPerStamp / 1000, bytes: start ..< end))
        }
        version = Self.uint32(bytes, at: 8)
        interval = millisecondsPerStamp / 1000
        self.frames = frames
    }

    /// The last frame at or before `time`.
    func frameIndex(at time: TimeInterval) -> Int? {
        guard !frames.isEmpty else { return nil }
        var low = 0
        var high = frames.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if frames[mid].time <= time {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }
}

/// Downloads a title's BIF once, on the first scrub, and cuts frames out of it.
actor BIFPreviewStore {
    static let shared = BIFPreviewStore()

    private struct Loaded {
        let index: BIFIndex
        let data: Data
    }

    /// A feature-length BIF is several megabytes; only the titles just played stay in memory.
    private let capacity = 2
    private var loaded: [(url: URL, file: Loaded)] = []
    private var missing: Set<URL> = []
    private var inFlight: [URL: Task<Loaded?, Never>] = [:]

    func image(url: URL, at time: TimeInterval) async -> UIImage? {
        guard let file = await file(for: url), let position = file.index.frameIndex(at: time) else { return nil }
        let range = file.index.frames[position].bytes
        return UIImage(data: file.data.subdata(in: range))
    }

    private func file(for url: URL) async -> Loaded? {
        if let hit = loaded.first(where: { $0.url == url }) { return hit.file }
        if missing.contains(url) { return nil }
        if let task = inFlight[url] { return await task.value }
        let task = Task<Loaded?, Never> {
            guard let (data, response) = try? await JellyfinNetworking.apiData(for: URLRequest(url: url)),
                  (response as? HTTPURLResponse).map({ (200 ..< 300).contains($0.statusCode) }) ?? false,
                  let index = BIFIndex(data: data),
                  !index.frames.isEmpty
            else { return nil }
            return Loaded(index: index, data: data)
        }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        if let result {
            loaded.append((url, result))
            if loaded.count > capacity { loaded.removeFirst(loaded.count - capacity) }
        } else {
            missing.insert(url)
        }
        return result
    }
}
