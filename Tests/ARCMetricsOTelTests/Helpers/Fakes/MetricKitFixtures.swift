import ARCMetrics
import Foundation

/// MetricKit summaries with hand-picked literal values, so expected exports are worked out by hand.
///
/// The interval ends exactly one day before `FakeClock.epoch` (1_800_000_000 - 86_400), i.e. "yesterday"
/// for a test that never advances the clock.
enum MetricKitFixtures {
    static let intervalStart = Date(timeIntervalSince1970: 1_799_910_000)
    static let intervalEnd = Date(timeIntervalSince1970: 1_799_913_600)
    static let interval = DateInterval(start: intervalStart, end: intervalEnd)

    /// Every field distinct, so a swapped mapping cannot pass.
    static func fullMetricSummary() -> MetricSummary {
        var summary = MetricSummary(interval: interval)
        summary.peakMemoryUsageMB = 150.5
        summary.averageMemoryUsageMB = 80
        summary.cumulativeCPUTimeSeconds = 12.5
        summary.cumulativeGPUTimeSeconds = 3.25
        summary.foregroundTimeSeconds = 3600
        summary.backgroundTimeSeconds = 1800.5
        summary.cellularDownloadMB = 10.5
        summary.cellularUploadMB = 2.5
        summary.wifiDownloadMB = 200
        summary.wifiUploadMB = 40.25
        summary.cumulativeDiskWritesMB = 64.5
        summary.totalHangTimeSeconds = 0.75
        summary.averageLaunchTimeSeconds = 1.25
        summary.hitchTimeRatio = 4.5
        summary.scrollHitchTimeRatio = 2.5
        return summary
    }

    /// The `metrickit.*` attributes of `fullMetricSummary()`, computed by hand (MB x 1_000_000).
    static let fullMetricAttributes: [String: Double] = ["metrickit.memory.peak_memory_usage": 150_500_000,
                                                         "metrickit.memory.suspended_memory_average": 80_000_000,
                                                         "metrickit.cpu.cpu_time": 12.5,
                                                         "metrickit.gpu.time": 3.25,
                                                         "metrickit.app_time.foreground_time": 3600,
                                                         "metrickit.app_time.background_time": 1800.5,
                                                         "metrickit.network_transfer.cellular_download": 10_500_000,
                                                         "metrickit.network_transfer.cellular_upload": 2_500_000,
                                                         "metrickit.network_transfer.wifi_download": 200_000_000,
                                                         "metrickit.network_transfer.wifi_upload": 40_250_000,
                                                         "metrickit.diskio.logical_write_count": 64_500_000,
                                                         "metrickit.app_responsiveness.hang_time_total_s": 0.75,
                                                         "metrickit.app_launch.time_to_first_draw_average_s": 1.25,
                                                         "metrickit.animation.hitch_time_ratio_ms_per_s": 4.5,
                                                         "metrickit.animation.scroll_hitch_time_ratio_ms_per_s": 2.5]

    static let secretRegionInfo = "VM_REGION_SECRET_0xDEADBEEF"

    static func crash(exceptionType: String? = "EXC_BAD_ACCESS",
                      signal: String? = "SIGSEGV",
                      terminationReason: String? = "Namespace SIGNAL, Code 11") -> DiagnosticSummary.CrashInfo {
        DiagnosticSummary.CrashInfo(exceptionType: exceptionType,
                                    signal: signal,
                                    terminationReason: terminationReason,
                                    virtualMemoryRegionInfo: secretRegionInfo)
    }

    static func diagnostic(crashes: [DiagnosticSummary.CrashInfo] = [],
                           hangs: [DiagnosticSummary.HangInfo] = []) -> DiagnosticSummary {
        var summary = DiagnosticSummary(interval: interval)
        summary.crashes = crashes
        summary.hangs = hangs
        return summary
    }
}
