import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter

/// The built OpenTelemetry objects. None of them is `Sendable`, so ``OTelTelemetry`` owns the
/// pipeline and touches it only from its own isolation.
///
/// Chain per signal: OTLP/HTTP exporter ← gated exporter ← persistence buffer ← batch processor
/// ← provider (with ``SessionSampler`` for traces).
final class Pipeline {
    let tracerProvider: TracerProviderSdk
    let loggerProvider: LoggerProviderSdk
    let tracer: any Tracer
    let logger: any OpenTelemetryApi.Logger
    let spanProcessor: BatchSpanProcessor
    let logProcessor: BatchLogRecordProcessor
    let spanBuffer: PersistenceSpanExporterDecorator
    let logBuffer: PersistenceLogExporterDecorator

    init(tracerProvider: TracerProviderSdk,
         loggerProvider: LoggerProviderSdk,
         tracer: any Tracer,
         logger: any OpenTelemetryApi.Logger,
         spanProcessor: BatchSpanProcessor,
         logProcessor: BatchLogRecordProcessor,
         spanBuffer: PersistenceSpanExporterDecorator,
         logBuffer: PersistenceLogExporterDecorator) {
        self.tracerProvider = tracerProvider
        self.loggerProvider = loggerProvider
        self.tracer = tracer
        self.logger = logger
        self.spanProcessor = spanProcessor
        self.logProcessor = logProcessor
        self.spanBuffer = spanBuffer
        self.logBuffer = logBuffer
    }

    /// Pushes queued records into the buffer, then drains the buffer through the gated exporters.
    ///
    /// Blocks for up to `timeout` per stage: upstream flushes are synchronous.
    func flush(timeout: TimeInterval) {
        spanProcessor.forceFlush(timeout: timeout)
        _ = logProcessor.forceFlush(explicitTimeout: timeout)
        _ = spanBuffer.flush(explicitTimeout: timeout)
        _ = logBuffer.forceFlush(explicitTimeout: timeout)
    }

    /// Flushes, then shuts the exporters down.
    func shutdown(timeout: TimeInterval) {
        flush(timeout: timeout)
        tracerProvider.shutdown()
        _ = logProcessor.shutdown(explicitTimeout: timeout)
    }
}
