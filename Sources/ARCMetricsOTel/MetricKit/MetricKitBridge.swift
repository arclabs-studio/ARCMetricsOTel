import ARCMetrics
import Foundation
import Synchronization

/// Sends ARCMetrics' MetricKit reports to OpenTelemetry.
///
/// Create it next to your `MetricsCollector` and run it for the app's lifetime:
///
/// ```swift
/// let bridge = MetricKitBridge(collector: collector, telemetry: telemetry)
/// Task { await bridge.run() }
/// collector.startCollecting()
/// ```
///
/// - Each metric summary becomes one `MXMetricPayload` span covering the report's interval, with
///   `metrickit.*` attributes.
/// - Each crash becomes an `app.crash` event (fatal) with `exception.type`, `exception.signal` and
///   `exception.termination_reason`; each hang an `app.hang` event (warn) with
///   `app.hang.duration_s`. Both are timestamped at the end of the report's interval.
///
/// Reports describe the past, but they join the session current when they arrive, so they never
/// end or rotate it. They follow session sampling and the kill switch like every record. A report
/// without an interval is skipped. The bridge never starts or stops the collector: the app owns it.
public final class MetricKitBridge: Sendable {
    private let telemetry: OTelTelemetry
    private let metrics: AsyncStream<MetricSummary>
    private let diagnostics: AsyncStream<DiagnosticSummary>
    private let hasRun = Mutex(false)

    /// Subscribes to `collector`'s reports. Reports delivered from now on are kept until
    /// ``run()`` sends them.
    public init(collector: any MetricsCollecting, telemetry: OTelTelemetry) {
        self.telemetry = telemetry
        metrics = collector.metricSummaries()
        diagnostics = collector.diagnosticSummaries()
    }

    /// Sends reports until both of the collector's streams finish or the task is cancelled.
    ///
    /// Call it once; later calls return immediately, so cancelling it stops the bridge for good.
    public func run() async {
        guard hasRun.claimFirst() else { return }
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await summary in self.metrics {
                    self.record(summary)
                }
            }
            group.addTask {
                for await summary in self.diagnostics {
                    self.record(summary)
                }
            }
        }
    }
}

// MARK: - Recording

private extension MetricKitBridge {
    func record(_ summary: MetricSummary) {
        guard let interval = summary.interval else { return }
        telemetry.recordSpan(name: MetricKitKeys.spanName,
                             attributes: summary.otelAttributes,
                             start: interval.start,
                             end: interval.end)
    }

    func record(_ summary: DiagnosticSummary) {
        guard let interval = summary.interval else { return }
        for crash in summary.crashes {
            telemetry.emitEvent(name: EventNames.crash,
                                attributes: crash.otelAttributes,
                                severity: .fatal,
                                timestamp: interval.end)
        }
        for hang in summary.hangs {
            telemetry.emitEvent(name: EventNames.hang,
                                attributes: [AttributeKeys.hangDuration: .double(hang.duration)],
                                severity: .warn,
                                timestamp: interval.end)
        }
    }
}
