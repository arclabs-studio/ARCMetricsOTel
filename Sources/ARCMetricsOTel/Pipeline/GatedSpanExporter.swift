import Foundation
import OpenTelemetrySdk

/// Sits between the persistence buffer and the network exporter, and enforces the kill switch.
///
/// Upstream's persistence `flush()` ignores its `exportCondition`, so the buffer would still
/// reach the network while telemetry is off. While the gate is closed this exporter discards
/// the batch and reports success — the buffer deletes it, so the disk drains and nothing is sent.
///
/// Implements the `async` requirements too: upstream's defaults for them `assertionFailure`. They
/// block like the synchronous ones (an export waits on a network round-trip), so they must never
/// be called from Swift's cooperative pool; nothing in this package calls them.
final class GatedSpanExporter: SpanExporter {
    private let inner: any SpanExporter
    private let gate: TelemetryGate

    init(inner: any SpanExporter, gate: TelemetryGate) {
        self.inner = inner
        self.gate = gate
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        gatedExport(spans: spans, explicitTimeout: explicitTimeout)
    }

    func flush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        gatedFlush(explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) {
        innerShutdown(explicitTimeout: explicitTimeout)
    }

    func export(spans: [SpanData], explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        gatedExport(spans: spans, explicitTimeout: explicitTimeout)
    }

    func flush(explicitTimeout: TimeInterval?) async -> SpanExporterResultCode {
        gatedFlush(explicitTimeout: explicitTimeout)
    }

    func shutdown(explicitTimeout: TimeInterval?) async {
        innerShutdown(explicitTimeout: explicitTimeout)
    }
}

// MARK: - Gate

private extension GatedSpanExporter {
    func gatedExport(spans: [SpanData], explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        guard gate.allowsExport else {
            return .success
        }
        return inner.export(spans: spans, explicitTimeout: explicitTimeout)
    }

    func gatedFlush(explicitTimeout: TimeInterval?) -> SpanExporterResultCode {
        guard gate.allowsExport else {
            return .success
        }
        return inner.flush(explicitTimeout: explicitTimeout)
    }

    func innerShutdown(explicitTimeout: TimeInterval?) {
        inner.shutdown(explicitTimeout: explicitTimeout)
    }
}
