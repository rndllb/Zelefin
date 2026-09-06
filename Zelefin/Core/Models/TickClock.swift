import Foundation

enum TickClock {
    static let ticksPerSecond: Int64 = 10_000_000

    static func seconds(from ticks: Int64) -> TimeInterval {
        TimeInterval(ticks) / TimeInterval(ticksPerSecond)
    }

    static func seconds(from ticks: Int) -> TimeInterval {
        seconds(from: Int64(ticks))
    }

    static func ticks(from seconds: TimeInterval) -> Int64 {
        Int64((seconds * TimeInterval(ticksPerSecond)).rounded())
    }

    static func intTicks(from seconds: TimeInterval) -> Int {
        Int(ticks(from: seconds))
    }
}
