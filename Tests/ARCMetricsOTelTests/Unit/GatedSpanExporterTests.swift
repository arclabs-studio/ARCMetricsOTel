import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("GatedSpanExporter", .tags(.unit)) struct GatedSpanExporterTests {
    private struct SUT {
        let exporter: GatedSpanExporter
        let inner: RecordingSpanExporter
        let gate: TelemetryGate
    }

    private func makeSUT(enabled: Bool = true,
                         exportResult: SpanExporterResultCode = .success,
                         flushResult: SpanExporterResultCode = .success) -> SUT {
        let inner = RecordingSpanExporter(exportResult: exportResult, flushResult: flushResult)
        let gate = TelemetryGate(TelemetrySettings(isEnabled: enabled, sampleRate: 1))
        return SUT(exporter: GatedSpanExporter(inner: inner, gate: gate), inner: inner, gate: gate)
    }

    // MARK: Enabled

    @Test("Enabled: export forwards the spans and returns the inner result",
          arguments: [SpanExporterResultCode.success, .failure])
    func enabledExport(result: SpanExporterResultCode) throws {
        let sut = makeSUT(exportResult: result)
        let span = try SampleData.spanData(named: "load")

        let returned = sut.exporter.export(spans: [span], explicitTimeout: nil)

        #expect(returned == result)
        #expect(sut.inner.exportedSpans.map(\.name) == ["load"])
    }

    @Test("Enabled: flush forwards and returns the inner result", arguments: [SpanExporterResultCode.success, .failure])
    func enabledFlush(result: SpanExporterResultCode) {
        let sut = makeSUT(flushResult: result)

        let returned = sut.exporter.flush(explicitTimeout: nil)

        #expect(returned == result)
        #expect(sut.inner.flushCalls == 1)
    }

    @Test("Enabled: the async overloads forward too", arguments: [SpanExporterResultCode.success, .failure])
    func enabledAsync(result: SpanExporterResultCode) async throws {
        let sut = makeSUT(exportResult: result, flushResult: result)
        let span = try SampleData.spanData(named: "load")

        let exported = await sut.exporter.export(spans: [span], explicitTimeout: nil)
        let flushed = await sut.exporter.flush(explicitTimeout: nil)

        #expect(exported == result)
        #expect(flushed == result)
        #expect(sut.inner.exportedSpans.map(\.name) == ["load"])
        #expect(sut.inner.flushCalls == 1)
    }

    // MARK: Disabled

    @Test("Disabled: export discards the batch and reports success") func disabledExport() throws {
        let sut = makeSUT(enabled: false, exportResult: .failure)
        let span = try SampleData.spanData(named: "load")

        let returned = sut.exporter.export(spans: [span], explicitTimeout: nil)

        #expect(returned == .success)
        #expect(sut.inner.exportCalls == 0)
    }

    @Test("Disabled: flush does not reach the inner exporter and reports success") func disabledFlush() {
        let sut = makeSUT(enabled: false, flushResult: .failure)

        let returned = sut.exporter.flush(explicitTimeout: nil)

        #expect(returned == .success)
        #expect(sut.inner.flushCalls == 0)
    }

    @Test("Disabled: the async overloads discard too") func disabledAsync() async throws {
        let sut = makeSUT(enabled: false, exportResult: .failure, flushResult: .failure)
        let span = try SampleData.spanData(named: "load")

        let exported = await sut.exporter.export(spans: [span], explicitTimeout: nil)
        let flushed = await sut.exporter.flush(explicitTimeout: nil)

        #expect(exported == .success)
        #expect(flushed == .success)
        #expect(sut.inner.exportCalls == 0)
        #expect(sut.inner.flushCalls == 0)
    }

    @Test("The gate is read on every call") func gateIsLive() throws {
        let sut = makeSUT()
        let span = try SampleData.spanData(named: "load")
        _ = sut.exporter.export(spans: [span], explicitTimeout: nil)

        sut.gate.update(.disabled)
        _ = sut.exporter.export(spans: [span], explicitTimeout: nil)

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
