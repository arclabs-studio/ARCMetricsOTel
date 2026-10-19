import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter

/// Collects ended spans and writes them to the disk buffer in batches, on the ``OTelTelemetry``
/// actor's thread.
///
/// Spans end on the actor, and ``writePending()`` and ``discardPending()`` are only called from
/// it, so a kill-switch discard always sees every span: either still pending (dropped) or already
/// written (deleted from disk). Upstream's `BatchSpanProcessor` hands batches over from a worker
/// thread of its own, at a moment a discard cannot wait for. Only sampled spans reach `onEnd`:
/// ``SessionSampler`` never records a span it does not sample.
final class BufferSpanProcessor: SpanProcessor {
    private let buffer: PersistenceSpanExporterDecorator
    private let maxBatchSize: Int
    private var pending: [SpanData] = []

    let isStartRequired = false
    let isEndRequired = true

    init(buffer: PersistenceSpanExporterDecorator, maxBatchSize: Int) {
        self.buffer = buffer
        self.maxBatchSize = maxBatchSize
    }

    /// Whether spans are waiting to be written.
    var hasPending: Bool {
        !pending.isEmpty
    }

    func onStart(parentContext _: SpanContext?, span _: any ReadableSpan) {}

    func onEnd(span: any ReadableSpan) {
        pending.append(span.toSpanData())
        if pending.count >= maxBatchSize {
            writePending()
        }
    }

    /// Writes the pending spans to the buffer as one batch.
    func writePending() {
        guard !pending.isEmpty else { return }
        _ = buffer.export(spans: pending, explicitTimeout: nil)
        pending.removeAll()
    }

    /// Drops the pending spans unwritten.
    func discardPending() {
        pending.removeAll()
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        writePending()
        buffer.shutdown(explicitTimeout: explicitTimeout)
    }

    /// Writes the pending spans, waits for the writes, then drains the buffer through the gated
    /// exporter.
    func forceFlush(timeout: TimeInterval?) {
        writePending()
        _ = buffer.flush(explicitTimeout: timeout)
    }
}
