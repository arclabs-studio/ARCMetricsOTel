import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Concurrent flush", .tags(.integration, .critical), .serialized,
       .timeLimit(.minutes(1))) struct ConcurrentFlushTests {
    @Test("More simultaneous flushes than CPUs all complete and deliver their spans")
    func manyConcurrentFlushesDoNotDeadlock() async throws {
        let count = ProcessInfo.processInfo.activeProcessorCount * 2 + 2
        var suts: [IntegrationSUT] = []
        for index in 0 ..< count {
            let sut = try await IntegrationSUT.makeSUT()
            sut.recordSpan(id: UInt64(index + 1), name: "span-\(index)")
            suts.append(sut)
        }
        defer { suts.forEach { $0.cleanUp() } }

        let completed = await withTaskGroup(of: Void.self, returning: Int.self) { group in
            for sut in suts {
                group.addTask { await sut.telemetry.flush() }
            }
            var finished = 0
            for await _ in group {
                finished += 1
            }
            return finished
        }

        #expect(completed == count)
        for (index, sut) in suts.enumerated() {
            #expect(sut.deliveredTraces.spans.count == 1, "instance \(index) delivered no span")
        }
    }
}
