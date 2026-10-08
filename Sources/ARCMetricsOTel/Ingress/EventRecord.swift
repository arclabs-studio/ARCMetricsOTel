import Foundation
import OpenTelemetryApi

/// A log event to emit.
struct EventRecord {
    let name: String
    let attributes: [String: AttributeValue]
    let severity: Severity
    let time: Date
}
