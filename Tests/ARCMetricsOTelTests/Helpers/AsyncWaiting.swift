import Foundation
@testable import ARCMetricsOTel

/// Flushes the pipeline and re-checks `condition`, sleeping between rounds, until it holds or `timeout` passes.
///
/// For records produced by a consumer task the test cannot await: each flush drains what has reached the
/// queue so far. Sleep-polling, never a `Task.yield()` spin.
func flushing(_ telemetry: OTelTelemetry,
              timeout: Duration = .seconds(30),
              until condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while true {
        await telemetry.flush()
        if condition() {
            return true
        }
        guard ContinuousClock.now < deadline else {
            return false
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// Whether `operation` finished before `timeout`. On timeout the operation is cancelled.
func completes(within timeout: Duration = .seconds(10),
               _ operation: @escaping @Sendable () async -> Void) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            await operation()
            return true
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
}
