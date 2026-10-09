import ARCMetrics
import ARCMetricsMocks
import Foundation
import OpenTelemetryApi
import Testing
@testable import ARCMetricsOTel

@Suite("Attribute scrubbing through the pipeline", .tags(.integration), .serialized, .timeLimit(.minutes(1)))
struct AttributeScrubbingPipelineTests {
    /// Removes every attribute.
    private static let removeAll = AttributeScrubber { _ in [:] }

    private func makeSUT(attributeScrubber: AttributeScrubber = .default) async throws -> ExporterHarness {
        try await ExporterHarness.make(attributeScrubber: attributeScrubber)
    }

    // MARK: Default scrubbing

    @Test("By default a span started through OTelTracer loses user.email at start and end, keeping the rest",
          .tags(.critical))
    func defaultScrubsTracerSpan() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let tracer = harness.telemetry.tracer

        let span = tracer.begin("Sync", category: .network, attributes: ["user.email": "a@b.test", "plan": "pro"])
        tracer.end(span, outcome: .ok, attributes: ["auth_token": "abc", "retries": 2])
        await harness.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.attributes == ["plan": .string("pro"), "retries": .int(2), "session.id": .string("s-1")])
    }

    @Test("By default emitEvent loses user.email and strips the url query", .tags(.critical))
    func defaultScrubsEmitEvent() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.telemetry.emitEvent("checkout",
                                    attributes: ["user.email": "a@b.test", "plan": "pro",
                                                 "url.full": "https://x.test/pay?card=1#top"])
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "checkout" })
        #expect(record.attributes == ["plan": .string("pro"), "url.full": .string("https://x.test/pay"),
                                      "session.id": .string("s-1")])
    }

    @Test("By default OTelTracer.event loses user.email") func defaultScrubsTracerEvent() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.telemetry.tracer.event("Tapped", category: .network, attributes: ["user.email": "a@b.test", "n": 1])
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "Tapped" })
        #expect(record.attributes == ["n": .int(1), "session.id": .string("s-1")])
    }

    // MARK: Custom scrubbers

    @Test("A custom scrubber runs on span start and span end attributes separately")
    func customRunsOnStartAndEnd() async throws {
        let scrubber = AttributeScrubber { $0.filter { !$0.key.hasPrefix("drop.") } }
        let harness = try await makeSUT(attributeScrubber: scrubber)
        defer { harness.sut.cleanUp() }
        let tracer = harness.telemetry.tracer

        let span = tracer.begin("Custom", category: .network, attributes: ["drop.start": 1, "keep.start": 2])
        tracer.end(span, outcome: .ok, attributes: ["drop.end": 3, "keep.end": 4])
        await harness.telemetry.flush()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.attributes == ["keep.start": .int(2), "keep.end": .int(4), "session.id": .string("s-1")])
    }

    @Test("A scrubber that removes everything still leaves session.id on spans and events", .tags(.critical))
    func removeAllKeepsSessionID() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }

        harness.telemetry.startSpan(id: 1, name: "bare", parentID: nil, attributes: ["a": .int(1)])
        harness.telemetry.endSpan(id: 1, errorType: nil, attributes: ["b": .int(2)])
        harness.telemetry.emitEvent("bare.event", attributes: ["c": 3])
        await harness.telemetry.flush()

        let span = try #require(harness.spans.exportedSpans.first { $0.name == "bare" })
        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "bare.event" })
        #expect(span.attributes == ["session.id": .string("s-1")])
        #expect(record.attributes == ["session.id": .string("s-1")])
    }

    @Test("A scrubber that injects session ids is overridden by the real ones", .tags(.critical))
    func injectedSessionIDsOverridden() async throws {
        let injector = AttributeScrubber {
            $0.merging(["session.id": "fake", "session.previous_id": "fake"]) { _, new in new }
        }
        let harness = try await makeSUT(attributeScrubber: injector)
        defer { harness.sut.cleanUp() }

        // Given activity in the first session, then a rotation (established before the records under test)
        harness.sut.recordEvent("first")
        await harness.telemetry.flush()
        harness.sut.clock.advance(by: 16 * 60)
        harness.telemetry.emitEvent("second")
        harness.telemetry.startSpan(id: 1, name: "after", parentID: nil, attributes: [:])
        harness.telemetry.endSpan(id: 1, errorType: nil, attributes: [:])
        await harness.telemetry.flush()

        // Then the records carry the real session and the real predecessor
        let first = try LogSummary(#require(harness.logs.exportedRecords.first { $0.eventName == "first" }))
        let second = try LogSummary(#require(harness.logs.exportedRecords.first { $0.eventName == "second" }))
        let span = try #require(harness.spans.exportedSpans.first { $0.name == "after" })
        #expect(first.sessionID == "s-1")
        #expect(second.sessionID == "s-2")
        #expect(second.previousID == "s-1")
        #expect(span.attributes["session.id"] == .string("s-2"))
        #expect(span.attributes["session.previous_id"] == .string("s-1"))
    }

    @Test("A scrubber chained after .default sees input that is already default-scrubbed")
    func chainSeesDefaultOutput() async throws {
        let probe = AttributeScrubber { attributes in
            attributes.merging(["saw.email": .bool(attributes["user.email"] != nil)]) { _, new in new }
        }
        let harness = try await makeSUT(attributeScrubber: AttributeScrubber.default.then(probe))
        defer { harness.sut.cleanUp() }

        harness.telemetry.emitEvent("probe", attributes: ["user.email": "a@b.test", "plan": "pro"])
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "probe" })
        #expect(record.attributes == ["plan": .string("pro"), "saw.email": .bool(false),
                                      "session.id": .string("s-1")])
    }

    @Test("Resource attributes are never scrubbed") func resourceNotScrubbed() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }

        harness.sut.recordSpan(id: 1, name: "res")
        harness.sut.recordEvent("res.event")
        await harness.telemetry.flush()

        let span = try #require(harness.spans.exportedSpans.first)
        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "res.event" })
        for resource in [span.resource.attributes, record.resource.attributes] {
            #expect(resource["service.name"] == .string("FavRes"))
            #expect(resource["service.version"] == .string("1.4.0"))
            #expect(resource["deployment.environment.name"] == .string("staging"))
            #expect(resource["device.model.identifier"] == .string("iPhone17,1"))
        }
    }

    // MARK: Package-produced records

    @Test("The scrubber also runs on a MetricKit metric span") func scrubsMetricSpan() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }
        let collector = ScriptedMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: harness.telemetry)

        collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        collector.finish()
        await bridge.run()
        await harness.telemetry.flush()

        let span = try #require(harness.spans.exportedSpans.first { $0.name == "MXMetricPayload" })
        #expect(span.attributes == ["session.id": .string("s-1")])
    }

    @Test("The scrubber also runs on crash and hang events") func scrubsCrashAndHang() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }
        let collector = ScriptedMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: harness.telemetry)

        collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash()],
                                                                    hangs: [.init(duration: 3)]))
        collector.finish()
        await bridge.run()
        await harness.telemetry.flush()

        let crash = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.crash" })
        let hang = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.hang" })
        #expect(crash.attributes == ["session.id": .string("s-1")])
        #expect(hang.attributes == ["session.id": .string("s-1")])
    }

    @Test("The scrubber also runs on lifecycle events") func scrubsLifecycle() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }
        let source = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: harness.telemetry, source: source)

        source.send(.foreground)
        source.finish()
        await observer.run()
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "device.app.lifecycle" })
        #expect(record.attributes == ["session.id": .string("s-1")])
    }

    @Test("The scrubber also runs on screen views") func scrubsScreenViews() async throws {
        let harness = try await makeSUT(attributeScrubber: Self.removeAll)
        defer { harness.sut.cleanUp() }

        ScreenViewTracker(emitter: harness.telemetry).screenAppeared("Home", attributes: ["extra": 1])
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.screen.view" })
        #expect(record.attributes == ["session.id": .string("s-1")])
    }
}
