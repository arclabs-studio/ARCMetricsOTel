import ARCMetrics
import ARCMetricsMocks
import Foundation
import OpenTelemetryApi
import Testing
@testable import ARCMetricsOTel

@Suite("MetricKit bridge", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct MetricKitBridgeTests {
    private struct Harness {
        let exporters: ExporterHarness
        let collector: ScriptedMetricsCollector
        let bridge: MetricKitBridge

        var sut: IntegrationSUT {
            exporters.sut
        }

        var telemetry: OTelTelemetry {
            exporters.telemetry
        }

        var spans: RecordingSpanExporter {
            exporters.spans
        }

        var logs: RecordingLogExporter {
            exporters.logs
        }

        /// Ends the scripted streams, lets the bridge drain them, and flushes.
        func drain() async {
            collector.finish()
            await bridge.run()
            await exporters.telemetry.flush()
        }
    }

    private func makeSUT(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1)) async throws
    -> Harness {
        let exporters = try await ExporterHarness.make(settings: settings)
        let collector = ScriptedMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: exporters.telemetry)
        return Harness(exporters: exporters, collector: collector, bridge: bridge)
    }

    // MARK: Metrics

    @Test("A metric summary becomes one MXMetricPayload span over its interval with every metrickit attribute")
    func metricSummaryBecomesSpan() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given a summary with distinct hand-picked values
        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        await harness.drain()

        // Then one root span spans the interval, with the hand-computed attribute values
        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(harness.spans.exportedSpans.count == 1)
        #expect(exported.name == "MXMetricPayload")
        #expect(exported.startTime == MetricKitFixtures.intervalStart)
        #expect(exported.endTime == MetricKitFixtures.intervalEnd)
        #expect(exported.parentSpanId == nil)
        var expected = MetricKitFixtures.fullMetricAttributes.mapValues { AttributeValue.double($0) }
        expected["session.id"] = .string("s-1")
        #expect(exported.attributes == expected)
    }

    @Test("Absent hitch ratios are omitted rather than exported as zero") func nilHitchRatiosOmitted() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        var summary = MetricKitFixtures.fullMetricSummary()
        summary.hitchTimeRatio = nil
        summary.scrollHitchTimeRatio = nil

        harness.collector.simulate(metric: summary)
        await harness.drain()

        let exported = try #require(harness.spans.exportedSpans.first)
        #expect(exported.attributes["metrickit.animation.hitch_time_ratio_ms_per_s"] == nil)
        #expect(exported.attributes["metrickit.animation.scroll_hitch_time_ratio_ms_per_s"] == nil)
        #expect(exported.attributes["metrickit.cpu.cpu_time"] == .double(12.5))
        #expect(exported.attributes.count == MetricKitFixtures.fullMetricAttributes.count - 2 + 1)
    }

    @Test("A metric summary without an interval exports nothing") func metricWithoutIntervalIgnored() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector.simulate(metric: MetricSummary(timeRange: "last 24 hours"))
        await harness.drain()

        #expect(harness.spans.exportedSpans.isEmpty)
    }

    // MARK: Diagnostics

    @Test("A crash becomes a fatal app.crash record at the interval's end, without the memory region")
    func crashRecord() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash()]))
        await harness.drain()

        let matching = harness.logs.exportedRecords.filter { $0.eventName == "app.crash" }
        let record = try #require(matching.first)
        #expect(matching.count == 1)
        #expect(record.severity == .fatal)
        #expect(record.timestamp == MetricKitFixtures.intervalEnd)
        #expect(record.attributes == ["exception.type": .string("EXC_BAD_ACCESS"),
                                      "exception.signal": .string("SIGSEGV"),
                                      "exception.termination_reason": .string("Namespace SIGNAL, Code 11"),
                                      "session.id": .string("s-1")])
        #expect(!record.attributes.values.contains { $0.description.contains(MetricKitFixtures.secretRegionInfo) })
    }

    @Test("Nil crash fields are not exported as attributes") func crashNilFieldsOmitted() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let crash = MetricKitFixtures.crash(exceptionType: nil, signal: "SIGABRT", terminationReason: nil)

        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [crash]))
        await harness.drain()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.crash" })
        #expect(record.attributes == ["exception.signal": .string("SIGABRT"), "session.id": .string("s-1")])
    }

    @Test("A structured termination reason is exported unchanged",
          arguments: ["Namespace SIGNAL, Code 11", "Namespace FRONTBOARD, Code 0x8badf00d",
                      "Namespace CODESIGNING, Code 2"])
    func structuredTerminationReasonExported(reason: String) async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector
            .simulate(diagnostic: MetricKitFixtures
                .diagnostic(crashes: [MetricKitFixtures.crash(terminationReason: reason)]))
        await harness.drain()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.crash" })
        #expect(record.attributes["exception.termination_reason"] == .string(reason))
    }

    @Test("A free-text termination reason is left out, keeping the rest of the crash",
          arguments: ["Namespace DYLD, Code 1, Library missing | Library not loaded: @rpath/Foo.framework/Foo | Referenced from: "
              + "/private/var/containers/Bundle/Application/0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0/App.app/App",
              "Namespace FRONTBOARD, Code 0x8badf00d scene-update watchdog for <com.example.app>",
              "Namespace SIGNAL, Code \(String(repeating: "9", count: 200))",
              "Termination reason with no structure at all"])
    func freeTextTerminationReasonOmitted(reason: String) async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector
            .simulate(diagnostic: MetricKitFixtures
                .diagnostic(crashes: [MetricKitFixtures.crash(terminationReason: reason)]))
        await harness.drain()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.crash" })
        #expect(record.attributes["exception.termination_reason"] == nil)
        #expect(record.attributes["exception.type"] == .string("EXC_BAD_ACCESS"))
        #expect(record.attributes["exception.signal"] == .string("SIGSEGV"))
    }

    @Test("Each hang becomes a warn app.hang record carrying its duration in seconds") func hangRecords() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let hangs = [DiagnosticSummary.HangInfo(duration: 2.5), DiagnosticSummary.HangInfo(duration: 9)]

        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(hangs: hangs))
        await harness.drain()

        let records = harness.logs.exportedRecords.filter { $0.eventName == "app.hang" }
        #expect(records.count == 2)
        #expect(records.allSatisfy { $0.severity == .warn && $0.timestamp == MetricKitFixtures.intervalEnd })
        #expect(records.map { $0.attributes["app.hang.duration_s"] } == [.double(2.5), .double(9)])
    }

    @Test("Several crashes and hangs in one summary each export their own record") func multipleRecords() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let summary = MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash(), MetricKitFixtures.crash()],
                                                   hangs: [.init(duration: 1), .init(duration: 2), .init(duration: 3)])

        harness.collector.simulate(diagnostic: summary)
        await harness.drain()

        let names = harness.logs.exportedRecords.map(\.eventName)
        #expect(names.filter { $0 == "app.crash" }.count == 2)
        #expect(names.filter { $0 == "app.hang" }.count == 3)
    }

    @Test("A diagnostic summary without an interval exports nothing") func diagnosticWithoutIntervalIgnored() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        var summary = DiagnosticSummary(timeRange: "last 24 hours")
        summary.crashes = [MetricKitFixtures.crash()]
        summary.hangs = [.init(duration: 4)]

        harness.collector.simulate(diagnostic: summary)
        await harness.drain()

        #expect(!harness.logs.exportedRecords.contains { $0.eventName == "app.crash" || $0.eventName == "app.hang" })
    }

    // MARK: Session rule

    @Test("A diagnostic from yesterday does not start a session at yesterday or end today's",
          .tags(.critical))
    func diagnosticIntervalDoesNotDriveSession() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given a crash whose interval ended a day before the clock's now
        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash()]))
        harness.collector.finish()
        await harness.bridge.run()
        // When ordinary activity follows a minute later
        harness.sut.clock.advance(by: 60)
        harness.sut.recordEvent("later.event")
        await harness.telemetry.flush()

        // Then there is a single session, started at the clock's now
        let records = harness.logs.exportedRecords
        let starts = records.filter { $0.eventName == "session.start" }
        #expect(starts.count == 1)
        #expect(starts.first?.timestamp == FakeClock.epoch)
        #expect(!records.contains { $0.eventName == "session.end" })
        #expect(Set(records.compactMap { LogSummary($0).sessionID }) == ["s-1"])
    }

    @Test("A metric span from yesterday does not start a session at yesterday or end today's",
          .tags(.critical))
    func metricIntervalDoesNotDriveSession() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        harness.collector.finish()
        await harness.bridge.run()
        harness.sut.clock.advance(by: 60)
        harness.sut.recordEvent("later.event")
        await harness.telemetry.flush()

        let records = harness.logs.exportedRecords
        let starts = records.filter { $0.eventName == "session.start" }
        #expect(starts.count == 1)
        #expect(starts.first?.timestamp == FakeClock.epoch)
        #expect(!records.contains { $0.eventName == "session.end" })
        #expect(Set(records.compactMap { LogSummary($0).sessionID }) == ["s-1"])
        #expect(harness.spans.exportedSpans.first?.attributes["session.id"] == .string("s-1"))
    }

    // MARK: Gating

    @Test("With the kill switch off or an unsampled session, nothing is exported",
          arguments: [TelemetrySettings.disabled, TelemetrySettings(isEnabled: true, sampleRate: 0)])
    func gatedSettingsExportNothing(settings: TelemetrySettings) async throws {
        let harness = try await makeSUT(settings: settings)
        defer { harness.sut.cleanUp() }

        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash()],
                                                                            hangs: [.init(duration: 3)]))
        await harness.drain()

        #expect(harness.spans.exportedSpans.isEmpty)
        #expect(harness.logs.exportedRecords.isEmpty)
        #expect(harness.sut.requests.isEmpty)
    }

    // MARK: Subscription and run

    @Test("Summaries simulated after init but before run() are delivered once run() starts") func subscribesInInit() async throws {
        let exporters = try await ExporterHarness.make()
        defer { exporters.sut.cleanUp() }
        let collector = MockMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: exporters.telemetry)

        // Given a summary delivered before anyone consumes (the mock keeps no replay for late subscribers)
        collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        let task = Task { await bridge.run() }
        let delivered = await flushing(exporters.telemetry) { !exporters.spans.exportedSpans.isEmpty }
        task.cancel()
        await task.value

        // Then it still arrived, and the bridge never drove collection itself
        #expect(delivered)
        #expect(exporters.spans.exportedSpans.map(\.name) == ["MXMetricPayload"])
        #expect(collector.startCollectingCallCount == 0)
        #expect(collector.stopCollectingCallCount == 0)
    }

    @Test("Metrics and diagnostics simulated while running are both consumed") func consumesBothStreams() async throws {
        let exporters = try await ExporterHarness.make()
        defer { exporters.sut.cleanUp() }
        let collector = MockMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: exporters.telemetry)
        let task = Task { await bridge.run() }

        collector.simulate(diagnostic: MetricKitFixtures.diagnostic(hangs: [.init(duration: 6)]))
        collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        let delivered = await flushing(exporters.telemetry) {
            !exporters.spans.exportedSpans.isEmpty && exporters.logs.exportedRecords
                .contains { $0.eventName == "app.hang" }
        }
        task.cancel()
        await task.value

        #expect(delivered)
        #expect(collector.startCollectingCallCount == 0)
        #expect(collector.stopCollectingCallCount == 0)
    }

    @Test("run() keeps consuming the diagnostic stream after the metric stream finished, and returns when both end")
    func runEndsWhenBothStreamsFinish() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let bridge = harness.bridge
        let task = Task { await bridge.run() }

        // When only the metric stream ends and a diagnostic follows
        harness.collector.finishMetrics()
        harness.collector.simulate(diagnostic: MetricKitFixtures.diagnostic(hangs: [.init(duration: 8)]))
        let delivered = await flushing(harness.exporters.telemetry) {
            harness.logs.exportedRecords.contains { $0.eventName == "app.hang" }
        }

        // Then the diagnostic was still consumed, and ending the last stream lets run() return
        #expect(delivered)
        harness.collector.finishDiagnostics()
        let returned = await completes { await task.value }
        #expect(returned)
    }

    @Test("A second run() returns immediately and does not consume") func secondRunReturnsImmediately() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let bridge = harness.bridge
        let first = Task { await bridge.run() }
        // Given the first run() is consuming: a summary goes through before the second call, so the
        // two calls cannot race for the claim.
        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        let consuming = await flushing(harness.exporters.telemetry) { harness.spans.exportedSpans.count == 1 }

        // When run() is called again
        let returned = await completes { await bridge.run() }
        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        let delivered = await flushing(harness.exporters.telemetry) { harness.spans.exportedSpans.count == 2 }
        first.cancel()
        await first.value

        // Then it came back at once, and each summary was exported exactly once, by the first run
        #expect(consuming)
        #expect(returned)
        #expect(delivered)
        #expect(harness.spans.exportedSpans.count == 2)
    }

    @Test("run() never starts or stops collection") func neverDrivesCollection() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        await harness.drain()

        #expect(harness.collector.startCollectingCallCount == 0)
        #expect(harness.collector.stopCollectingCallCount == 0)
    }
}
