import Foundation
import Synchronization
import Testing
@testable import ARCMetricsOTel

@Suite("TelemetryExecutor", .tags(.unit), .timeLimit(.minutes(1))) struct TelemetryExecutorTests {
    /// Hands the executor's thread out of the actor.
    private final class ThreadProbe: Sendable {
        let slot = Mutex<Thread?>(nil)

        var isFinished: Bool {
            slot.withLock { $0?.isFinished ?? false }
        }

        var name: String? {
            slot.withLock { $0?.name }
        }
    }

    /// An actor pinned to a `TelemetryExecutor`, as `OTelTelemetry` is.
    private actor Subject {
        private let executor: TelemetryExecutor
        private var log: [Int] = []
        private var counter = 0

        init(threadName: String) {
            executor = TelemetryExecutor(name: threadName)
        }

        deinit {
            executor.stop()
        }

        nonisolated var unownedExecutor: UnownedSerialExecutor {
            executor.asUnownedSerialExecutor()
        }

        /// Read inside a synchronous actor method, so it reports the thread the job really ran on.
        func currentThreadName() -> String? {
            Thread.current.name
        }

        func captureThread(into probe: ThreadProbe) {
            probe.slot.withLock { $0 = Thread.current }
        }

        func isMainThread() -> Bool {
            Thread.isMainThread
        }

        func append(_ value: Int) {
            log.append(value)
        }

        func increment() {
            let before = counter
            counter = before + 1
        }

        var appended: [Int] {
            log
        }

        var total: Int {
            counter
        }
    }

    @Test("Actor methods run on the thread the executor was named after") func runsOnNamedThread() async {
        let subject = Subject(threadName: "executor-under-test")

        let name = await subject.currentThreadName()

        #expect(name == "executor-under-test")
    }

    @Test("Two executors run their actors on separate threads") func separateThreadsPerExecutor() async {
        let first = Subject(threadName: "first-thread")
        let second = Subject(threadName: "second-thread")

        let names = await [first.currentThreadName(), second.currentThreadName()]

        #expect(names == ["first-thread", "second-thread"])
    }

    @Test("Jobs never run on the main thread") func offMainThread() async {
        let subject = Subject(threadName: "off-main")

        let isMain = await subject.isMainThread()

        #expect(!isMain)
    }

    @Test("Jobs from one task run in the order they were enqueued") func preservesOrderFromOneTask() async {
        let subject = Subject(threadName: "fifo")
        let values = Array(0 ..< 200)

        for value in values {
            await subject.append(value)
        }

        #expect(await subject.appended == values)
    }

    @Test("Concurrent callers never interleave: every increment is counted") func serialisesConcurrentCallers() async {
        let subject = Subject(threadName: "mutual-exclusion")
        let callers = 64
        let incrementsPerCaller = 50

        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< callers {
                group.addTask {
                    for _ in 0 ..< incrementsPerCaller {
                        await subject.increment()
                    }
                }
            }
        }

        #expect(await subject.total == callers * incrementsPerCaller)
    }

    @Test("The thread keeps serving jobs enqueued after earlier ones finished") func servesLaterJobs() async {
        let subject = Subject(threadName: "later-jobs")

        await subject.append(1)
        let firstName = await subject.currentThreadName()
        await subject.append(2)
        let secondName = await subject.currentThreadName()

        #expect(await subject.appended == [1, 2])
        #expect(firstName == "later-jobs")
        #expect(secondName == "later-jobs")
    }

    @Test("Releasing the actor lets the executor thread finish after it ran its last job")
    func threadExitsAfterRelease() async {
        let probe = ThreadProbe()
        do {
            let subject = Subject(threadName: "exits-after-release")
            await subject.captureThread(into: probe)
        }

        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !probe.isFinished, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(probe.name == "exits-after-release")
        #expect(probe.isFinished)
    }

    @Test("Jobs enqueued before the actor is released still run") func queuedJobsRunBeforeRelease() async {
        var result: [Int] = []
        do {
            let subject = Subject(threadName: "drain")
            async let first: Void = subject.append(1)
            async let second: Void = subject.append(2)
            _ = await (first, second)
            result = await subject.appended.sorted()
        }

        #expect(result == [1, 2])
    }
}
