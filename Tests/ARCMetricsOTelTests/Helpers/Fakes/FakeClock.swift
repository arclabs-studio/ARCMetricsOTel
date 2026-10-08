import Foundation
import Synchronization
@testable import ARCMetricsOTel

/// A `TelemetryClock` the test advances by hand.
final class FakeClock: TelemetryClock {
    private let state: Mutex<Date>

    init(start: Date = FakeClock.epoch) {
        state = Mutex(start)
    }

    /// A fixed, arbitrary instant every test starts from.
    static let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        state.withLock { $0 }
    }

    func advance(by interval: TimeInterval) {
        state.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}
