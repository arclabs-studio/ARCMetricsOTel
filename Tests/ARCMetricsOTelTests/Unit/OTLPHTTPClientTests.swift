import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("OTLPHTTPClient", .tags(.unit), .timeLimit(.minutes(1))) struct OTLPHTTPClientTests {
    private enum Outcome: Equatable {
        case response(Int)
        case failure
        case timedOut
    }

    /// Runs the blocking `send(request:completion:)` on a dedicated thread, as the exporters do.
    private actor Caller {
        private let executor = TelemetryExecutor(name: "OTLPHTTPClientTests")

        deinit {
            executor.stop()
        }

        nonisolated var unownedExecutor: UnownedSerialExecutor {
            executor.asUnownedSerialExecutor()
        }

        func sendBlocking(_ request: URLRequest,
                          over session: URLSession,
                          waitLimit: (@Sendable (URLRequest) -> TimeInterval)? = nil) -> Outcome {
            let client = waitLimit.map { OTLPHTTPClient(session: session, waitLimit: $0) }
                ?? OTLPHTTPClient(session: session)
            var outcome = Outcome.failure
            client.send(request: request) { result in
                switch result {
                case let .success(response):
                    outcome = .response(response.statusCode)
                case let .failure(error):
                    outcome = (error as? URLError)?.code == .timedOut ? .timedOut : .failure
                }
            }
            return outcome
        }
    }

    private struct SUT {
        let session: URLSession
        let request: URLRequest
        let testID: String
    }

    private func makeSUT(_ behavior: StubServer.Behavior) throws -> SUT {
        let testID = UUID().uuidString
        StubServer.shared.register(testID: testID, behavior: behavior)
        let url = try #require(URL(string: "https://otlp.example.test/v1/traces"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(testID, forHTTPHeaderField: StubServer.testIDHeader)
        return SUT(session: StubURLProtocol.makeSession(), request: request, testID: testID)
    }

    /// Status -> whether the exporter must see a delivery (success), per the OTLP/HTTP specification.
    private static let table: [(status: Int, delivered: Bool)] = [(200, true), (204, true), (400, true), (401, true),
                                                                  (403, true), (404, true), (413, true), (500, true),
                                                                  (429, false), (502, false), (503, false),
                                                                  (504, false)]

    @Test("Async send reports retryable statuses as failures and every other status as a response",
          arguments: table)
    func asyncStatusTable(status: Int, delivered: Bool) async throws {
        let sut = try makeSUT(.status(status))
        defer { StubServer.shared.unregister(testID: sut.testID) }

        let outcome: Outcome
        do {
            outcome = try await .response(OTLPHTTPClient(session: sut.session).send(request: sut.request).statusCode)
        } catch {
            outcome = .failure
        }

        #expect(outcome == (delivered ? .response(status) : .failure))
    }

    @Test("Blocking send reports retryable statuses as failures and every other status as a response",
          arguments: table)
    func blockingStatusTable(status: Int, delivered: Bool) async throws {
        let sut = try makeSUT(.status(status))
        defer { StubServer.shared.unregister(testID: sut.testID) }

        let outcome = await Caller().sendBlocking(sut.request, over: sut.session)

        #expect(outcome == (delivered ? .response(status) : .failure))
    }

    @Test("A transport error is a failure, in both overloads") func transportError() async throws {
        let sut = try makeSUT(.offline)
        defer { StubServer.shared.unregister(testID: sut.testID) }

        let blocking = await Caller().sendBlocking(sut.request, over: sut.session)
        var asyncFailed = false
        do {
            _ = try await OTLPHTTPClient(session: sut.session).send(request: sut.request)
        } catch {
            asyncFailed = true
        }

        #expect(blocking == .failure)
        #expect(asyncFailed)
    }

    @Test("A response that is not HTTP is a failure, in both overloads") func nonHTTPResponse() async throws {
        let sut = try makeSUT(.nonHTTP)
        defer { StubServer.shared.unregister(testID: sut.testID) }

        let blocking = await Caller().sendBlocking(sut.request, over: sut.session)
        var asyncFailed = false
        do {
            _ = try await OTLPHTTPClient(session: sut.session).send(request: sut.request)
        } catch {
            asyncFailed = true
        }

        #expect(blocking == .failure)
        #expect(asyncFailed)
    }

    @Test("A request that never answers is cancelled at the wait limit and reported as timed out")
    func hangingRequestTimesOut() async throws {
        let sut = try makeSUT(.hang)
        defer { StubServer.shared.unregister(testID: sut.testID) }

        let outcome = await Caller().sendBlocking(sut.request, over: sut.session, waitLimit: { _ in 0.2 })

        #expect(outcome == .timedOut)
    }
}
