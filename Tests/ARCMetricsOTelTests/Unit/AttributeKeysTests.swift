import ARCMetrics
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("AttributeKeys", .tags(.integration, .critical), .serialized,
       .timeLimit(.minutes(1))) struct AttributeKeysTests {
    /// Every key the package itself puts on spans, log events and session events.
    private static let recordKeys: Set = ["session.id", "session.previous_id", "error.type",
                                          // M3: crash and hang diagnostics, lifecycle state
                                          "exception.type", "exception.signal", "exception.termination_reason",
                                          "app.hang.duration_s", "ios.app.state",
                                          // M3: the MXMetricPayload span
                                          "metrickit.memory.peak_memory_usage",
                                          "metrickit.memory.suspended_memory_average",
                                          "metrickit.cpu.cpu_time", "metrickit.gpu.time",
                                          "metrickit.app_time.foreground_time", "metrickit.app_time.background_time",
                                          "metrickit.network_transfer.cellular_download",
                                          "metrickit.network_transfer.cellular_upload",
                                          "metrickit.network_transfer.wifi_download",
                                          "metrickit.network_transfer.wifi_upload",
                                          "metrickit.diskio.logical_write_count",
                                          "metrickit.app_responsiveness.hang_time_total_s",
                                          "metrickit.app_launch.time_to_first_draw_average_s",
                                          "metrickit.animation.hitch_time_ratio_ms_per_s",
                                          "metrickit.animation.scroll_hitch_time_ratio_ms_per_s"]

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

        // M3 producers: a fully populated metric payload, a full crash, a hang, and a lifecycle state
        let collector = ScriptedMetricsCollector()
        let bridge = MetricKitBridge(collector: collector, telemetry: sut.telemetry)
        collector.simulate(metric: MetricKitFixtures.fullMetricSummary())
        collector.simulate(diagnostic: MetricKitFixtures.diagnostic(crashes: [MetricKitFixtures.crash()],
                                                                    hangs: [.init(duration: 3)]))
        collector.finish()
        await bridge.run()
        let lifecycle = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: sut.telemetry, source: lifecycle)
        lifecycle.send(.foreground)
        lifecycle.finish()
        await observer.run()
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
