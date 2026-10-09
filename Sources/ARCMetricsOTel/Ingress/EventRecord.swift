import Foundation
import OpenTelemetryApi

/// A log event to emit.
struct EventRecord {
    let name: String
    let attributes: [String: AttributeValue]
    let severity: Severity
    /// The record's timestamp.
    let time: Date
    /// When the record was made: the session is looked up at this time, never at `time`, so a
    /// record about the past (a MetricKit report) cannot end or rotate the current session.
    let sessionTime: Date

    init(name: String, attributes: [String: AttributeValue], severity: Severity, time: Date, sessionTime: Date? = nil) {
        self.name = name
        self.attributes = attributes
        self.severity = severity
        self.time = time
        self.sessionTime = sessionTime ?? time
    }
}
