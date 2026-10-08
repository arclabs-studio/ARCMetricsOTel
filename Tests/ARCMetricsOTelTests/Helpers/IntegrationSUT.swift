import Foundation
import OpenTelemetryApi
import PersistenceExporter
import Testing
@testable import ARCMetricsOTel

/// A running `OTelTelemetry` wired to a stub transport and a scratch directory.
struct IntegrationSUT {
    let telemetry: OTelTelemetry
    let testID: String
    let scratch: TemporaryDirectory
    let clock: FakeClock
    let store: InMemorySessionStore

    var root: URL {
        scratch.root
    }

    var tracesDirectory: URL {
        root.appending(path: "traces", directoryHint: .isDirectory)
    }

    var logsDirectory: URL {
        root.appending(path: "logs", directoryHint: .isDirectory)
    }

    /// Every request the stub received, in arrival order.
    var requests: [StubServer.Request] {
        StubServer.shared.requests(for: testID)
    }

    /// Requests the stub answered `200`.
    var deliveries: [StubServer.Request] {
        requests.filter(\.succeeded)
    }

    /// Spans decoded from the successful `v1/traces` deliveries.
    var deliveredTraces: OTLPDecoder.Traces {
        var merged = OTLPDecoder.Traces()
        for request in deliveries where request.path.hasSuffix("/v1/traces") {
            let decoded = OTLPDecoder.traces(from: request.body)
            merged.spans += decoded.spans
            merged.resourceAttributes.merge(decoded.resourceAttributes) { _, new in new }
        }
        return merged
    }

    /// Log records decoded from the successful `v1/logs` deliveries.
    var deliveredLogs: OTLPDecoder.Logs {
        var merged = OTLPDecoder.Logs()
        for request in deliveries where request.path.hasSuffix("/v1/logs") {
            let decoded = OTLPDecoder.logs(from: request.body)
            merged.records += decoded.records
            merged.resourceAttributes.merge(decoded.resourceAttributes) { _, new in new }
        }
        return merged
    }

    func setBehavior(_ behavior: StubServer.Behavior) {
        StubServer.shared.setBehavior(behavior, for: testID)
    }

    func cleanUp() {
        StubServer.shared.unregister(testID: testID)
        scratch.remove()
    }

    // MARK: Recording shortcuts

    /// Starts and ends a span, optionally under `parentID`.
    func recordSpan(id: UInt64, name: String, parentID: UInt64? = nil) {
        telemetry.startSpan(id: id, name: name, parentID: parentID, attributes: [:])
        telemetry.endSpan(id: id, errorType: nil, attributes: [:])
    }

    func recordEvent(_ name: String) {
        telemetry.emitEvent(name: name, attributes: [:], severity: .info)
    }

    // MARK: Factory

    /// Builds dependencies that keep the whole pipeline inside the test.
    ///
    /// Persistence writes synchronously and exports only on an explicit flush (the timers are set
    /// to an hour), so a test controls exactly when anything leaves the device.
    static func makeDependencies(clock: FakeClock,
                                 store: InMemorySessionStore,
                                 sessionIDs: [String],
                                 exporters: ExporterOverride?,
                                 storageRoot: URL) -> OTelDependencies {
        let sequence = SessionIDSequence(sessionIDs)
        var dependencies = OTelDependencies()
        dependencies.clock = clock
        dependencies.makeSessionID = { sequence.next() }
        dependencies.urlSession = StubURLProtocol.makeSession()
        dependencies.storageRoot = storageRoot
        dependencies.sessionStore = store
        dependencies.environment = [:]
        dependencies.operatingSystemVersion = OperatingSystemVersion(majorVersion: 18, minorVersion: 4, patchVersion: 1)
        dependencies.machine = { "iPhone17,1" }
        dependencies.exporters = exporters
        dependencies.compression = .none
        dependencies.performancePreset = PersistencePerformancePreset(maxFileSize: 64000,
                                                                      maxDirectorySize: 1_000_000,
                                                                      maxFileAgeForWrite: 0.01,
                                                                      minFileAgeForRead: 0,
                                                                      maxFileAgeForRead: 3600,
                                                                      maxObjectsInFile: 100,
                                                                      maxObjectSize: 64000,
                                                                      synchronousWrite: true,
                                                                      initialExportDelay: 3600,
                                                                      defaultExportDelay: 3600,
                                                                      minExportDelay: 3600,
                                                                      maxExportDelay: 3600,
                                                                      exportDelayChangeRate: 0.1)
        dependencies.scheduleDelay = 3600
        return dependencies
    }

    /// Configures telemetry against the stub transport.
    static func makeSUT(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1),
                        behavior: StubServer.Behavior = .ok,
                        sessionIDs: [String] = ["session-1", "session-2", "session-3"],
                        store: InMemorySessionStore = InMemorySessionStore(),
                        exporters: ExporterOverride? = nil,
                        storageRoot: URL? = nil) async throws -> IntegrationSUT {
        let testID = UUID().uuidString
        let scratch = TemporaryDirectory()
        let clock = FakeClock()
        StubServer.shared.register(testID: testID, behavior: behavior)
        let configuration = try TestConfiguration.make(headers: [StubServer.testIDHeader: testID],
                                                       settings: settings)
        let dependencies = makeDependencies(clock: clock,
                                            store: store,
                                            sessionIDs: sessionIDs,
                                            exporters: exporters,
                                            storageRoot: storageRoot ?? scratch.root)
        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)
        return IntegrationSUT(telemetry: telemetry, testID: testID, scratch: scratch, clock: clock, store: store)
    }
}
