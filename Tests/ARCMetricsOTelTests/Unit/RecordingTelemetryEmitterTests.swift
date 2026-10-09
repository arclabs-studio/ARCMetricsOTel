import ARCMetrics
import ARCMetricsOTelMocks
import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Recording telemetry emitter", .tags(.unit), .timeLimit(.minutes(1))) struct RecordingTelemetryEmitterTests {
    private func makeSUT() -> RecordingTelemetryEmitter {
        RecordingTelemetryEmitter()
    }

    @Test("A new emitter has recorded nothing") func startsEmpty() {
        #expect(makeSUT().events.isEmpty)
    }

    @Test("Each emitted event is recorded with every field, in order") func recordsInOrder() {
        let sut = makeSUT()
        let stamp = Date(timeIntervalSince1970: 1_800_000_123)

        sut.emitEvent("first", attributes: ["a": "x", "n": 2], severity: .warn, timestamp: stamp)
        sut.emitEvent("second", attributes: [:], severity: .fatal, timestamp: nil)

        #expect(sut.events.map(\.name) == ["first", "second"])
        #expect(sut.events.map(\.severity) == [.warn, .fatal])
        #expect(sut.events.map(\.timestamp) == [stamp, nil])
        #expect(sut.events.map(\.attributes) == [["a": "x", "n": 2], [:]])
    }

    @Test("Emitting from many tasks at once loses no event") func concurrentEmissionLosesNothing() async {
        let sut = makeSUT()

        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 100 {
                group.addTask {
                    sut.emitEvent("event.\(index)", attributes: [:], severity: .info, timestamp: nil)
                }
            }
        }

        #expect(sut.events.count == 100)
        #expect(Set(sut.events.map(\.name)).count == 100)
    }
}
