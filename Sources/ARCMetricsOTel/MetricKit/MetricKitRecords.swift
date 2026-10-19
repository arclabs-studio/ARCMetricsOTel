import ARCMetrics
import Foundation

/// ARCMetrics reports megabytes as decimal megabytes (`UnitInformationStorage.megabytes`).
private let bytesPerMegabyte = 1_000_000.0

extension MetricSummary {
    /// The metric span's attributes. The hitch ratios appear only when MetricKit reported them.
    var traceAttributes: TraceAttributes {
        var attributes: TraceAttributes = [:]
        attributes[MetricKitKeys.peakMemory] = .double(peakMemoryUsageMB * bytesPerMegabyte)
        attributes[MetricKitKeys.suspendedMemoryAverage] = .double(averageMemoryUsageMB * bytesPerMegabyte)
        attributes[MetricKitKeys.cpuTime] = .double(cumulativeCPUTimeSeconds)
        attributes[MetricKitKeys.gpuTime] = .double(cumulativeGPUTimeSeconds)
        attributes[MetricKitKeys.foregroundTime] = .double(foregroundTimeSeconds)
        attributes[MetricKitKeys.backgroundTime] = .double(backgroundTimeSeconds)
        attributes[MetricKitKeys.cellularDownload] = .double(cellularDownloadMB * bytesPerMegabyte)
        attributes[MetricKitKeys.cellularUpload] = .double(cellularUploadMB * bytesPerMegabyte)
        attributes[MetricKitKeys.wifiDownload] = .double(wifiDownloadMB * bytesPerMegabyte)
        attributes[MetricKitKeys.wifiUpload] = .double(wifiUploadMB * bytesPerMegabyte)
        attributes[MetricKitKeys.diskWrites] = .double(cumulativeDiskWritesMB * bytesPerMegabyte)
        attributes[MetricKitKeys.hangTimeTotal] = .double(totalHangTimeSeconds)
        attributes[MetricKitKeys.launchTimeAverage] = .double(averageLaunchTimeSeconds)
        if let hitchTimeRatio {
            attributes[MetricKitKeys.hitchTimeRatio] = .double(hitchTimeRatio)
        }
        if let scrollHitchTimeRatio {
            attributes[MetricKitKeys.scrollHitchTimeRatio] = .double(scrollHitchTimeRatio)
        }
        return attributes
    }
}

extension DiagnosticSummary.CrashInfo {
    /// The crash's `exception.*` attributes, for the fields MetricKit reported.
    /// `virtualMemoryRegionInfo` is left out: it can hold memory addresses.
    /// `terminationReason` is kept only in its structured form (see ``structuredTerminationReason``).
    var traceAttributes: TraceAttributes {
        var attributes: TraceAttributes = [:]
        if let exceptionType {
            attributes[AttributeKeys.exceptionType] = .string(exceptionType)
        }
        if let signal {
            attributes[AttributeKeys.exceptionSignal] = .string(signal)
        }
        if let reason = Self.structuredTerminationReason(terminationReason) {
            attributes[AttributeKeys.exceptionTerminationReason] = .string(reason)
        }
        return attributes
    }

    /// The longest termination reason exported; longer ones are left out.
    static let maxTerminationReasonLength = 64

    /// `reason` when the whole string is `Namespace <NAME>, Code <decimal or 0x hex>`, else `nil`.
    ///
    /// The OS writes free text after the code for some crashes (a missing library's path, a
    /// watchdog's scene and bundle id), and a path can hold the app's per-install container UUID,
    /// which would link sessions. Only the structured form is exported.
    static func structuredTerminationReason(_ reason: String?) -> String? {
        guard let reason, reason.count <= maxTerminationReasonLength else { return nil }
        let structured = /Namespace [A-Z0-9_]+, Code (?:0x[0-9a-fA-F]+|[0-9]+)/
        return reason.wholeMatch(of: structured) == nil ? nil : reason
    }
}
