import Synchronization
@testable import ARCMetricsOTel

/// A `LifecycleEventSource` the test feeds by hand.
final class ScriptedLifecycleSource: LifecycleEventSource {
    private let stream: AsyncStream<AppLifecycleState>
    private let continuation: AsyncStream<AppLifecycleState>.Continuation
    private let calls = Mutex(0)

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: AppLifecycleState.self)
    }

    /// How many times `states()` was asked for.
    var statesCallCount: Int {
        calls.withLock { $0 }
    }

    func states() -> AsyncStream<AppLifecycleState> {
        calls.withLock { $0 += 1 }
        return stream
    }

    func send(_ state: AppLifecycleState) {
        continuation.yield(state)
    }

    func finish() {
        continuation.finish()
    }
}
