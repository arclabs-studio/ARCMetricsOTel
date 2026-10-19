import Foundation
import OpenTelemetryProtocolExporterCommon
import OpenTelemetrySdk
import PersistenceExporter

/// Everything ``OTelBootstrap`` reaches for outside the configuration — the test seam.
///
/// Production uses the defaults. Tests inject a clock, session ids, a `URLSession` with a stub
/// `URLProtocol`, a temporary storage root, a fake session store, a fake environment, and, for
/// the sampling tests, in-memory exporters in place of OTLP.
struct OTelDependencies {
    var clock: any TelemetryClock = SystemClock()
    var makeSessionID: @Sendable () -> String = { UUID().uuidString.lowercased() }
    var urlSession = URLSession(configuration: .ephemeral)
    /// The buffer root, or `nil` for `Application Support/ARCMetricsOTel`.
    var storageRoot: URL?
    var sessionStore: any SessionStore = UserDefaultsSessionStore()
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var operatingSystemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    var machine: @Sendable () -> String = { DeviceInfo.hardwareMachine() }
    /// Replaces the OTLP exporters (still behind the gate and the disk buffer).
    var exporters: ExporterOverride?
    var compression: CompressionType = .gzip
    var performancePreset: PersistencePerformancePreset = .arcMetricsOTel
    /// The batch processors' schedule delay, in seconds.
    var scheduleDelay: TimeInterval = 5
}
