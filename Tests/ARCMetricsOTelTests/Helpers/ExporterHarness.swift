import Foundation
@testable import ARCMetricsOTel

/// An `IntegrationSUT` whose spans and logs land in recording exporters.
struct ExporterHarness {
    let sut: IntegrationSUT
    let spans: RecordingSpanExporter
    let logs: RecordingLogExporter

    var telemetry: OTelTelemetry {
        sut.telemetry
    }

    static func make(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1),
                     attributeScrubber: AttributeScrubber = .default) async throws -> ExporterHarness {
        let spans = RecordingSpanExporter()
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(settings: settings,
                                                   sessionIDs: ["s-1", "s-2"],
                                                   exporters: ExporterOverride(spans: spans, logs: logs),
                                                   attributeScrubber: attributeScrubber)
        return ExporterHarness(sut: sut, spans: spans, logs: logs)
    }
}
