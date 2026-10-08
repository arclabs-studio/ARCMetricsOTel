import Foundation
import OpenTelemetryApi
import OpenTelemetryProtocolExporterCommon
import OpenTelemetryProtocolExporterHttp
import OpenTelemetrySdk
import Testing

/// Proves the test harness itself (stub transport, request-body decoding, routing) with the real
/// upstream OTLP exporters, so a later failure in an acceptance test cannot be the harness's fault.
@Suite("Test harness", .tags(.integration), .timeLimit(.minutes(1))) struct HarnessSelfTests {
    private let endpoint = URL(string: "https://otlp.example.test")

    private func makeExporters(testID: String, behavior: StubServer.Behavior) throws
    -> (traces: OtlpHttpTraceExporter, logs: OtlpHttpLogExporter) {
        StubServer.shared.register(testID: testID, behavior: behavior)
        let base = try #require(endpoint)
        let client = BaseHTTPClient(session: StubURLProtocol.makeSession())
        let config = OtlpConfiguration(compression: .none, headers: [(StubServer.testIDHeader, testID)])
        return (OtlpHttpTraceExporter(endpoint: base.appending(path: "v1/traces"),
                                      config: config,
                                      httpClient: client,
                                      envVarHeaders: nil,
                                      requeueOnFailure: false),
                OtlpHttpLogExporter(endpoint: base.appending(path: "v1/logs"),
                                    config: config,
                                    httpClient: client,
                                    envVarHeaders: nil,
                                    requeueOnFailure: false))
    }

    @Test("Spans and logs sent by the real OTLP exporters are routed, recorded and decoded")
    func decodesUpstreamBodies() throws {
        let testID = UUID().uuidString
        defer { StubServer.shared.unregister(testID: testID) }
        let (traces, logs) = try makeExporters(testID: testID, behavior: .ok)
        let resource = Resource(attributes: ["service.name": .string("HarnessService")])
        let span = try SampleData.spanData(named: "harness-span",
                                           attributes: ["session.id": .string("harness-session")],
                                           resource: resource)
        let record = SampleData.logRecord(eventName: "harness-event",
                                          attributes: ["session.id": .string("harness-session")],
                                          resource: resource)

        let spanResult = traces.export(spans: [span], explicitTimeout: nil)
        let logResult = logs.export(logRecords: [record], explicitTimeout: nil)

        #expect(spanResult == .success)
        #expect(logResult == .success)
        let requests = StubServer.shared.requests(for: testID)
        #expect(requests.map(\.path) == ["/v1/traces", "/v1/logs"])
        #expect(requests.allSatisfy { $0.headers[StubServer.testIDHeader] == testID && $0.succeeded })
        let decodedTraces = OTLPDecoder.traces(from: requests[0].body)
        #expect(decodedTraces.spans.map(\.name) == ["harness-span"])
        #expect(decodedTraces.spans.first?.attributes["session.id"] == "harness-session")
        #expect(decodedTraces.resourceAttributes["service.name"] == "HarnessService")
        let decodedLogs = OTLPDecoder.logs(from: requests[1].body)
        #expect(decodedLogs.records.map(\.eventName) == ["harness-event"])
        #expect(decodedLogs.records.first?.severityNumber == 9)
        #expect(decodedLogs.records.first?.attributes["session.id"] == "harness-session")
        #expect(decodedLogs.resourceAttributes["service.name"] == "HarnessService")
    }

    @Test("An offline stub fails the export and records the attempt as undelivered") func offlineFails() throws {
        let testID = UUID().uuidString
        defer { StubServer.shared.unregister(testID: testID) }
        let (traces, _) = try makeExporters(testID: testID, behavior: .offline)
        let span = try SampleData.spanData(named: "harness-span")

        let result = traces.export(spans: [span], explicitTimeout: nil)

        #expect(result == .failure)
        #expect(StubServer.shared.requests(for: testID).map(\.succeeded) == [false])
    }
}
