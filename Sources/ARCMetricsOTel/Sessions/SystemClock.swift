import Foundation

/// The real wall clock.
struct SystemClock: TelemetryClock {
    var now: Date {
        Date()
    }
}
