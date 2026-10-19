import Foundation
import Synchronization
@testable import ARCMetricsOTel

/// A `TelemetryClock` the test advances by hand.
final class FakeClock: TelemetryClock {
    private let state: Mutex<Date>
    private let readCount = Mutex(0)

    init(start: Date = FakeClock.epoch) {
        state = Mutex(start)
    }

    /// How many times `now` has been read: a record's timestamp is taken by reading it.
    var reads: Int {
        readCount.withLock { $0 }
    }

    /// A fixed, arbitrary instant every test starts from.
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        readCount.withLock { $0 += 1 }
        return state.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
