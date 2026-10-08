import Foundation
import OpenTelemetrySdk
import PersistenceExporter
import Testing
@testable import ARCMetricsOTel

@Suite("Telemetry lifecycle", .tags(.integration), .timeLimit(.minutes(1))) struct TelemetryLifecycleTests {
    private struct Harness {
        let sut: IntegrationSUT
        let spans: RecordingSpanExporter
        let logs: RecordingLogExporter
    }

    private func makeSUT(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1)) async throws
    -> Harness {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(settings: settings,
                                                   exporters: ExporterOverride(spans: spans, logs: logs))
        return Harness(sut: sut, spans: spans, logs: logs)
    }

    @Test("Enabling again while the pipeline exists keeps it and exports each span once")
    func updateEnabledKeepsPipeline() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        harness.sut.recordSpan(id: 1, name: "kept")

        await harness.sut.telemetry.update(TelemetrySettings(isEnabled: true, sampleRate: 1))
        await harness.sut.telemetry.flush()

        #expect(await harness.sut.telemetry.isActive)
        #expect(harness.spans.exportedSpans.map(\.name) == ["kept"])
    }

    @Test("Enabling after shutdown does not rebuild the pipeline") func updateAfterShutdownStaysShut() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        await harness.sut.telemetry.shutdown()

        await harness.sut.telemetry.update(TelemetrySettings(isEnabled: true, sampleRate: 1))
        harness.sut.recordSpan(id: 1, name: "late")
        await harness.sut.telemetry.flush()

        #expect(await !harness.sut.telemetry.isActive)
        #expect(harness.spans.exportedSpans.isEmpty)
    }

    @Test("A second shutdown does nothing") func secondShutdownIsNoOp() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        await harness.sut.telemetry.shutdown()
        let shutdownsAfterFirst = harness.spans.shutdownCalls
        #expect(shutdownsAfterFirst >= 1)

        await harness.sut.telemetry.shutdown()

        #expect(harness.spans.shutdownCalls == shutdownsAfterFirst)
    }

    @Test("Ending a span that was never started is ignored") func endUnknownSpan() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.sut.telemetry.endSpan(id: 404, errorType: "boom", attributes: [:])
        harness.sut.recordSpan(id: 1, name: "real")
        await harness.sut.telemetry.flush()

        #expect(harness.spans.exportedSpans.map(\.name) == ["real"])
    }

    @Test("A span ended with an error type is exported as failed, tagged error.type") func failedSpan() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.sut.telemetry.startSpan(id: 1, name: "request", parentID: nil, attributes: [:])
        harness.sut.telemetry.endSpan(id: 1, errorType: "timeout", attributes: [:])
        await harness.sut.telemetry.flush()

        let span = try #require(harness.spans.exportedSpans.first)
        #expect(span.status == .error(description: "timeout"))
        #expect(span.attributes["error.type"]?.description == "timeout")
    }

    @Test("When the actor is released with commands still queued, the consumer ends and the queue closes")
    func consumerEndsWhenActorIsReleased() async throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s"],
                                                           exporters: nil,
                                                           storageRoot: scratch.root)
        var telemetry: OTelTelemetry? = try await OTelBootstrap.configure(TestConfiguration.make(settings: .disabled),
                                                                          dependencies: dependencies)
        let ingress = try #require(telemetry?.ingress)
        telemetry = nil

        var accepted = true
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while accepted, ContinuousClock.now < deadline {
            accepted = ingress.send(.resetSession(Date()))
            await Task.yield()
        }

        #expect(!accepted)
    }

    @Test("Without a storage root the buffer lives in Application Support") func defaultStorageRoot() async throws {
        let defaultRoot = StorageLocation.defaultRoot()
        let existed = FileManager.default.fileExists(atPath: defaultRoot.path)
        defer {
            if !existed {
                try? FileManager.default.removeItem(at: defaultRoot)
            }
        }
        let spans = RecordingSpanExporter()
        let configuration = try TestConfiguration.make(settings: TelemetrySettings(isEnabled: true, sampleRate: 1))
        var dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s"],
                                                           exporters: ExporterOverride(spans: spans,
                                                                                       logs: RecordingLogExporter()),
                                                           storageRoot: defaultRoot)
        dependencies.storageRoot = nil

        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)

        #expect(await telemetry.isActive)
        #expect(FileManager.default.fileExists(atPath: defaultRoot.appending(path: "traces").path))
    }

    @Test("Every configured header reaches the collector") func headersArriveOnTheWire() async throws {
        let testID = UUID().uuidString
        let scratch = TemporaryDirectory()
        StubServer.shared.register(testID: testID, behavior: .ok)
        defer {
            StubServer.shared.unregister(testID: testID)
            scratch.remove()
        }
        let configuration = try TestConfiguration.make(headers: [StubServer.testIDHeader: testID, "x-zeta": "3",
                                                                 "x-alpha": "1", "x-mid": "2"],
                                                       settings: TelemetrySettings(isEnabled: true, sampleRate: 1))
        let dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s"],
                                                           exporters: nil,
                                                           storageRoot: scratch.root)
        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)

        telemetry.startSpan(id: 1, name: "headers", parentID: nil, attributes: [:])
        telemetry.endSpan(id: 1, errorType: nil, attributes: [:])
        await telemetry.flush()

        let request = try #require(StubServer.shared.requests(for: testID).first { $0.path.hasSuffix("/v1/traces") })
        #expect(request.headers["x-alpha"] == "1")
        #expect(request.headers["x-mid"] == "2")
        #expect(request.headers["x-zeta"] == "3")
    }

    @Test("The disk buffer exports on its own timer while telemetry is enabled")
    func bufferExportsWithoutFlush() async throws {
        let spans = RecordingSpanExporter()
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        let configuration = try TestConfiguration.make(settings: TelemetrySettings(isEnabled: true, sampleRate: 1))
        var dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s"],
                                                           exporters: ExporterOverride(spans: spans,
                                                                                       logs: RecordingLogExporter()),
                                                           storageRoot: scratch.root)
        dependencies.scheduleDelay = 0.05
        dependencies.performancePreset = PersistencePerformancePreset(maxFileSize: 64000,
                                                                      maxDirectorySize: 1_000_000,
                                                                      maxFileAgeForWrite: 0.01,
                                                                      minFileAgeForRead: 0.01,
                                                                      maxFileAgeForRead: 3600,
                                                                      maxObjectsInFile: 100,
                                                                      maxObjectSize: 64000,
                                                                      synchronousWrite: true,
                                                                      initialExportDelay: 0.05,
                                                                      defaultExportDelay: 0.05,
                                                                      minExportDelay: 0.05,
                                                                      maxExportDelay: 0.05,
                                                                      exportDelayChangeRate: 0.1)
        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)

        telemetry.startSpan(id: 1, name: "automatic", parentID: nil, attributes: [:])
        telemetry.endSpan(id: 1, errorType: nil, attributes: [:])
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while spans.exportedSpans.isEmpty, ContinuousClock.now < deadline {
            await Task.yield()
        }

        #expect(spans.exportedSpans.map(\.name) == ["automatic"])
    }

    @Test("Headers from the process environment are never sent") func environmentHeadersAreIgnored() async throws {
        setenv("OTEL_EXPORTER_OTLP_HEADERS", "x-injected=evil", 1)
        // Limitation: upstream caches the environment in a process-wide `static let`, so this can
        // still pass after a regression if another test read it first. `headersArriveOnTheWire`
        // is the real guard that the configured headers are exactly what is sent.
        defer { unsetenv("OTEL_EXPORTER_OTLP_HEADERS") }
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }

        sut.recordSpan(id: 1, name: "env")
        sut.recordEvent("env-event")
        await sut.telemetry.flush()

        #expect(sut.deliveries.count >= 2)
        for request in sut.requests {
            #expect(request.headers["x-test-id"] == sut.testID)
            #expect(!request.headers.keys.contains { $0.hasPrefix("x-injected") })
        }
    }

    @Test("Concurrent shutdown calls all return only after the exporters are shut down")
    func concurrentShutdownsWaitForTheFirst() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        harness.sut.recordSpan(id: 1, name: "last")

        let shutDownOnReturn = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for _ in 0 ..< 2 {
                group.addTask {
                    await harness.sut.telemetry.shutdown()
                    return harness.spans.shutdownCalls >= 1 && harness.logs.shutdownCalls >= 1
                }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        #expect(shutDownOnReturn == [true, true])
        #expect(harness.spans.exportedSpans.map(\.name) == ["last"])
    }

    @Test("A dump of live telemetry never contains a header value") func dumpOfTelemetryIsRedacted() async throws {
        let secret = "Bearer s3cr3t-token"
        let testID = UUID().uuidString
        let scratch = TemporaryDirectory()
        StubServer.shared.register(testID: testID, behavior: .ok)
        defer {
            StubServer.shared.unregister(testID: testID)
            scratch.remove()
        }
        let configuration = try TestConfiguration.make(headers: [StubServer.testIDHeader: testID,
                                                                 "Authorization": secret],
                                                       settings: TelemetrySettings(isEnabled: true, sampleRate: 1))
        let dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["s"],
                                                           exporters: nil,
                                                           storageRoot: scratch.root)
        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)
        #expect(await telemetry.isActive)

        var dumped = ""
        dump(telemetry, to: &dumped)

        #expect(dumped.contains(TestConfiguration.serviceName))
        #expect(!dumped.contains(secret))
        #expect(!dumped.contains(testID))
    }

    @Test("A race of two unordered updates cannot let stale buffered data out")
    func concurrentUpdateRaceDiscardsStaleData() async throws {
        let enabled = TelemetrySettings(isEnabled: true, sampleRate: 1)
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "stale")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)

        // Both gate flips land before the actor work of either update has run.
        sut.telemetry.gate.update(.disabled)
        sut.telemetry.gate.update(enabled)
        await sut.telemetry.update(enabled)
        sut.setBehavior(.ok)
        sut.recordSpan(id: 2, name: "fresh")
        await sut.telemetry.flush()

        let names = sut.deliveredTraces.spans.map(\.name)
        #expect(names.contains("fresh"))
        #expect(!names.contains("stale"))
    }
}
