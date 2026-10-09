import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("EndpointValidator", .tags(.unit)) struct EndpointValidatorTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let url: String
        let allowsInsecure: Bool
        /// `nil` means accepted.
        let error: OTelBootstrapError?
        var testDescription: String {
            "\(url) insecure=\(allowsInsecure) -> \(String(describing: error))"
        }
    }

    /// `allowsInsecureTransport` is compiled out of Release builds.
    static var insecureAllowedResult: OTelBootstrapError? {
        #if DEBUG
        nil
        #else
        .insecureEndpoint
        #endif
    }

    static let cases = [Case(url: "https://otlp.example.com", allowsInsecure: false, error: nil),
                        Case(url: "https://otlp.example.com/otlp", allowsInsecure: true, error: nil),
                        Case(url: "http://localhost:4318", allowsInsecure: false, error: nil),
                        Case(url: "http://127.0.0.1", allowsInsecure: false, error: nil),
                        Case(url: "http://[::1]:4318", allowsInsecure: false, error: nil),
                        Case(url: "http://example.com", allowsInsecure: false, error: .insecureEndpoint),
                        Case(url: "http://example.com", allowsInsecure: true, error: Self.insecureAllowedResult),
                        Case(url: "https://user:token@otlp.example.com", allowsInsecure: false,
                             error: .invalidEndpoint),
                        Case(url: "https://user@otlp.example.com", allowsInsecure: false, error: .invalidEndpoint),
                        Case(url: "http://localhost.example.com", allowsInsecure: false, error: .insecureEndpoint),
                        Case(url: "http://127.0.0.1.example.com", allowsInsecure: false, error: .insecureEndpoint),
                        Case(url: "ftp://example.com", allowsInsecure: false, error: .invalidEndpoint),
                        Case(url: "ftp://example.com", allowsInsecure: true, error: .invalidEndpoint),
                        Case(url: "file:///tmp/collector", allowsInsecure: true, error: .invalidEndpoint),
                        Case(url: "https:///v1/traces", allowsInsecure: false, error: .invalidEndpoint)]

    @Test("Endpoints are accepted or rejected for the documented reason", arguments: cases)
    func validates(_ testCase: Case) throws {
        let url = try #require(URL(string: testCase.url))

        if let expected = testCase.error {
            #expect(throws: expected) {
                try EndpointValidator.validate(url, allowsInsecureTransport: testCase.allowsInsecure)
            }
        } else {
            #expect(throws: Never.self) {
                try EndpointValidator.validate(url, allowsInsecureTransport: testCase.allowsInsecure)
            }
        }
    }
}
