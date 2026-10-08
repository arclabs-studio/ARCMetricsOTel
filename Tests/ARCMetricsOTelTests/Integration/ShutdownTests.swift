import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Shutdown", .tags(.integration), .timeLimit(.minutes(1))) struct ShutdownTests {
    private struct Harness {
        let sut: IntegrationSUT
        let spans: RecordingSpanExporter
        let logs: RecordingLogExporter
    }

    private func makeSUT() async throws -> Harness {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(exporters: ExporterOverride(spans: spans, logs: logs))
        return Harness(sut: sut, spans: spans, logs: logs)
    }

    @Test("Records enqueued before shutdown are exported, and the exporters are shut down")
    func drainsBeforeShutdown() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.sut.recordSpan(id: 1, name: "before")
        harness.sut.recordEvent("before-event")
        await harness.sut.telemetry.shutdown()

        #expect(harness.spans.exportedSpans.map(\.name) == ["before"])
        #expect(harness.logs.exportedRecords.contains { $0.eventName == "before-event" })
        #expect(harness.spans.shutdownCalls >= 1)
        #expect(harness.logs.shutdownCalls >= 1)
    }

    @Test("Records made after shutdown are ignored") func ignoresAfterShutdown() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        harness.sut.recordSpan(id: 1, name: "before")
        await harness.sut.telemetry.shutdown()

        harness.sut.recordSpan(id: 2, name: "after")
        harness.sut.recordEvent("after-event")
        await harness.sut.telemetry.flush()

        #expect(harness.spans.exportedSpans.map(\.name) == ["before"])
        #expect(!harness.logs.exportedRecords.contains { $0.eventName == "after-event" })
    }

    @Test("Flush after shutdown returns promptly instead of waiting for a queue nobody reads")
    func flushAfterShutdownReturns() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        harness.sut.recordSpan(id: 1, name: "before")
        await harness.sut.telemetry.shutdown()
        #expect(harness.spans.exportedSpans.map(\.name) == ["before"])

        let elapsed = await ContinuousClock().measure {
            await harness.sut.telemetry.flush()
        }

        #expect(elapsed < .seconds(2))
    }
}
