import ARCMetrics
import Foundation
import OpenTelemetryApi
import PersistenceExporter
import Testing
@testable import ARCMetricsOTel

/// The disk buffer stores each batch the processors hand it as one object, and drops an object
/// above `maxObjectSize` without a trace. These run a backlog through the production buffer limits
/// and expect every record on the other side.
@Suite("Large batches", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct LargeBatchTests {
    private struct Harness {
        let telemetry: OTelTelemetry
        let spans: RecordingSpanExporter
        let logs: RecordingLogExporter
        let scratch: TemporaryDirectory
    }

    private static let count = 1000

    private func makeSUT() async throws -> Harness {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let scratch = TemporaryDirectory()
        var dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s-1"],
                                                           exporters: ExporterOverride(spans: spans, logs: logs),
                                                           storageRoot: scratch.root)
        dependencies.performancePreset = .arcMetricsOTel
        let telemetry = try await OTelBootstrap
            .configure(TestConfiguration.make(settings: TelemetrySettings(isEnabled: true, sampleRate: 1)),
                       dependencies: dependencies)
        return Harness(telemetry: telemetry, spans: spans, logs: logs, scratch: scratch)
    }

    @Test("1,000 spans flushed at once all reach the exporter", .tags(.critical)) func spanBacklog() async throws {
        let harness = try await makeSUT()
        defer { harness.scratch.remove() }

        // Given 1,000 ended spans waiting in the batch processor
        let tracer = harness.telemetry.tracer
        for _ in 0 ..< Self.count {
            let span = tracer.begin("Load", category: .network)
            tracer.end(span, outcome: .ok, attributes: [:])
        }

        // When they are flushed through the production disk buffer
        await harness.telemetry.flush()

        // Then every one is exported
        #expect(Set(harness.spans.exportedSpans.map(\.spanId.hexString)).count == Self.count)
    }

    @Test("1,000 events flushed at once all reach the exporter", .tags(.critical)) func eventBacklog() async throws {
        let harness = try await makeSUT()
        defer { harness.scratch.remove() }

        // Given 1,000 events waiting in the batch processor
        let tracer = harness.telemetry.tracer
        for index in 0 ..< Self.count {
            tracer.event("Tick", category: .network, attributes: ["index": .int(index)])
        }

        // When they are flushed through the production disk buffer
        await harness.telemetry.flush()

        // Then every one is exported
        let indices = harness.logs.exportedRecords.compactMap { record -> Int? in
            guard case let .int(index) = record.attributes["index"] else { return nil }
            return index
        }
        #expect(Set(indices).count == Self.count)
    }
}
