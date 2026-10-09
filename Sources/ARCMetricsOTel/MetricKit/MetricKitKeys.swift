/// Attribute keys of the MetricKit metric span.
///
/// Where an ARCMetrics value means exactly what upstream opentelemetry-swift's MetricKit
/// instrumentation reports, the key and base unit are upstream's, so dashboards built for it
/// work. Where the meaning differs, the key is our own and names its unit.
enum MetricKitKeys {
    static let spanName = "MXMetricPayload"

    // Upstream names, base units (bytes, seconds).
    static let peakMemory = "metrickit.memory.peak_memory_usage"
    static let suspendedMemoryAverage = "metrickit.memory.suspended_memory_average"
    static let cpuTime = "metrickit.cpu.cpu_time"
    static let gpuTime = "metrickit.gpu.time"
    static let foregroundTime = "metrickit.app_time.foreground_time"
    static let backgroundTime = "metrickit.app_time.background_time"
    static let cellularDownload = "metrickit.network_transfer.cellular_download"
    static let cellularUpload = "metrickit.network_transfer.cellular_upload"
    static let wifiDownload = "metrickit.network_transfer.wifi_download"
    static let wifiUpload = "metrickit.network_transfer.wifi_upload"
    static let diskWrites = "metrickit.diskio.logical_write_count"

    /// Our own: upstream reports an average hang time, ARCMetrics a total.
    static let hangTimeTotal = "metrickit.app_responsiveness.hang_time_total_s"
    /// Our own: ARCMetrics weights each histogram bucket by its lower edge, upstream by its midpoint.
    static let launchTimeAverage = "metrickit.app_launch.time_to_first_draw_average_s"
    // Our own: ARCMetrics reports hitch ratios in milliseconds per second.
    static let hitchTimeRatio = "metrickit.animation.hitch_time_ratio_ms_per_s"
    static let scrollHitchTimeRatio = "metrickit.animation.scroll_hitch_time_ratio_ms_per_s"
}
