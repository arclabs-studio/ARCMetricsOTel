import Foundation
import OpenTelemetrySdk
import Synchronization

/// A `SpanExporter` that records what it is asked to do and answers with preset results.
///
/// Implements the `async` requirements too: upstream's defaults `assertionFailure`.
final class RecordingSpanExporter: SpanExporter {
    private struct State {
        var exported: [SpanData] = []
        var exportCalls = 0
        var flushCalls = 0
        var shutdownCalls = 0
    }

    private let state = Mutex(State())
    private let exportResult: SpanExporterResultCode
    private let flushResult: SpanExporterResultCode

    init(exportResult: SpanExporterResultCode = .success, flushResult: SpanExporterResultCode = .success) {
        self.exportResult = exportResult
        self.flushResult = flushResult
    }

    var exportedSpans: [SpanData] {
        state.withLock { $0.exported }
    }

    var exportCalls: Int {
        state.withLock { $0.exportCalls }
    }

    var flushCalls: Int {
        state.withLock { $0.flushCalls }
    }

    var shutdownCalls: Int {
        state.withLock { $0.shutdownCalls }
    }

    func export(spans: [SpanData], explicitTimeout _: TimeInterval?) -> SpanExporterResultCode {
        recordExport(spans)
    }

    func flush(explicitTimeout _: TimeInterval?) -> SpanExporterResultCode {
        recordFlush()
    }

    func shutdown(explicitTimeout _: TimeInterval?) {
        recordShutdown()
    }

    func export(spans: [SpanData], explicitTimeout _: TimeInterval?) async -> SpanExporterResultCode {
        recordExport(spans)
    }

    func flush(explicitTimeout _: TimeInterval?) async -> SpanExporterResultCode {
        recordFlush()
    }

    func shutdown(explicitTimeout _: TimeInterval?) async {
        recordShutdown()
    }

    private func recordExport(_ spans: [SpanData]) -> SpanExporterResultCode {
        state.withLock {
            $0.exported.append(contentsOf: spans)
            $0.exportCalls += 1
        }
        return exportResult
    }

    private func recordFlush() -> SpanExporterResultCode {
        state.withLock { $0.flushCalls += 1 }
        return flushResult
    }

    private func recordShutdown() {
        state.withLock { $0.shutdownCalls += 1 }
    }
}
