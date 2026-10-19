import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("TelemetryClock", .tags(.unit)) struct TelemetryClockTests {
    @Test("The system clock reads the wall clock") func systemClockIsWallClock() {
        let before = Date()
        let now = SystemClock().now
        let after = Date()

        #expect(before <= now)
        #expect(now <= after)
    }
}
