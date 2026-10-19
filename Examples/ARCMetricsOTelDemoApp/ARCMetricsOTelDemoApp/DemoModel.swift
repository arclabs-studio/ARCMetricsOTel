import ARCMetrics
import ARCMetricsMocks
import ARCMetricsOTel
import Foundation
import Observation

/// Configures ARCMetricsOTel and drives every demo action.
///
/// The collector is `MockMetricsCollector`, so crashes, hangs and metric reports can be simulated
/// instead of waiting a day for MetricKit.
@Observable
final class DemoModel {
    /// Where telemetry is sent: `OTEL_EXPORTER_OTLP_ENDPOINT` from the launch environment, or a
    /// collector on this Mac.
    static let endpointVariable = "OTEL_EXPORTER_OTLP_ENDPOINT"
    static let defaultEndpoint = "http://localhost:4318"

    private(set) var state: DemoState = .starting
    private(set) var telemetry: OTelTelemetry?
    /// What the last action did, and a counter that changes on every action, so a repeated
    /// action is still announced.
    private(set) var lastAction = "" {
        didSet { actionCount += 1 }
    }

    private(set) var actionCount = 0
    var isEnabled = true {
        didSet { scheduleApplySettings() }
    }

    var sampleRate = 1.0 {
        didSet { scheduleApplySettings() }
    }

    private let collector = MockMetricsCollector()
    private var tasks: [Task<Void, Never>] = []

    /// Builds the pipeline once, then runs the MetricKit bridge and the lifecycle observer.
    func start() async {
        guard telemetry == nil else { return }
        let endpointString = ProcessInfo.processInfo.environment[Self.endpointVariable] ?? Self.defaultEndpoint
        guard let endpoint = URL(string: endpointString) else {
            state = .failed("Invalid endpoint: \(endpointString)")
            return
        }
        let configuration = OTelConfiguration(serviceName: "ARCMetricsOTelDemo",
                                              serviceVersion: Self.appVersion,
                                              environment: "development",
                                              endpoint: endpoint,
                                              initialSettings: settings,
                                              allowsInsecureTransport: true)
        do {
            let telemetry = try await OTelBootstrap.configure(configuration)
            let bridge = MetricKitBridge(collector: collector, telemetry: telemetry)
            let lifecycle = AppLifecycleObserver(telemetry: telemetry)
            tasks = [Task { await bridge.run() }, Task { await lifecycle.run() }]
            self.telemetry = telemetry
            state = .running(endpointHost: endpoint.host() ?? endpointString)
        } catch {
            state = .failed("Configuration failed: \(error)")
        }
    }

    /// Sends the kill switch and sample rate to the pipeline.
    func applySettings() async {
        await telemetry?.update(settings)
        lastAction = isEnabled ? "Telemetry on, sample rate \(sampleRate.formatted(.percent))" : "Telemetry off"
    }

    /// A 300 ms span recorded by MetricKit signposts and OpenTelemetry together.
    func runTracedOperation() async {
        guard let telemetry else { return }
        let tracer = TeeTracer([MetricKitSignpostTracer(), telemetry.tracer])
        do {
            try await tracer.trace("DemoOperation", category: .network, attributes: ["demo.step": "fetch"]) { _ in
                try await Task.sleep(for: .milliseconds(300))
            }
            lastAction = "Recorded span DemoOperation"
        } catch {
            lastAction = "DemoOperation was cancelled"
        }
    }

    func emitEvent() {
        telemetry?.emitEvent("demo.button_tapped", attributes: ["demo.source": "controls"])
        lastAction = "Emitted demo.button_tapped"
    }

    func simulateMetricReport() {
        collector.simulate(metric: DemoReports.metricSummary())
        lastAction = "Simulated a MetricKit metric report"
    }

    func simulateCrash() {
        collector.simulate(diagnostic: DemoReports.crashDiagnostic())
        lastAction = "Simulated a MetricKit crash report"
    }

    func simulateHang() {
        collector.simulate(diagnostic: DemoReports.hangDiagnostic())
        lastAction = "Simulated a MetricKit hang report"
    }

    func resetSession() {
        telemetry?.resetSession()
        lastAction = "Started a new session"
    }

    func flush() async {
        await telemetry?.flush()
        lastAction = "Flushed"
    }
}

// MARK: - Helpers

private extension DemoModel {
    func scheduleApplySettings() {
        Task { await applySettings() }
    }

    var settings: TelemetrySettings {
        TelemetrySettings(isEnabled: isEnabled, sampleRate: sampleRate)
    }

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }
}
