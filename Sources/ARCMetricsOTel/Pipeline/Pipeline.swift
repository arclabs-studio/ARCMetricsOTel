import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk

/// The built OpenTelemetry objects. None of them is `Sendable`, so ``OTelTelemetry`` owns the
/// pipeline and touches it only from its own isolation.
///
/// Chain per signal: OTLP/HTTP exporter ← gated exporter ← persistence buffer ← buffer processor
/// ← provider (with ``SessionSampler`` for traces). The buffer processors batch on the actor's
/// thread: nothing reaches the disk buffer from a thread of its own.
final class Pipeline {
    let tracerProvider: TracerProviderSdk
    let loggerProvider: LoggerProviderSdk
    let tracer: any Tracer
    let logger: any OpenTelemetryApi.Logger
    let spanProcessor: BufferSpanProcessor
    let logProcessor: BufferLogProcessor

    init(tracerProvider: TracerProviderSdk,
         loggerProvider: LoggerProviderSdk,
         tracer: any Tracer,
         logger: any OpenTelemetryApi.Logger,
         spanProcessor: BufferSpanProcessor,
         logProcessor: BufferLogProcessor) {
        self.tracerProvider = tracerProvider
        self.loggerProvider = loggerProvider
        self.tracer = tracer
        self.logger = logger
        self.spanProcessor = spanProcessor
        self.logProcessor = logProcessor
    }

    /// Whether records are waiting to be written to the buffer.
    var hasPending: Bool {
        spanProcessor.hasPending || logProcessor.hasPending
    }

    /// Writes the records waiting in memory to the buffer, one batch per signal.
    func writePending() {
        spanProcessor.writePending()
        logProcessor.writePending()
    }

    /// Drops the records waiting in memory unwritten.
    func discardPending() {
        spanProcessor.discardPending()
        logProcessor.discardPending()
    }

    /// Writes what is pending, waits for the writes, then drains the buffer through the gated
    /// exporters.
    ///
    /// Blocks for up to `timeout` per signal: upstream flushes are synchronous.
    func flush(timeout: TimeInterval) {
        spanProcessor.forceFlush(timeout: timeout)
        _ = logProcessor.forceFlush(explicitTimeout: timeout)
    }

    /// Flushes, then shuts the exporters down.
    func shutdown(timeout: TimeInterval) {
        flush(timeout: timeout)
        tracerProvider.shutdown()
        _ = logProcessor.shutdown(explicitTimeout: timeout)
    }
}
