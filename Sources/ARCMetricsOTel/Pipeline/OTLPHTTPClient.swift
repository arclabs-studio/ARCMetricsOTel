import Foundation
import OpenTelemetryProtocolExporterHttp

/// The HTTP client behind the OTLP exporters. Unlike upstream's `BaseHTTPClient`, it tells a
/// rejected batch from a failed delivery.
///
/// The disk buffer retries every failure, and upstream reports any non-2xx response as one. A
/// batch the collector will never accept — a revoked token, a malformed or oversized payload —
/// would be resent from every device for as long as the file lives. Following the OTLP/HTTP
/// specification, only 429, 502, 503 and 504 and transport errors are retryable; any other status
/// is reported as success, so the buffer deletes the batch instead of retrying it.
final class OTLPHTTPClient: HTTPClient {
    /// The statuses the OTLP/HTTP specification marks as retryable.
    static let retryableStatusCodes: Set = [429, 502, 503, 504]

    private let session: URLSession
    private let waitLimit: @Sendable (URLRequest) -> TimeInterval

    /// - Parameters:
    ///   - session: The session that sends the requests.
    ///   - waitLimit: How long the blocking ``send(request:completion:)`` waits before it gives up
    ///     and cancels the request. Defaults to the request's timeout plus one second, so
    ///     `URLSession`'s own timeout normally fires first.
    init(session: URLSession,
         waitLimit: @escaping @Sendable (URLRequest) -> TimeInterval = { $0.timeoutInterval + 1 }) {
        self.session = session
        self.waitLimit = waitLimit
    }

    /// Sends `request` and calls `completion` on the calling thread before returning.
    ///
    /// Upstream calls this from its own export threads — the disk buffer's worker or
    /// ``OTelTelemetry``'s dedicated thread, never Swift's cooperative pool — and then waits for
    /// the completion anyway. Waiting here keeps the non-`Sendable` completion on its own thread.
    /// The wait is bounded: past the limit the request is cancelled and reported as timed out,
    /// so a stalled request never holds the buffer's worker or the telemetry thread for longer.
    func send(request: URLRequest, completion: @escaping (Result<HTTPURLResponse, any Error>) -> Void) {
        let outcome = BlockingResult<HTTPURLResponse>()
        let delivery = Self.startDelivery(request, with: session, into: outcome)
        if let result = outcome.wait(until: Date(timeIntervalSinceNow: waitLimit(request))) {
            completion(result)
        } else {
            delivery.cancel()
            completion(.failure(URLError(.timedOut)))
        }
    }

    func send(request: URLRequest) async throws -> HTTPURLResponse {
        try await Self.deliver(request, with: session)
    }
}

// MARK: - Delivery

private extension OTLPHTTPClient {
    struct UnexpectedResponse: Error {}

    struct RetryableStatus: Error {
        let statusCode: Int
    }

    /// Starts delivering `request` and resolves `outcome` when it finishes.
    ///
    /// A separate function whose parameters are all `Sendable`: Xcode 26's region-based isolation
    /// checker rejects the task when it is created next to the non-`Sendable` completion.
    static func startDelivery(_ request: URLRequest,
                              with session: URLSession,
                              into outcome: BlockingResult<HTTPURLResponse>) -> Task<Void, Never> {
        Task {
            do {
                try await outcome.resolve(.success(deliver(request, with: session)))
            } catch {
                outcome.resolve(.failure(error))
            }
        }
    }

    static func deliver(_ request: URLRequest, with session: URLSession) async throws -> HTTPURLResponse {
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw UnexpectedResponse()
        }
        guard !retryableStatusCodes.contains(response.statusCode) else {
            throw RetryableStatus(statusCode: response.statusCode)
        }
        return response
    }
}
