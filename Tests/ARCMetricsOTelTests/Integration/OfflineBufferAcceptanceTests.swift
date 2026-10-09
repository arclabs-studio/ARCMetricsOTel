import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Acceptance: offline disk buffer", .tags(.integration, .critical), .serialized, .timeLimit(.minutes(1)))
struct OfflineBufferAcceptanceTests {
    @Test("A span recorded offline is buffered on disk, then delivered exactly once when the network returns")
    func bufferedThenDeliveredOnce() async throws {
        // Given a device without connectivity
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }

        // When a span is recorded and flushed
        sut.recordSpan(id: 1, name: "offline-span")
        await sut.telemetry.flush()

        // Then at least one file waits in traces/ and nothing was delivered
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        #expect(sut.deliveries.isEmpty)

        // When connectivity returns and the buffer is flushed (past the minimum file age)
        sut.setBehavior(.ok)
        await sut.telemetry.flush()

        // Then the span arrives exactly once and the buffer is empty
        let delivered = sut.deliveredTraces.spans.filter { $0.name == "offline-span" }
        #expect(delivered.count == 1)
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)

        // And a third flush does not resend it
        await sut.telemetry.flush()
        #expect(sut.deliveredTraces.spans.filter { $0.name == "offline-span" }.count == 1)
    }

    @Test("Log events are buffered offline and delivered once as well") func logsBufferedThenDelivered() async throws {
        let sut = try await IntegrationSUT.makeSUT(behavior: .offline)
        defer { sut.cleanUp() }

        sut.recordEvent("offline-event")
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.logsDirectory).isEmpty)
        #expect(sut.deliveries.isEmpty)

        sut.setBehavior(.ok)
        await sut.telemetry.flush()

        #expect(sut.deliveredLogs.records.filter { $0.eventName == "offline-event" }.count == 1)
        #expect(TemporaryDirectory.files(in: sut.logsDirectory).isEmpty)
    }
}
