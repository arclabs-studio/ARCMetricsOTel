import Foundation
import Synchronization

/// The shared, per-test routing table behind ``StubURLProtocol``.
///
/// `URLProtocol` classes are instantiated by the URL loading system, so their state has to be
/// global. A `Mutex` makes this checked `Sendable`, and every test routes through its own
/// `x-test-id` header, so parallel tests never see each other's traffic.
final class StubServer: Sendable {
    static let shared = StubServer()

    static let testIDHeader = "x-test-id"

    enum Behavior: Sendable, Equatable {
        /// Answer `200`.
        case ok
        /// Fail like a device without connectivity.
        case offline
        /// Answer an HTTP response with this status.
        case status(Int)
        /// Answer a response that is not HTTP.
        case nonHTTP
        /// Never answer.
        case hang
    }

    struct Request: Sendable {
        let path: String
        let headers: [String: String]
        let body: Data
        /// Whether the stub answered `200`.
        let succeeded: Bool
    }

    private struct State {
        var behaviors: [String: Behavior] = [:]
        var requests: [String: [Request]] = [:]
    }

    private let state = Mutex(State())

    func register(testID: String, behavior: Behavior) {
        state.withLock { $0.behaviors[testID] = behavior }
    }

    func setBehavior(_ behavior: Behavior, for testID: String) {
        state.withLock { $0.behaviors[testID] = behavior }
    }

    func unregister(testID: String) {
        state.withLock {
            $0.behaviors[testID] = nil
            $0.requests[testID] = nil
        }
    }

    func requests(for testID: String) -> [Request] {
        state.withLock { $0.requests[testID] ?? [] }
    }

    /// Records the request and returns how the stub answers it.
    func handle(testID: String, path: String, headers: [String: String], body: Data) -> Behavior {
        state.withLock {
            let behavior = $0.behaviors[testID] ?? .offline
            let request = Request(path: path, headers: headers, body: body, succeeded: behavior == .ok)
            $0.requests[testID, default: []].append(request)
            return behavior
        }
    }
}
