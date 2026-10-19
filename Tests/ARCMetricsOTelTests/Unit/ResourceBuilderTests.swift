import OpenTelemetryApi
import Testing
@testable import ARCMetricsOTel

@Suite("ResourceBuilder", .tags(.unit)) struct ResourceBuilderTests {
    private func makeSUT() throws -> [String: AttributeValue] {
        let configuration = try TestConfiguration.make()
        let device = DeviceInfo(osName: "iOS", osVersion: "27.0.1", modelIdentifier: "iPhone17,1")
        return ResourceBuilder.make(configuration: configuration, device: device).attributes
    }

    @Test("The Resource carries the service, environment, OS and device facts")
    func carriesDocumentedAttributes() throws {
        let attributes = try makeSUT()

        #expect(attributes["service.name"] == .string("FavRes"))
        #expect(attributes["service.version"] == .string("1.4.0"))
        #expect(attributes["deployment.environment.name"] == .string("staging"))
        #expect(attributes["os.name"] == .string("iOS"))
        #expect(attributes["os.version"] == .string("27.0.1"))
        #expect(attributes["os.type"] == .string("darwin"))
        #expect(attributes["device.model.identifier"] == .string("iPhone17,1"))
    }

    @Test("The SDK's own attributes are kept") func keepsSDKDefaults() throws {
        let attributes = try makeSUT()

        #expect(attributes["service.name"] == .string("FavRes"))
        #expect(attributes["telemetry.sdk.language"] != nil)
    }

    @Test("The session id is never on the Resource, because sessions rotate") func hasNoSessionID() throws {
        let attributes = try makeSUT()

        #expect(attributes["service.name"] == .string("FavRes"))
        #expect(attributes["session.id"] == nil)
    }
}
