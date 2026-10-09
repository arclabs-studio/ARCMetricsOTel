import Foundation
import OpenTelemetrySdk

/// The log counterpart of ``GatedSpanExporter``: discards batches, reporting success, while the
/// kill switch is off, so the persistence buffer drains without reaching the network.
///
/// Like ``GatedSpanExporter``, its `async` overloads block and must never run on Swift's
/// cooperative pool.
struct GatedLogExporter: LogRecordExporter {
    let inner: any LogRecordExporter
    let gate: TelemetryGate

    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        gatedExport(logRecords: logRecords, explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        innerShutdown(explicitTimeout: explicitTimeout)
    }

    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        gatedFlush(explicitTimeout: explicitTimeout)
    }

    func export(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) async -> ExportResult {
        gatedExport(logRecords: logRecords, explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) async {
        innerShutdown(explicitTimeout: explicitTimeout)
    }

    func forceFlush(explicitTimeout: TimeInterval?) async -> ExportResult {
        gatedFlush(explicitTimeout: explicitTimeout)
    }
}

// MARK: - Gate

private extension GatedLogExporter {
    func gatedExport(logRecords: [ReadableLogRecord], explicitTimeout: TimeInterval?) -> ExportResult {
        guard gate.allowsExport else {
            return .success
        }
        return inner.export(logRecords: logRecords, explicitTimeout: explicitTimeout)
    }

    func gatedFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        guard gate.allowsExport else {
            return .success
        }
        return inner.forceFlush(explicitTimeout: explicitTimeout)
    }

    func innerShutdown(explicitTimeout: TimeInterval?) {
        inner.shutdown(explicitTimeout: explicitTimeout)
    }
}
