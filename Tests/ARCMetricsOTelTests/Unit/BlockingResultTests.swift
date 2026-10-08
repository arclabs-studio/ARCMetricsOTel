import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("BlockingResult", .tags(.unit), .timeLimit(.minutes(1))) struct BlockingResultTests {
    private struct Failure: Error, Equatable {
        let code: Int
    }

    @Test("A value produced by the operation is returned by wait()") func returnsValue() async throws {
        let result = BlockingResult<Int>()

        await result.resolve { 42 }

        #expect(try result.wait(until: .distantFuture)?.get() == 42)
    }

    @Test("An error thrown by the operation is returned by wait()") func returnsFailure() async {
        let result = BlockingResult<Int>()

        await result.resolve { throw Failure(code: 7) }

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
    func resolvedBeforeWait() async throws {
        let result = BlockingResult<Int>()
        await result.resolve { 5 }

        #expect(try result.wait(until: .distantPast)?.get() == 5)
    }
}
