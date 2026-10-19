/// Waits until `condition` holds or `timeout` passes, sleeping between checks.
///
/// Sleeping rather than spinning on `Task.yield()` leaves the CPU to the threads under test:
/// a spin loop kept a core busy and starved the export threads on CI's three-core runners.
///
/// Runs on the caller's actor, so `condition` may read main-actor state.
///
/// - Returns: Whether `condition` held before the timeout.
func eventually(timeout: Duration = .seconds(30),
                pollingEvery interval: Duration = .milliseconds(10),
                isolation _: isolated (any Actor)? = #isolation,
                _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            return false
        }
        try? await Task.sleep(for: interval)
    }
    return true
}
