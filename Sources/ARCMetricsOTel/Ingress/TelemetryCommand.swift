import Foundation

/// One unit of work for the ``OTelTelemetry`` actor, created synchronously at the call site.
///
/// Timestamps are read when the command is created, not when the actor processes it, so a
/// backlog never skews them.
enum TelemetryCommand {
    case startSpan(SpanStart)
    case endSpan(SpanEnd)
    case event(EventRecord)
    case resetSession(Date)
    /// Resumed once every command enqueued before it has been processed.
    case barrier(CheckedContinuation<Void, Never>)
}
