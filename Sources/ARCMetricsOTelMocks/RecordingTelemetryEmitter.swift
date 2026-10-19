import ARCMetrics
import ARCMetricsOTel
import Foundation
import Synchronization

/// A ``ARCMetricsOTel/TelemetryEmitting`` that records every event, for tests and previews.
///
/// ```swift
/// let recorder = RecordingTelemetryEmitter()
/// let view = HomeView().telemetry(recorder)
/// // …
/// #expect(recorder.events.map(\.name) == ["app.screen.view"])
/// ```
public final class RecordingTelemetryEmitter: TelemetryEmitting {
    /// One recorded event.
    public struct Event: Sendable, Equatable {
        /// The event name.
        public let name: String
        /// The attributes, exactly as passed: no scrubbing and no session stamping.
        public let attributes: TraceAttributes
        /// The severity.
        public let severity: EventSeverity
        /// The timestamp passed, or `nil` for "now".
        public let timestamp: Date?
    }

    private let recorded = Mutex<[Event]>([])

    /// Creates an empty recorder.
    public init() {}

    /// Every event so far, in the order they were emitted.
    public var events: [Event] {
        recorded.withLock { $0 }
    }

    /// Records the event.
    public func emitEvent(_ name: String, attributes: TraceAttributes, severity: EventSeverity, timestamp: Date?) {
        let event = Event(name: name, attributes: attributes, severity: severity, timestamp: timestamp)
        recorded.withLock { $0.append(event) }
    }
}
