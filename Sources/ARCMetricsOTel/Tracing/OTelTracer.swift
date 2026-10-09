import ARCMetrics
import OpenTelemetryApi

/// Sends ARCMetrics ``ARCMetrics/Tracing`` spans and events to OpenTelemetry.
///
/// Get one from ``OTelTelemetry/tracer`` and combine it with the signpost tracer, so each span
/// reaches MetricKit and the collector with the same id:
///
/// ```swift
/// let tracer = TeeTracer([MetricKitSignpostTracer(), telemetry.tracer])
///
/// let restaurants = try await tracer.trace("FetchAll", category: .persistence) { _ in
///     try await repository.fetchAll()
/// }
/// ```
///
/// Every call returns immediately: it reads the clock and enqueues a record for the telemetry
/// actor. A span's `parentID` becomes its OpenTelemetry parent while the parent is still open;
/// ``ARCMetrics/TraceOutcome/error(type:)`` sets the span's status to error and its `error.type`
/// attribute. A span that is never ended is never exported. The span category is not exported.
public struct OTelTracer: Tracing {
    private let telemetry: OTelTelemetry

    init(telemetry: OTelTelemetry) {
        self.telemetry = telemetry
    }

    public func start(_ span: TraceSpan, attributes: TraceAttributes) {
        telemetry.startSpan(id: span.id,
                            name: "\(span.name)",
                            parentID: span.parentID,
                            attributes: attributes.otelAttributes)
    }

    public func end(_ span: TraceSpan, outcome: TraceOutcome, attributes: TraceAttributes) {
        telemetry.endSpan(id: span.id, errorType: outcome.errorType, attributes: attributes.otelAttributes)
    }

    public func event(_ name: StaticString, category _: SignpostCategory, attributes: TraceAttributes) {
        telemetry.emitEvent(name: "\(name)", attributes: attributes.otelAttributes, severity: .info)
    }
}

// MARK: - Mapping

private extension TraceOutcome {
    var errorType: String? {
        switch self {
        case .ok:
            nil
        case let .error(type):
            type
        }
    }
}

private extension [String: TraceAttributeValue] {
    var otelAttributes: [String: AttributeValue] {
        mapValues { value in
            switch value {
            case let .string(string):
                .string(string)
            case let .int(int):
                .int(int)
            case let .double(double):
                .double(double)
            case let .bool(bool):
                .bool(bool)
            }
        }
    }
}
