import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Acceptance: export status handling", .tags(.integration, .critical), .timeLimit(.minutes(1)))
struct ExportStatusAcceptanceTests {
    private func traceAttempts(_ sut: IntegrationSUT) -> Int {
        sut.requests.filter { $0.path.hasSuffix("/v1/traces") }.count
    }

    @Test("A batch the collector rejects with 401 is attempted once and then dropped from the buffer")
    func rejectedBatchIsDropped() async throws {
        let sut = try await IntegrationSUT.makeSUT(behavior: .status(401))
        defer { sut.cleanUp() }

        sut.recordSpan(id: 1, name: "rejected")
        await sut.telemetry.flush()

        #expect(traceAttempts(sut) == 1)
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)

        let attemptsBefore = sut.requests.count
        await sut.telemetry.flush()
        #expect(sut.requests.count == attemptsBefore)
    }

    @Test("A batch answered 503 stays on disk and is delivered once when the collector recovers")
    func unavailableBatchIsRetried() async throws {
        let sut = try await IntegrationSUT.makeSUT(behavior: .status(503))
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "retry-me")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        #expect(sut.deliveries.isEmpty)

        sut.setBehavior(.ok)
        await sut.telemetry.flush()

        #expect(sut.deliveredTraces.spans.filter { $0.name == "retry-me" }.count == 1)
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
    }
}
