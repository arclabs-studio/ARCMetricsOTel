import Foundation
import OpenTelemetrySdk
import Synchronization

/// A `LogRecordExporter` that records what it is asked to do and answers with preset results.
///
/// Upstream's in-memory log exporter has no public initialiser, and its `async` defaults
/// `assertionFailure`, so this one implements every requirement.
final class RecordingLogExporter: LogRecordExporter {
    private struct State {
        var exported: [ReadableLogRecord] = []
        var exportCalls = 0
        var flushCalls = 0
        var shutdownCalls = 0
    }

    private let state = Mutex(State())
    private let exportResult: ExportResult
    private let flushResult: ExportResult

    init(exportResult: ExportResult = .success, flushResult: ExportResult = .success) {
        self.exportResult = exportResult
        self.flushResult = flushResult
    }

    var exportedRecords: [ReadableLogRecord] {
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

    func export(logRecords: [ReadableLogRecord], explicitTimeout _: TimeInterval?) -> ExportResult {
        recordExport(logRecords)
    }

    func shutdown(explicitTimeout _: TimeInterval?) {
        recordShutdown()
    }

    func forceFlush(explicitTimeout _: TimeInterval?) -> ExportResult {
        recordFlush()
    }

    func export(logRecords: [ReadableLogRecord], explicitTimeout _: TimeInterval?) async -> ExportResult {
        recordExport(logRecords)
    }

    func shutdown(explicitTimeout _: TimeInterval?) async {
        recordShutdown()
    }

    func forceFlush(explicitTimeout _: TimeInterval?) async -> ExportResult {
        recordFlush()
    }

    private func recordExport(_ records: [ReadableLogRecord]) -> ExportResult {
        state.withLock {
            $0.exported.append(contentsOf: records)
            $0.exportCalls += 1
        }
        return exportResult
    }

    private func recordFlush() -> ExportResult {
        state.withLock { $0.flushCalls += 1 }
        return flushResult
    }

    private func recordShutdown() {
        state.withLock { $0.shutdownCalls += 1 }
    }
}
