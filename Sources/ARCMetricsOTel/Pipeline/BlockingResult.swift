import Foundation
import Synchronization

/// A result produced by a task and awaited by a thread that must block — the bridge for
/// upstream's synchronous, completion-based `HTTPClient` requirement.
///
/// Only for threads outside Swift's cooperative pool: blocking a pool thread can starve the task
/// that would resolve the result.
final class BlockingResult<Success: Sendable>: Sendable {
    private struct Pending: Error {}

    private struct State {
        var outcome: Result<Success, any Error> = .failure(Pending())
        var isResolved = false
    }

    /// Guards `state` changes together with the wake-up, so a signal is never lost.
    private let condition = NSCondition()
    private let state = Mutex(State())

    /// Stores `outcome` and wakes the waiting thread.
    func resolve(_ outcome: Result<Success, any Error>) {
        condition.lock()
        state.withLock { $0 = State(outcome: outcome, isResolved: true) }
        condition.signal()
        condition.unlock()
    }

    /// Blocks until ``resolve(_:)`` has stored an outcome or `deadline` passes. Returns the
    /// outcome, or `nil` on timeout.
    func wait(until deadline: Date) -> Result<Success, any Error>? {
        condition.lock()
        defer { condition.unlock() }
        while !state.withLock({ $0.isResolved }), condition.wait(until: deadline) {}
        return state.withLock { $0.isResolved ? $0.outcome : nil }
    }
}
