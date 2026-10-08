import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Acceptance: kill switch", .tags(.integration, .critical), .timeLimit(.minutes(1)))
struct KillSwitchAcceptanceTests {
    private let enabled = TelemetrySettings(isEnabled: true, sampleRate: 1)

    @Test("(a) Configured disabled: nothing is built, written or sent, until it is enabled")
    func disabledAtLaunchBuildsNothing() async throws {
        // Given telemetry configured while disabled
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled)
        defer { sut.cleanUp() }

        // When records are produced and flushed
        sut.recordSpan(id: 1, name: "while-disabled")
        sut.recordEvent("while-disabled-event")
        await sut.telemetry.flush()

        // Then no request was made, no directory exists and the pipeline was never built
        #expect(sut.requests.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sut.root.path))
        #expect(await sut.telemetry.isActive == false)

        // And once enabled, only what is recorded afterwards is delivered (the pipeline works at all)
        await sut.telemetry.update(enabled)
        sut.recordSpan(id: 2, name: "after-enable")
        await sut.telemetry.flush()
        #expect(sut.deliveredTraces.spans.map(\.name) == ["after-enable"])
        #expect(FileManager.default.fileExists(atPath: sut.tracesDirectory.path))
    }

    @Test("(b) Disabled after recording: nothing more is sent and the buffer holds no files")
    func disablingStopsExport() async throws {
        // Given a working pipeline that has already delivered a warm-up span
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "warm-up")
        await sut.telemetry.flush()
        let before = sut.requests.count
        #expect(sut.deliveredTraces.spans.map(\.name) == ["warm-up"])

        // When a record is made and the kill switch is thrown before the flush
        sut.recordSpan(id: 2, name: "recorded-then-disabled")
        sut.recordEvent("event-then-disabled")
        await sut.telemetry.update(.disabled)
        await sut.telemetry.flush()

        // Then the stub saw nothing new and neither buffer directory holds a file
        #expect(sut.requests.count == before)
        #expect(sut.deliveredTraces.spans.map(\.name) == ["warm-up"])
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        #expect(TemporaryDirectory.files(in: sut.logsDirectory).isEmpty)
        #expect(FileManager.default.fileExists(atPath: sut.tracesDirectory.path))
    }

    @Test("(b) Disabled while a batch waits on disk: the buffer is drained, not sent")
    func disablingDrainsBufferedBatches() async throws {
        // Given a span stranded in the disk buffer because the network is down
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "stranded")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        let attemptsBefore = sut.requests.count

        // When telemetry is disabled and the network comes back
        await sut.telemetry.update(.disabled)
        sut.setBehavior(.ok)
        await sut.telemetry.flush()

        // Then the persistence flush discards the batch instead of sending it
        #expect(sut.requests.count == attemptsBefore)
        #expect(sut.deliveries.isEmpty)
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
    }

    @Test("(c) Positive control: enabled telemetry delivers decodable traces and logs")
    func enabledDelivers() async throws {
        // Given enabled telemetry
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }

        // When a span and an event are recorded and flushed
        sut.recordSpan(id: 1, name: "load-restaurants")
        sut.recordEvent("restaurant-saved")
        await sut.telemetry.flush()

        // Then both signals reach their OTLP paths with the test header
        let paths = Set(sut.deliveries.map(\.path))
        #expect(paths == ["/v1/traces", "/v1/logs"])
        #expect(sut.deliveries.allSatisfy { $0.headers[StubServer.testIDHeader] == sut.testID })

        // And the payloads carry the span, the log, the Resource and the session id
        let traces = sut.deliveredTraces
        let span = try #require(traces.spans.first)
        #expect(traces.spans.map(\.name) == ["load-restaurants"])
        #expect(span.attributes[AttributeKeys.sessionID] == "session-1")
        #expect(traces.resourceAttributes[AttributeKeys.serviceName] == TestConfiguration.serviceName)
        #expect(traces.resourceAttributes[AttributeKeys.sessionID] == nil)

        let logs = sut.deliveredLogs
        let record = try #require(logs.records.first { $0.eventName == "restaurant-saved" })
        #expect(record.attributes[AttributeKeys.sessionID] == "session-1")
        #expect(record.severityNumber == 9)
        #expect(logs.resourceAttributes[AttributeKeys.serviceName] == TestConfiguration.serviceName)
    }

    @Test("Enabling a dormant pipeline builds it and starts delivering") func enablingBuildsPipeline() async throws {
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled)
        defer { sut.cleanUp() }

        await sut.telemetry.update(enabled)
        sut.recordSpan(id: 1, name: "first")
        await sut.telemetry.flush()

        #expect(await sut.telemetry.isActive)
        #expect(sut.deliveredTraces.spans.map(\.name) == ["first"])
    }

    @Test("(b) Disabled then re-enabled: data buffered before the kill switch is never delivered")
    func disableDiscardsEvenAfterReEnable() async throws {
        // Given a span stranded in the disk buffer because the network is down
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "stale")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)

        // When telemetry is disabled, enabled again, and the network returns
        await sut.telemetry.update(.disabled)
        await sut.telemetry.update(TelemetrySettings(isEnabled: true, sampleRate: 1))
        sut.setBehavior(.ok)
        sut.recordSpan(id: 2, name: "fresh")
        await sut.telemetry.flush()

        // Then only the span recorded after re-enabling arrives
        let names = sut.deliveredTraces.spans.map(\.name)
        #expect(names.contains("fresh"))
        #expect(!names.contains("stale"))
    }
}
