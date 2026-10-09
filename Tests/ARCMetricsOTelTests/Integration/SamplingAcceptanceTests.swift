import Foundation
import InMemoryExporter
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("Acceptance: session-consistent sampling", .tags(.integration, .critical), .serialized, .timeLimit(.minutes(1)))
struct SamplingAcceptanceTests {
    private let rate = 0.5

    private struct Harness {
        let sut: IntegrationSUT
        let spans: InMemoryExporter
        let logs: RecordingLogExporter
        let sampledID: String
        let droppedID: String
    }

    private func makeSUT() async throws -> Harness {
        let sampledID = ReferenceSampling.id(sampledAt: rate, wantSampled: true)
        let droppedID = ReferenceSampling.id(sampledAt: rate, wantSampled: false)
        let spans = InMemoryExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(settings: TelemetrySettings(isEnabled: true, sampleRate: rate),
                                                   sessionIDs: [sampledID, droppedID],
                                                   exporters: ExporterOverride(spans: spans, logs: logs))
        return Harness(sut: sut, spans: spans, logs: logs, sampledID: sampledID, droppedID: droppedID)
    }

    /// A parent span, a child span under it, and an event.
    private func recordTree(_ prefix: String, on sut: IntegrationSUT, firstSpanID: UInt64) {
        sut.telemetry.startSpan(id: firstSpanID, name: "\(prefix)-parent", parentID: nil, attributes: [:])
        sut.telemetry.startSpan(id: firstSpanID + 1, name: "\(prefix)-child", parentID: firstSpanID, attributes: [:])
        sut.telemetry.endSpan(id: firstSpanID + 1, errorType: nil, attributes: [:])
        sut.telemetry.endSpan(id: firstSpanID, errorType: nil, attributes: [:])
        sut.recordEvent("\(prefix)-event")
    }

    @Test("Every record of the sampled session is exported and none of the dropped one")
    func exportsOnlySampledSession() async throws {
        // Given a 50% rate and two sessions, one sampled in and one sampled out
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let sut = harness.sut

        // When each session records a span tree and an event, and the session is reset between them
        recordTree("a", on: sut, firstSpanID: 10)
        sut.telemetry.resetSession()
        recordTree("b", on: sut, firstSpanID: 20)
        await sut.telemetry.flush()

        // Then only the sampled session's spans and logs left the process
        let spans = harness.spans.getFinishedSpanItems()
        let logs = harness.logs.exportedRecords
        let spanSessions = Set(spans.compactMap { SampleData.string($0.attributes[AttributeKeys.sessionID]) })
        let logSessions = Set(logs.compactMap { SampleData.string($0.attributes[AttributeKeys.sessionID]) })

        #expect(Set(spans.map(\.name)) == ["a-parent", "a-child"])
        #expect(spans.count == 2)
        #expect(spanSessions == [harness.sampledID])
        #expect(logs.map(\.eventName).contains("a-event"))
        #expect(!logs.contains { $0.eventName == "b-event" })
        #expect(logSessions == [harness.sampledID])
    }

    @Test("A child span shares its parent's trace and points at it") func childSharesTrace() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        recordTree("a", on: harness.sut, firstSpanID: 10)
        await harness.sut.telemetry.flush()

        let spans = harness.spans.getFinishedSpanItems()
        let parent = try #require(spans.first { $0.name == "a-parent" })
        let child = try #require(spans.first { $0.name == "a-child" })
        #expect(child.traceId == parent.traceId)
        #expect(child.parentSpanId == parent.spanId)
        #expect(parent.parentSpanId == nil)
    }
}
