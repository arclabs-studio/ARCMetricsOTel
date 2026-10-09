import ARCMetrics
import Synchronization

/// A `MetricsCollecting` whose streams the test finishes by hand.
///
/// `MockMetricsCollector` never finishes its streams while it is alive, so a test cannot wait for a
/// consumer to drain them. This one buffers whatever is simulated and ends the streams on `finish()`,
/// which lets a test `await` a consumer's `run()` deterministically.
final class ScriptedMetricsCollector: MetricsCollecting {
    private struct State {
        var metrics: [AsyncStream<MetricSummary>.Continuation] = []
        var diagnostics: [AsyncStream<DiagnosticSummary>.Continuation] = []
        var startCalls = 0
        var stopCalls = 0
    }

    private let state = Mutex(State())

    var startCollectingCallCount: Int {
        state.withLock { $0.startCalls }
    }

    var stopCollectingCallCount: Int {
        state.withLock { $0.stopCalls }
    }

    var isCollecting: Bool {
        false
    }

    var pastMetricSummaries: [MetricSummary] {
        []
    }

    var pastDiagnosticSummaries: [DiagnosticSummary] {
        []
    }

    func metricSummaries() -> AsyncStream<MetricSummary> {
        let (stream, continuation) = AsyncStream.makeStream(of: MetricSummary.self)
        state.withLock { $0.metrics.append(continuation) }
        return stream
    }

    func diagnosticSummaries() -> AsyncStream<DiagnosticSummary> {
        let (stream, continuation) = AsyncStream.makeStream(of: DiagnosticSummary.self)
        state.withLock { $0.diagnostics.append(continuation) }
        return stream
    }

    func startCollecting() {
        state.withLock { $0.startCalls += 1 }
    }

    func stopCollecting() {
        state.withLock { $0.stopCalls += 1 }
    }

    func simulate(metric: MetricSummary) {
        for continuation in state.withLock({ $0.metrics }) {
            continuation.yield(metric)
        }
    }

    func simulate(diagnostic: DiagnosticSummary) {
        for continuation in state.withLock({ $0.diagnostics }) {
            continuation.yield(diagnostic)
        }
    }

    func finishMetrics() {
        for continuation in state.withLock({ $0.metrics }) {
            continuation.finish()
        }
    }

    func finishDiagnostics() {
        for continuation in state.withLock({ $0.diagnostics }) {
            continuation.finish()
        }
    }

    func finish() {
        finishMetrics()
        finishDiagnostics()
    }
}
