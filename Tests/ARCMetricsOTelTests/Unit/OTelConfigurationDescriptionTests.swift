import Testing
@testable import ARCMetricsOTel

@Suite("OTelConfiguration description", .tags(.unit)) struct OTelConfigurationDescriptionTests {
    private let secrets = ["Basic dXNlcjpzM2NyM3Q=", "k-9f8e7d6c5b4a"]

    private func makeSUT() throws -> OTelConfiguration {
        try TestConfiguration.make(headers: ["Authorization": secrets[0], "x-api-key": secrets[1]])
    }

    @Test("Descriptions name the service but never a header value") func redactsHeaderValues() throws {
        let configuration = try makeSUT()

        for text in [configuration.description,
                     configuration.debugDescription,
                     "\(configuration)",
                     String(reflecting: configuration)] {
            // Guard against a vacuous pass: the text must say something about the configuration.
            #expect(text.contains(TestConfiguration.serviceName))
            for secret in secrets {
                #expect(!text.contains(secret))
            }
        }
    }

    @Test("A description of a configuration whose endpoint has no host shows an empty host")
    func descriptionWithoutHost() throws {
        let configuration = try TestConfiguration.make(endpoint: "mailto:ops@example.test",
                                                       headers: ["Authorization": "secret"])

        #expect(configuration.description
            == "OTelConfiguration(service: FavRes 1.4.0, environment: staging, "
            + "endpoint host: , headers: [Authorization] (values redacted))")
    }

    @Test("dump and Mirror never expose a header value") func reflectionRedactsHeaderValues() throws {
        let configuration = try makeSUT()

        var dumped = ""
        dump(configuration, to: &dumped)
        let mirrored = Mirror(reflecting: configuration).children.map { "\($0.label ?? ""): \($0.value)" }

        #expect(dumped.contains(TestConfiguration.serviceName))
        #expect(!mirrored.isEmpty)
        for secret in secrets {
            #expect(!dumped.contains(secret))
            #expect(!mirrored.contains { $0.contains(secret) })
        }
    }

    @Test("A query string on the endpoint never appears in a dump") func reflectionHidesEndpointQuery() throws {
        let configuration = try TestConfiguration.make(endpoint: "https://otlp.example.test/v1?api_key=hunter2")

        var dumped = ""
        dump(configuration, to: &dumped)

        #expect(dumped.contains("otlp.example.test"))
        #expect(!dumped.contains("hunter2"))
        #expect(!dumped.contains("api_key"))
    }
}
