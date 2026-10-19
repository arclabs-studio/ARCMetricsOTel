import Foundation
import Synchronization

/// The serial executor ``OTelTelemetry`` runs on: one dedicated thread, outside Swift's
/// cooperative pool.
///
/// OpenTelemetry's flush and shutdown block the calling thread until an export finishes on an
/// `OperationQueue`. On the cooperative pool, enough concurrent flushes occupy every pool thread
/// while the exports they wait for are never scheduled — a deadlock. Running the actor here keeps
/// every blocking upstream call off the pool.
///
/// Jobs run in enqueue order. The thread exits once ``stop()`` has been called and the queue is empty.
final class TelemetryExecutor: SerialExecutor {
    private struct State {
        var jobs: [UnownedJob] = []
        var isStopped = false
    }

    /// Guards `state` changes together with the wake-up, so a signal is never lost.
    private let condition = NSCondition()
    private let state = Mutex(State())

    init(name: String) {
        let thread = Thread { [self] in
            run()
        }
        thread.name = name
        // `.default`, not `.utility`: tests waiting on this thread stalled for minutes on three-core
        // CI runners, and starvation of a utility-QoS thread is the suspected cause. The work is brief.
        thread.qualityOfService = .default
        thread.start()
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        condition.lock()
        state.withLock { $0.jobs.append(job) }
        condition.signal()
        condition.unlock()
    }

    /// Lets the thread exit after it runs the jobs already queued.
    func stop() {
        condition.lock()
        state.withLock { $0.isStopped = true }
        condition.signal()
        condition.unlock()
    }
}

// MARK: - Run loop

private extension TelemetryExecutor {
    func run() {
        while let batch = nextBatch() {
            for job in batch {
                job.runSynchronously(on: asUnownedSerialExecutor())
            }
        }
    }

    /// Waits for queued jobs and takes them all; `nil` once stopped with nothing left to run.
    func nextBatch() -> [UnownedJob]? {
        condition.lock()
        defer { condition.unlock() }
        while state.withLock({ $0.jobs.isEmpty && !$0.isStopped }) {
            condition.wait()
        }
        return state.withLock { state in
            defer { state.jobs.removeAll() }
            return state.jobs.isEmpty ? nil : state.jobs
        }
    }
}
