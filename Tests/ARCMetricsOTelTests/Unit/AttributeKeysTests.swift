import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("AttributeKeys", .tags(.integration, .critical), .timeLimit(.minutes(1))) struct AttributeKeysTests {
    /// Every key the package itself puts on spans, log events and session events.
    private static let recordKeys: Set = ["session.id", "session.previous_id", "error.type"]

    /// Every Resource key: the package's own plus the SDK defaults.
    private static let resourceKeys: Set = ["service.name", "service.version", "deployment.environment.name",
                                            "os.name", "os.version", "os.type", "device.model.identifier",
                                            "telemetry.sdk.language", "telemetry.sdk.name", "telemetry.sdk.version"]

    @Test("Spans, log events, session events and the Resource carry exactly the allowlisted keys")
    func emittedKeysMatchAllowlist() async throws {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(sessionIDs: ["s-1", "s-2"],
                                                   exporters: ExporterOverride(spans: spans, logs: logs))
        defer { sut.cleanUp() }

        sut.telemetry.startSpan(id: 1, name: "failing", parentID: nil, attributes: [:])
        sut.telemetry.endSpan(id: 1, errorType: "boom", attributes: [:])
        sut.recordEvent("plain-event")
        sut.clock.advance(by: 16 * 60)
        sut.recordEvent("after-rotation")
        await sut.telemetry.flush()

        let exportedSpans = spans.exportedSpans
        let exportedLogs = logs.exportedRecords
        #expect(!exportedSpans.isEmpty)
        #expect(exportedLogs.contains { $0.eventName == EventNames.sessionEnd })
        #expect(exportedLogs.contains { $0.eventName == EventNames.sessionStart })

        var recordKeys = Set<String>()
        var resourceKeys = Set<String>()
        for span in exportedSpans {
            recordKeys.formUnion(span.attributes.keys)
            resourceKeys.formUnion(span.resource.attributes.keys)
        }
        for record in exportedLogs {
            recordKeys.formUnion(record.attributes.keys)
            resourceKeys.formUnion(record.resource.attributes.keys)
        }

        #expect(recordKeys == Self.recordKeys)
        #expect(resourceKeys == Self.resourceKeys)
    }
}
