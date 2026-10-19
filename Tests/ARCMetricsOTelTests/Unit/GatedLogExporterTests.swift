import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("GatedLogExporter", .tags(.unit)) struct GatedLogExporterTests {
    private struct SUT {
        let exporter: GatedLogExporter
        let inner: RecordingLogExporter
        let gate: TelemetryGate
    }

    private func makeSUT(enabled: Bool = true,
                         exportResult: ExportResult = .success,
                         flushResult: ExportResult = .success) -> SUT {
        let inner = RecordingLogExporter(exportResult: exportResult, flushResult: flushResult)
        let gate = TelemetryGate(TelemetrySettings(isEnabled: enabled, sampleRate: 1))
        return SUT(exporter: GatedLogExporter(inner: inner, gate: gate), inner: inner, gate: gate)
    }

    private let records = [SampleData.logRecord(eventName: "app.event")]

    // MARK: Enabled

    @Test("Enabled: export forwards the records and returns the inner result",
          arguments: [ExportResult.success, .failure])
    func enabledExport(result: ExportResult) {
        let sut = makeSUT(exportResult: result)

        let returned = sut.exporter.export(logRecords: records, explicitTimeout: nil)

        #expect(returned == result)
        #expect(sut.inner.exportedRecords.map(\.eventName) == ["app.event"])
    }

    @Test("Enabled: forceFlush forwards and returns the inner result", arguments: [ExportResult.success, .failure])
    func enabledFlush(result: ExportResult) {
        let sut = makeSUT(flushResult: result)

        let returned = sut.exporter.forceFlush(explicitTimeout: nil)

        #expect(returned == result)
        #expect(sut.inner.flushCalls == 1)
    }

    @Test("Enabled: the async overloads forward too", arguments: [ExportResult.success, .failure])
    func enabledAsync(result: ExportResult) async {
        let sut = makeSUT(exportResult: result, flushResult: result)

        let exported = await sut.exporter.export(logRecords: records, explicitTimeout: nil)
        let flushed = await sut.exporter.forceFlush(explicitTimeout: nil)

        #expect(exported == result)
        #expect(flushed == result)
        #expect(sut.inner.exportedRecords.map(\.eventName) == ["app.event"])
        #expect(sut.inner.flushCalls == 1)
    }

    // MARK: Disabled

    @Test("Disabled: export discards the batch and reports success") func disabledExport() {
        let sut = makeSUT(enabled: false, exportResult: .failure)

        let returned = sut.exporter.export(logRecords: records, explicitTimeout: nil)

        #expect(returned == .success)
        #expect(sut.inner.exportCalls == 0)
    }

    @Test("Disabled: forceFlush does not reach the inner exporter and reports success") func disabledFlush() {
        let sut = makeSUT(enabled: false, flushResult: .failure)

        let returned = sut.exporter.forceFlush(explicitTimeout: nil)

        #expect(returned == .success)
        #expect(sut.inner.flushCalls == 0)
    }

    @Test("Disabled: the async overloads discard too") func disabledAsync() async {
        let sut = makeSUT(enabled: false, exportResult: .failure, flushResult: .failure)

        let exported = await sut.exporter.export(logRecords: records, explicitTimeout: nil)
        let flushed = await sut.exporter.forceFlush(explicitTimeout: nil)

        #expect(exported == .success)
        #expect(flushed == .success)
        #expect(sut.inner.exportCalls == 0)
        #expect(sut.inner.flushCalls == 0)
    }

    @Test("The gate is read on every call") func gateIsLive() {
        let sut = makeSUT()
        _ = sut.exporter.export(logRecords: records, explicitTimeout: nil)

        sut.gate.update(.disabled)
        _ = sut.exporter.export(logRecords: records, explicitTimeout: nil)

        #expect(sut.inner.exportCalls == 1)
    }

    // MARK: Shutdown

    /// Overload resolution picks the `async` form inside an async test, so the sync one needs a sync context.
    private func shutDownSynchronously(_ sut: SUT) {
        sut.exporter.shutdown(explicitTimeout: nil)
    }

    @Test("Shutdown always reaches the inner exporter", arguments: [true, false])
    func shutdownForwarded(enabled: Bool) async {
        let sut = makeSUT(enabled: enabled)

        shutDownSynchronously(sut)
        await sut.exporter.shutdown(explicitTimeout: nil)

        #expect(sut.inner.shutdownCalls == 2)
    }
}
