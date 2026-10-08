import Foundation
import OpenTelemetryApi

/// A span to end.
struct SpanEnd {
    let id: UInt64
    /// The error's type name when the operation failed, for example `URLError`. Never the
    /// message: it is exported as `error.type` and as the span status description.
    let errorType: String?
    let attributes: [String: AttributeValue]
    let time: Date
}
