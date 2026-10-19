import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Acceptance: kill switch", .tags(.integration, .critical), .serialized, .timeLimit(.minutes(1)))
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

    // MARK: A buffer left by an earlier launch

    /// An earlier launch that strands one span on disk: the network is down when it shuts down.
    private func makeEarlierLaunch(spanName: String) async throws -> IntegrationSUT {
        let earlier = try await IntegrationSUT.makeSUT(behavior: .offline)
        earlier.recordSpan(id: 1, name: spanName)
        await earlier.telemetry.flush()
        await earlier.telemetry.shutdown()
        return earlier
    }

    @Test("(b) Disabled at launch, then explicitly disabled: a buffer from an earlier launch is never delivered")
    func killSwitchDiscardsBufferOfEarlierLaunch() async throws {
        // Given a span left on disk by an earlier launch
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        defer { earlier.cleanUp() }
        #expect(!TemporaryDirectory.files(in: earlier.tracesDirectory).isEmpty)

        // And a new launch on the same storage root that starts disabled
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }

        // When the kill switch is thrown explicitly, then telemetry is enabled with the network back
        await sut.telemetry.update(.disabled)
        await sut.telemetry.update(enabled)
        await sut.telemetry.flush()

        // Then nothing was sent and the buffer holds no files
        #expect(sut.requests.isEmpty)
        #expect(TemporaryDirectory.files(in: earlier.tracesDirectory).isEmpty)
        #expect(TemporaryDirectory.files(in: earlier.logsDirectory).isEmpty)
    }

    @Test("(b) Positive control: without the kill switch, a buffer from an earlier launch is delivered once")
    func bufferOfEarlierLaunchIsDeliveredWithoutKillSwitch() async throws {
        // Given a span left on disk by an earlier launch
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        defer { earlier.cleanUp() }

        // And a new launch that starts disabled, with a working network
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }

        // When it is only enabled, never explicitly disabled
        await sut.telemetry.update(enabled)
        await sut.telemetry.flush()

        // Then the old span is delivered exactly once
        #expect(sut.deliveredTraces.spans.map(\.name) == ["left-by-earlier-launch"])
    }

    @Test("(b) Disabled at launch and explicitly disabled, never re-enabled: the old buffer is removed from disk")
    func killSwitchRemovesBufferWithoutReEnabling() async throws {
        // Given a span left on disk by an earlier launch
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        defer { earlier.cleanUp() }
        #expect(!TemporaryDirectory.files(in: earlier.tracesDirectory).isEmpty)
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }

        // When the kill switch is thrown on the dormant telemetry
        await sut.telemetry.update(.disabled)

        // Then the files are gone, and nothing was sent
        #expect(TemporaryDirectory.files(in: earlier.tracesDirectory).isEmpty)
        #expect(TemporaryDirectory.files(in: earlier.logsDirectory).isEmpty)
        #expect(sut.requests.isEmpty)
    }

    @Test("(b) Merely starting disabled leaves an earlier launch's buffer untouched")
    func startingDisabledDoesNotPurge() async throws {
        // Given a span left on disk by an earlier launch
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        defer { earlier.cleanUp() }
        let filesBefore = TemporaryDirectory.files(in: earlier.tracesDirectory).count
        #expect(filesBefore > 0)

        // When a new launch starts disabled and records something
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }
        sut.recordSpan(id: 2, name: "while-disabled")
        await sut.telemetry.flush()

        // Then the buffer is as the earlier launch left it
        #expect(TemporaryDirectory.files(in: earlier.tracesDirectory).count == filesBefore)
    }

    /// Makes the earlier launch's `traces` directory immutable, so that removing it fails.
    /// The returned closure undoes it; call it before the scratch directory is deleted.
    private func lockTraces(of earlier: IntegrationSUT) throws -> @Sendable () -> Void {
        let traces = earlier.tracesDirectory.path
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: traces)
        return { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: traces) }
    }

    @Test("(b) Positive control: with an undeletable buffer and no kill switch, the old buffer is still delivered")
    func lockedBufferIsDeliveredWithoutKillSwitch() async throws {
        // Given a span left on disk by an earlier launch, in a directory that cannot be removed
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        let unlock = try lockTraces(of: earlier)
        defer {
            unlock()
            earlier.cleanUp()
        }
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }

        // When telemetry is only enabled
        await sut.telemetry.update(enabled)
        await sut.telemetry.flush()

        // Then the old span is delivered, so an empty request list in the next test means a closed gate
        #expect(sut.deliveredTraces.spans.map(\.name).contains("left-by-earlier-launch"))
    }

    @Test("(b) A buffer that cannot be removed keeps exports closed, even after telemetry is enabled again")
    func failedPurgeKeepsExportsClosed() async throws {
        // Given a span left on disk by an earlier launch, in a directory that cannot be removed
        let earlier = try await makeEarlierLaunch(spanName: "left-by-earlier-launch")
        let unlock = try lockTraces(of: earlier)
        defer {
            unlock()
            earlier.cleanUp()
        }
        let sut = try await IntegrationSUT.makeSUT(settings: .disabled, storageRoot: earlier.root)
        defer { sut.cleanUp() }

        // When the kill switch is thrown (the purge fails), then telemetry is enabled and flushed
        await sut.telemetry.update(.disabled)
        await sut.telemetry.update(enabled)
        sut.recordSpan(id: 2, name: "after-failed-purge")
        await sut.telemetry.flush()

        // Then no request left the device
        #expect(sut.requests.isEmpty)
    }

    // MARK: A live pipeline

    private func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    @Test("(b) Disabled with a live pipeline: files the upstream flush leaves behind are removed, directories stay")
    func liveDiscardLeavesNoFiles() async throws {
        // Given a live pipeline with a span on disk, and leftovers upstream's flush does not drain
        // (non-numeric names, which its reader skips)
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "stranded")
        await sut.telemetry.flush()
        let buffered = try #require(TemporaryDirectory.files(in: sut.tracesDirectory).first)
        let batch = try Data(contentsOf: buffered)
        try batch.write(to: sut.tracesDirectory.appending(path: "leftover-batch"))
        try batch.write(to: sut.logsDirectory.appending(path: "leftover-batch"))

        // When the kill switch is thrown
        await sut.telemetry.update(.disabled)

        // Then no regular file remains in the buffer, and both directories are still there
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        #expect(TemporaryDirectory.files(in: sut.logsDirectory).isEmpty)
        #expect(isDirectory(sut.tracesDirectory))
        #expect(isDirectory(sut.logsDirectory))

        // And enabling again with the network back sends nothing old
        await sut.telemetry.update(enabled)
        sut.setBehavior(.ok)
        await sut.telemetry.flush()
        #expect(sut.deliveredTraces.spans.isEmpty)
    }

    @Test("(b) Positive control: a live, undeletable buffer is delivered once the network is back and nothing was disabled")
    func liveLockedBufferIsDeliveredWithoutKillSwitch() async throws {
        // Given a live pipeline with a span on disk, in a directory that cannot be modified
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        sut.recordSpan(id: 1, name: "stranded")
        await sut.telemetry.flush()
        let unlock = try lockTraces(of: sut)
        defer {
            unlock()
            sut.cleanUp()
        }

        // When the network comes back and nothing is disabled
        sut.setBehavior(.ok)
        await sut.telemetry.flush()

        // Then the stranded span is delivered, so the next test's empty result means a closed gate
        #expect(sut.deliveredTraces.spans.map(\.name).contains("stranded"))
    }

    @Test("(b) A live buffer that cannot be removed keeps exports closed, even after telemetry is enabled again")
    func failedLiveDiscardKeepsExportsClosed() async throws {
        // Given a live pipeline with a span on disk, in a directory that cannot be modified
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        sut.recordSpan(id: 1, name: "stranded")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        let unlock = try lockTraces(of: sut)
        defer {
            unlock()
            sut.cleanUp()
        }

        // When the kill switch is thrown (the removal fails), then telemetry is enabled and flushed
        await sut.telemetry.update(.disabled)
        await sut.telemetry.update(enabled)
        sut.setBehavior(.ok)
        sut.recordSpan(id: 2, name: "after-failed-discard")
        await sut.telemetry.flush()

        // Then the stranded span was never sent
        #expect(sut.deliveredTraces.spans.isEmpty)
    }
}
