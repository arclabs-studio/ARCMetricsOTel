import Foundation

/// One unit of work for the ``OTelTelemetry`` actor, created synchronously at the call site.
///
/// Timestamps are read when the command is created, not when the actor processes it, so a
/// backlog never skews them.
/// `Sendable` is spelled out: Swift does not infer it for an `indirect` enum. The compiler still
/// checks every payload.
indirect enum TelemetryCommand: Sendable {
    /// A recording command, tagged with the gate's discard generation when it was made
    /// (``TelemetryGate/admission``).
    case admitted(TelemetryCommand, generation: Int)
    case startSpan(SpanStart)
    case endSpan(SpanEnd)
    case event(EventRecord)
    /// A span that already ended, such as a MetricKit report.
    case completedSpan(CompletedSpan)
    case resetSession(Date)
    /// Resumed once every command enqueued before it has been processed.
    case barrier(CheckedContinuation<Void, Never>)
}
