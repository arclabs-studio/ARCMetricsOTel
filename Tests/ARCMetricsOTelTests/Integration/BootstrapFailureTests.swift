import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Bootstrap failures", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct BootstrapFailureTests {
    private func configure(endpoint: String,
                           settings: TelemetrySettings,
                           storageRoot: URL,
                           testID: String = UUID().uuidString) async throws -> OTelTelemetry {
        let configuration = try TestConfiguration.make(endpoint: endpoint,
                                                       headers: [StubServer.testIDHeader: testID],
                                                       settings: settings)
        let dependencies = IntegrationSUT.makeDependencies(clock: FakeClock(),
                                                           store: InMemorySessionStore(),
                                                           sessionIDs: ["session-1"],
                                                           exporters: nil,
                                                           storageRoot: storageRoot)
        return try await OTelBootstrap.configure(configuration, dependencies: dependencies)
    }

    private let enabled = TelemetrySettings(isEnabled: true, sampleRate: 1)

    @Test("A plain http endpoint on a public host is rejected, and nothing is created")
    func insecureEndpointThrows() async throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }

        await #expect(throws: OTelBootstrapError.insecureEndpoint) {
            try await configure(endpoint: "http://example.com", settings: enabled, storageRoot: scratch.root)
        }
        #expect(!FileManager.default.fileExists(atPath: scratch.root.path))
    }

    @Test("An endpoint that is not http(s) is rejected") func invalidEndpointThrows() async throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }

        await #expect(throws: OTelBootstrapError.invalidEndpoint) {
            try await configure(endpoint: "ftp://example.com", settings: enabled, storageRoot: scratch.root)
        }
    }

    @Test("A storage root that is a regular file makes enabled telemetry fail with storageUnavailable")
    func unusableStorageThrows() async throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        try scratch.createParent()
        try Data("occupied".utf8).write(to: scratch.root)

        await #expect(throws: OTelBootstrapError.storageUnavailable) {
            try await configure(endpoint: "https://otlp.example.test", settings: enabled, storageRoot: scratch.root)
        }
    }

    @Test("Enabling a dormant telemetry whose storage is unusable leaves it dormant and sends nothing")
    func dormantStaysDormant() async throws {
        let scratch = TemporaryDirectory()
        defer { scratch.remove() }
        try scratch.createParent()
        try Data("occupied".utf8).write(to: scratch.root)
        let testID = UUID().uuidString
        StubServer.shared.register(testID: testID, behavior: .ok)
        defer { StubServer.shared.unregister(testID: testID) }

        // Given telemetry configured disabled, so the bad storage is never touched
        let telemetry = try await configure(endpoint: "https://otlp.example.test",
                                            settings: .disabled,
                                            storageRoot: scratch.root,
                                            testID: testID)
        #expect(await telemetry.isActive == false)

        // When it is enabled
        await telemetry.update(enabled)
        telemetry.emitEvent(name: "ignored", attributes: [:], severity: .info)
        await telemetry.flush()

        // Then it stays dormant and nothing reaches the network
        #expect(await telemetry.isActive == false)
        #expect(StubServer.shared.requests(for: testID).isEmpty)
    }

    @Test("Telemetry configured enabled with good storage is active") func enabledIsActive() async throws {
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }

        #expect(await sut.telemetry.isActive)
        #expect(FileManager.default.fileExists(atPath: sut.tracesDirectory.path))
        #expect(FileManager.default.fileExists(atPath: sut.logsDirectory.path))
    }
}
