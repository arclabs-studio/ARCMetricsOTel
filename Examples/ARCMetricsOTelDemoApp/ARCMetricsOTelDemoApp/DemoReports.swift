import ARCMetrics
import Foundation

/// MetricKit summaries the demo simulates, covering yesterday.
enum DemoReports {
    static var yesterday: DateInterval {
        let end = Date.now.addingTimeInterval(-60)
        return DateInterval(start: end.addingTimeInterval(-24 * 60 * 60), end: end)
    }

    static func metricSummary() -> MetricSummary {
        var summary = MetricSummary(interval: yesterday)
        summary.peakMemoryUsageMB = 182.5
        summary.averageMemoryUsageMB = 96
        summary.cumulativeCPUTimeSeconds = 42.5
        summary.foregroundTimeSeconds = 1800
        summary.backgroundTimeSeconds = 600
        summary.totalHangTimeSeconds = 1.25
        summary.averageLaunchTimeSeconds = 0.9
        summary.wifiDownloadMB = 12.5
        summary.hitchTimeRatio = 3.5
        return summary
    }

    static func crashDiagnostic() -> DiagnosticSummary {
        var summary = DiagnosticSummary(interval: yesterday)
        summary.crashes = [DiagnosticSummary.CrashInfo(exceptionType: "1",
                                                       signal: "11",
                                                       terminationReason: "Namespace SIGNAL, Code 11",
                                                       virtualMemoryRegionInfo: nil)]
        return summary
    }

    static func hangDiagnostic() -> DiagnosticSummary {
        var summary = DiagnosticSummary(interval: yesterday)
        summary.hangs = [DiagnosticSummary.HangInfo(duration: 2.5)]
        return summary
    }
}
