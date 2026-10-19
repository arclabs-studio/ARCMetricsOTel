import Foundation
import OpenTelemetrySdk
import PersistenceExporter

/// Collects emitted log records and writes them to the disk buffer in batches, on the
/// ``OTelTelemetry`` actor's thread. See ``BufferSpanProcessor`` for why.
final class BufferLogProcessor: LogRecordProcessor {
    private let buffer: PersistenceLogExporterDecorator
    private let maxBatchSize: Int
    private var pending: [ReadableLogRecord] = []

    init(buffer: PersistenceLogExporterDecorator, maxBatchSize: Int) {
        self.buffer = buffer
        self.maxBatchSize = maxBatchSize
    }

    /// Whether log records are waiting to be written.
    var hasPending: Bool {
        !pending.isEmpty
    }

    func onEmit(logRecord: ReadableLogRecord) {
        pending.append(logRecord)
        if pending.count >= maxBatchSize {
            writePending()
        }
    }

    /// Writes the pending log records to the buffer as one batch.
    func writePending() {
        guard !pending.isEmpty else { return }
        _ = buffer.export(logRecords: pending, explicitTimeout: nil)
        pending.removeAll()
    }

    /// Drops the pending log records unwritten.
    func discardPending() {
        pending.removeAll()
    }

    /// Writes the pending log records, waits for the writes, then drains the buffer through the
    /// gated exporter.
    func forceFlush(explicitTimeout: TimeInterval?) -> ExportResult {
        writePending()
        return buffer.forceFlush(explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) -> ExportResult {
        writePending()
        buffer.shutdown(explicitTimeout: explicitTimeout)
        return .success
    }
}
