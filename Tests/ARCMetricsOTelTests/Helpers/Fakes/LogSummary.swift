import OpenTelemetryApi
import OpenTelemetrySdk
@testable import ARCMetricsOTel

/// The session facts of an exported log record, for readable assertions.
struct LogSummary {
    let eventName: String?
    let sessionID: String?
    let previousID: String?

    init(_ record: ReadableLogRecord) {
        eventName = record.eventName
        sessionID = SampleData.string(record.attributes[AttributeKeys.sessionID])
        previousID = SampleData.string(record.attributes[AttributeKeys.sessionPreviousID])
    }
}
