import OpenTelemetryApi

/// The severity of an event recorded with ``OTelTelemetry/emitEvent(_:attributes:severity:timestamp:)``.
///
/// Our own type rather than OpenTelemetry's `Severity`, so apps never import an OpenTelemetry
/// module. Each case is exported as the OpenTelemetry severity of the same name.
public enum EventSeverity: Sendable {
    /// Diagnostic detail, normally filtered out.
    case debug
    /// A normal occurrence.
    case info
    /// Something unexpected that the app recovered from.
    case warn
    /// A failed operation.
    case error
    /// A failure the app cannot continue after, such as a crash.
    case fatal
}

extension EventSeverity {
    var otelSeverity: Severity {
        switch self {
        case .debug:
            .debug
        case .info:
            .info
        case .warn:
            .warn
        case .error:
            .error
        case .fatal:
            .fatal
        }
    }
}
