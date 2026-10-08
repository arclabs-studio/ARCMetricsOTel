import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("BlockingResult", .tags(.unit), .timeLimit(.minutes(1))) struct BlockingResultTests {
    private struct Failure: Error, Equatable {
        let code: Int
    }

    @Test("A resolved value is returned by wait()") func returnsValue() throws {
        let result = BlockingResult<Int>()

        result.resolve(.success(42))

        #expect(try result.wait(until: .distantFuture)?.get() == 42)
    }

    @Test("A resolved failure is returned by wait()") func returnsFailure() {
        let result = BlockingResult<Int>()

        result.resolve(.failure(Failure(code: 7)))

        #expect(throws: Failure(code: 7)) {
            try result.wait(until: .distantFuture)?.get()
        }
    }

    @Test("An unresolved result times out with nil at the deadline") func timesOut() {
        let result = BlockingResult<Int>()

        let outcome = result.wait(until: Date(timeIntervalSinceNow: 0.05))

        #expect(outcome == nil)
    }

    @Test("A deadline already in the past returns nil without blocking") func pastDeadline() {
        let result = BlockingResult<Int>()

        #expect(result.wait(until: .distantPast) == nil)
    }

    @Test("A result resolved before the deadline passes is returned even if the deadline is past")
    func resolvedBeforeWait() throws {
        let result = BlockingResult<Int>()
        result.resolve(.success(5))

        #expect(try result.wait(until: .distantPast)?.get() == 5)
    }
}
