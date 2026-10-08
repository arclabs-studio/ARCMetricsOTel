import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("TelemetryIngress", .tags(.unit), .timeLimit(.minutes(1))) struct TelemetryIngressTests {
    private let dates = (0 ..< 3).map { Date(timeIntervalSince1970: 1000 + Double($0)) }

    /// The `resetSession` timestamps delivered until the stream ends, or none if it never ends.
    private func drain(_ ingress: TelemetryIngress) async -> [Date] {
        var received: [Date] = []
        for await command in ingress.stream {
            if case let .resetSession(date) = command {
                received.append(date)
            }
        }
        return received
    }

    @Test("Commands come out in the order they went in") func fifo() async {
        let ingress = TelemetryIngress()

        let accepted = dates.map { ingress.send(.resetSession($0)) }
        ingress.finish()

        #expect(accepted == [true, true, true])
        #expect(await drain(ingress) == dates)
    }

    @Test("A full queue drops the newest command and keeps the oldest") func boundedKeepsOldest() async {
        let ingress = TelemetryIngress(capacity: 2)

        let accepted = dates.map { ingress.send(.resetSession($0)) }
        ingress.finish()

        #expect(accepted == [true, true, false])
        #expect(await drain(ingress) == Array(dates.prefix(2)))
    }

    @Test("Nothing is accepted after finish") func finishedRejects() {
        let ingress = TelemetryIngress()

        #expect(ingress.send(.resetSession(dates[0])) == true)
        ingress.finish()

        #expect(ingress.send(.resetSession(dates[1])) == false)
    }
}
