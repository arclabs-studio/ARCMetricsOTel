import ARCMetrics
import Foundation

/// Something that records events: ``OTelTelemetry``, or a test double such as
/// `RecordingTelemetryEmitter` from `ARCMetricsOTelMocks`.
public protocol TelemetryEmitting: Sendable {
    /// Records an event. See ``OTelTelemetry/emitEvent(_:attributes:severity:timestamp:)``.
    func emitEvent(_ name: String, attributes: TraceAttributes, severity: EventSeverity, timestamp: Date?)
}

extension OTelTelemetry: TelemetryEmitting {}
