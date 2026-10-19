import ARCMetrics
import Foundation

/// A span that already ended, recorded in one step.
struct CompletedSpan {
    let name: String
    let attributes: TraceAttributes
    let start: Date
    let end: Date
    /// When the span was recorded: the session is looked up at this time, never at `start` or `end`.
    let sessionTime: Date
}
