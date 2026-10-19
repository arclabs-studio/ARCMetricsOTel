import Testing
@testable import ARCMetricsOTel

@Suite("OTelBootstrap", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct OTelBootstrapTests {
    @Test("The public configure(_:) starts dormant telemetry without building anything")
    func publicConfigureDormant() async throws {
        let configuration = try TestConfiguration.make(settings: .disabled)

        let telemetry = try await OTelBootstrap.configure(configuration)

        #expect(await !telemetry.isActive)
    }
}
