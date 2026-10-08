import Foundation
import OpenTelemetryApi

/// A span to start.
struct SpanStart {
    /// The caller's token for the span; ends it later.
    let id: UInt64
    let name: String
    /// The token of the parent span, if it is still open.
    let parentID: UInt64?
    let attributes: [String: AttributeValue]
    let time: Date
}
