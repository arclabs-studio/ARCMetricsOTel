import Foundation
import Testing
@testable import ARCMetricsOTel

/// Configurations for tests. The endpoint is a reserved `.test` host that nothing resolves.
enum TestConfiguration {
    static let serviceName = "FavRes"
    static let serviceVersion = "1.4.0"
    static let environment = "staging"

    static func make(endpoint: String = "https://otlp.example.test",
                     headers: [String: String] = [:],
                     settings: TelemetrySettings = .disabled,
                     allowsInsecureTransport: Bool = false,
                     attributeScrubber: AttributeScrubber = .default) throws -> OTelConfiguration {
        let url = try #require(URL(string: endpoint))
        return OTelConfiguration(serviceName: serviceName,
                                 serviceVersion: serviceVersion,
                                 environment: environment,
                                 endpoint: url,
                                 headers: headers,
                                 initialSettings: settings,
                                 allowsInsecureTransport: allowsInsecureTransport,
                                 attributeScrubber: attributeScrubber)
    }
}
