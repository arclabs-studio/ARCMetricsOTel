import ARCMetrics
import ARCMetricsMocks
import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import PersistenceExporter
import Testing
@testable import ARCMetricsOTel

@Suite("OTel tracer", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct OTelTracerTests {
    private struct Harness {
        let sut: IntegrationSUT
        let spans: RecordingSpanExporter
        let logs: RecordingLogExporter

        var tracer: OTelTracer {
            sut.telemetry.tracer
        }
    }

    private func makeSUT(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1)) async throws
    -> Harness {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(settings: settings,
                                                   sessionIDs: ["s-1", "s-2"],
                                                   exporters: ExporterOverride(spans: spans, logs: logs))
        return Harness(sut: sut, spans: spans, logs: logs)
    }

    // MARK: Spans

    @Test("A span is exported with the tracer's name, once, only after it ends") func exportsNamedSpanOnEnd() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given a started span
        let span = harness.tracer.begin("FetchAll", category: .persistence)
        await harness.sut.telemetry.flush()
        #expect(harness.spans.exportedSpans.isEmpty)

        // When it ends
        harness.tracer.end(span, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()

        // Then exactly one span with that name is exported, and the category leaks nowhere
        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(harness.spans.exportedSpans.count == 1)
        #expect(exported.name == "FetchAll")
        #expect(!exported.attributes.values.contains { $0.description.contains("Persistence") })
        #expect(!exported.attributes.keys.contains { $0.lowercased().contains("categor") })
    }

    @Test("Start and end attributes keep their OTel types on the exported span") func attributeTypes() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given a span with one attribute of each type at start and another set at end
        let span = harness.tracer.begin("Typed",
                                        category: .network,
                                        attributes: ["start.string": "cloudkit", "start.int": 7,
                                                     "start.double": 0.25, "start.bool": true])
        harness.tracer.end(span,
                           outcome: .ok,
                           attributes: ["end.string": "done", "end.int": -3, "end.double": 1.5, "end.bool": false])
        await harness.sut.telemetry.flush()

        // Then each lands as the matching AttributeValue case
        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.attributes["start.string"] == .string("cloudkit"))
        #expect(exported.attributes["start.int"] == .int(7))
        #expect(exported.attributes["start.double"] == .double(0.25))
        #expect(exported.attributes["start.bool"] == .bool(true))
        #expect(exported.attributes["end.string"] == .string("done"))
        #expect(exported.attributes["end.int"] == .int(-3))
        #expect(exported.attributes["end.double"] == .double(1.5))
        #expect(exported.attributes["end.bool"] == .bool(false))
    }

    @Test("Attribute types survive the OTLP wire for string, int and bool") func attributeTypesOnTheWire() async throws {
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }

        let tracer = sut.telemetry.tracer
        let span = tracer.begin("Wire", category: .network, attributes: ["a.string": "x", "a.int": 42])
        tracer.end(span, outcome: .ok, attributes: ["a.bool": true])
        await sut.telemetry.flush()

        let decoded = try #require(sut.deliveredTraces.spans.first)
        #expect(decoded.name == "Wire")
        #expect(decoded.attributes["a.string"] == "x")
        #expect(decoded.attributes["a.int"] == "42")
        #expect(decoded.attributes["a.bool"] == "true")
    }

    @Test("The span's duration comes from the injected clock between start and end") func durationFromClock() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        let span = harness.tracer.begin("Timed", category: .launch)
        harness.sut.clock.advance(by: 2)
        harness.tracer.end(span, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.endTime.timeIntervalSince(exported.startTime) == 2)
    }

    @Test("An error outcome exports a failed span tagged error.type, with the end attributes")
    func errorOutcome() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        let span = harness.tracer.begin("Save", category: .persistence)
        harness.tracer.end(span, outcome: .error(type: "CocoaError"), attributes: ["retries": 3])
        await harness.sut.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.status == .error(description: "CocoaError"))
        #expect(exported.attributes["error.type"] == .string("CocoaError"))
        #expect(exported.attributes["retries"] == .int(3))
    }

    @Test("An ok outcome exports a span that is not failed") func okOutcome() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        let span = harness.tracer.begin("Save", category: .persistence)
        harness.tracer.end(span, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        // OTel leaves a successful span's status unset; only failures set one.
        #expect(exported.status == .unset)
        #expect(exported.attributes["error.type"] == nil)
    }

    @Test("A throwing trace ends the span as an error named after the thrown type") func throwingTrace() async throws {
        struct Boom: Error {}
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        _ = try? harness.tracer.trace("Risky", category: .network) { _ -> Int in throw Boom() }
        await harness.sut.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.name == "Risky")
        #expect(exported.status == .error(description: "Boom"))
    }

    // MARK: Parenting

    @Test("A child begun with parent: shares the trace and points at the parent's span id") func parentChild() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        let parent = harness.tracer.begin("Parent", category: .launch)
        let child = harness.tracer.begin("Child", category: .launch, parent: parent)
        harness.tracer.end(child, outcome: .ok, attributes: [:])
        harness.tracer.end(parent, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()

        let exportedParent = try #require(harness.spans.exportedSpans.first { $0.name == "Parent" })
        let exportedChild = try #require(harness.spans.exportedSpans.first { $0.name == "Child" })
        #expect(exportedChild.traceId == exportedParent.traceId)
        #expect(exportedChild.parentSpanId == exportedParent.spanId)
        #expect(exportedParent.parentSpanId == nil)
    }

    @Test("Nested async trace calls export a parent chain over the wire") func nestedTraceOnTheWire() async throws {
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        let tracer = sut.telemetry.tracer

        await tracer.trace("Outer", category: .launch) { outer in
            await tracer.trace("Inner", category: .launch, parent: outer) { _ in await Task.yield() }
        }
        await sut.telemetry.flush()

        let spans = sut.deliveredTraces.spans
        let outer = try #require(spans.first { $0.name == "Outer" })
        let inner = try #require(spans.first { $0.name == "Inner" })
        #expect(inner.traceID == outer.traceID)
        #expect(inner.parentSpanID == outer.spanID)
        #expect(outer.parentSpanID.isEmpty)
    }

    @Test("Nested sync trace calls export child under parent") func nestedSyncTrace() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let tracer = harness.tracer

        tracer.trace("Outer", category: .launch) { outer in
            tracer.trace("Inner", category: .launch, parent: outer) { _ in }
        }
        await harness.sut.telemetry.flush()

        let outer = try #require(harness.spans.exportedSpans.first { $0.name == "Outer" })
        let inner = try #require(harness.spans.exportedSpans.first { $0.name == "Inner" })
        #expect(inner.traceId == outer.traceId)
        #expect(inner.parentSpanId == outer.spanId)
    }

    // MARK: Concurrency

    @Test("1,000 concurrent begin/end pairs export exactly 1,000 distinct spans") func concurrentSpans() async throws {
        // Given a pipeline whose disk buffer fits a full 512-span batch (the shared harness preset caps an
        // object at 64 kB, which a batch that size exceeds). 1,000 pairs are 2,000 commands, well under
        // the ingress queue's 10,000 capacity: if either number changes, a full queue drops spans silently
        // and this fails as "missing spans", not as an overflow.
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        var dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s-1"],
                                                           exporters: ExporterOverride(spans: spans, logs: logs),
                                                           storageRoot: scratch.root)
        dependencies.performancePreset = PersistencePerformancePreset(maxFileSize: 8 * 1024 * 1024,
                                                                      maxDirectorySize: 64 * 1024 * 1024,
                                                                      maxFileAgeForWrite: 0.01,
                                                                      minFileAgeForRead: 0,
                                                                      maxFileAgeForRead: 3600,
                                                                      maxObjectsInFile: 500,
                                                                      maxObjectSize: 1024 * 1024,
                                                                      synchronousWrite: true,
                                                                      initialExportDelay: 3600,
                                                                      defaultExportDelay: 3600,
                                                                      minExportDelay: 3600,
                                                                      maxExportDelay: 3600,
                                                                      exportDelayChangeRate: 0.1)
        let telemetry = try await OTelBootstrap
            .configure(TestConfiguration.make(settings: TelemetrySettings(isEnabled: true,
                                                                          sampleRate: 1)),
                       dependencies: dependencies)
        let tracer = telemetry.tracer
        let count = 1000

        // When 1,000 spans are begun and ended from concurrent tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< count {
                group.addTask {
                    let span = tracer.begin("Load", category: .network)
                    tracer.end(span, outcome: .ok, attributes: [:])
                }
            }
        }
        await telemetry.flush()

        // Then every one is exported once, with a distinct id
        let exported = spans.exportedSpans
        #expect(exported.count == count)
        #expect(Set(exported.map(\.spanId.hexString)).count == count)
        #expect(exported.allSatisfy { $0.name == "Load" })
    }

    // MARK: Never ended

    @Test("A span that is begun but never ended is not exported by a flush or by shutdown") func openSpanNeverExported() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        _ = harness.tracer.begin("Leaked", category: .media)
        let finished = harness.tracer.begin("Finished", category: .media)
        harness.tracer.end(finished, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()
        #expect(harness.spans.exportedSpans.map(\.name) == ["Finished"])

        await harness.sut.telemetry.shutdown()
        #expect(harness.spans.exportedSpans.map(\.name) == ["Finished"])
    }

    // MARK: Events

    @Test("An event becomes one info log record with its name, typed attributes and the session")
    func eventRecord() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.tracer.event("cache.miss", category: .persistence,
                             attributes: ["source": "disk", "count": 2, "ratio": 0.5, "warm": false])
        await harness.sut.telemetry.flush()

        let matching = harness.logs.exportedRecords.filter { $0.eventName == "cache.miss" }
        let record = try #require(matching.first)
        #expect(matching.count == 1)
        #expect(record.severity == .info)
        #expect(record.attributes["source"] == .string("disk"))
        #expect(record.attributes["count"] == .int(2))
        #expect(record.attributes["ratio"] == .double(0.5))
        #expect(record.attributes["warm"] == .bool(false))
        #expect(LogSummary(record).sessionID == "s-1")
    }

    // MARK: Composition

    @Test("Through a TeeTracer both sides see the same span, and OTel keeps name and parentage") func teeTracer() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let recording = RecordingTracer()
        let tee = TeeTracer([recording, harness.tracer])

        let parent = tee.begin("Sync", category: .network)
        let child = tee.begin("Upload", category: .network, parent: parent)
        tee.end(child, outcome: .ok, attributes: [:])
        tee.end(parent, outcome: .ok, attributes: [:])
        await harness.sut.telemetry.flush()

        #expect(recording.startedSpans.map(\.id) == [parent.id, child.id])
        #expect(recording.endedSpans.map(\.id) == [child.id, parent.id])
        let exportedParent = try #require(harness.spans.exportedSpans.first { $0.name == "Sync" })
        let exportedChild = try #require(harness.spans.exportedSpans.first { $0.name == "Upload" })
        #expect(exportedChild.parentSpanId == exportedParent.spanId)
    }

    // MARK: Kill switch

    @Test("With telemetry disabled the tracer produces nothing") func disabledProducesNothing() async throws {
        let harness = try await makeSUT(settings: .disabled)
        defer { harness.sut.cleanUp() }

        harness.tracer.trace("Quiet", category: .launch) { _ in }
        harness.tracer.event("quiet.event", category: .launch, attributes: [:])
        await harness.sut.telemetry.flush()

        #expect(harness.spans.exportedSpans.isEmpty)
        #expect(harness.logs.exportedRecords.isEmpty)
        #expect(harness.sut.requests.isEmpty)
    }
}
