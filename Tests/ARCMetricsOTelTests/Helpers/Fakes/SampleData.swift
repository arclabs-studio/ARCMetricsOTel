import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

/// Builds upstream value types that have no public initialiser.
enum SampleData {
    /// A real `SpanData`, taken from a span the SDK created.
    static func spanData(named name: String,
                         attributes: [String: AttributeValue] = [:],
                         resource: Resource = Resource()) throws -> SpanData {
        let tracer = TracerProviderBuilder().with(resource: resource).build().get(instrumentationName: "tests")
        let builder = tracer.spanBuilder(spanName: name)
        for (key, value) in attributes {
            builder.setAttribute(key: key, value: value)
        }
        let span = builder.startSpan()
        let readable = try #require(span as? any ReadableSpan)
        span.end()
        return readable.toSpanData()
    }

    static func logRecord(eventName: String,
                          attributes: [String: AttributeValue] = [:],
                          resource: Resource = Resource()) -> ReadableLogRecord {
        ReadableLogRecord(resource: resource,
                          instrumentationScopeInfo: InstrumentationScopeInfo(),
                          timestamp: FakeClock.epoch,
                          severity: .info,
                          attributes: attributes,
                          eventName: eventName)
    }

    /// A string attribute's value, or `nil` when absent or not a string.
    static func string(_ value: AttributeValue?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text
    }
}
