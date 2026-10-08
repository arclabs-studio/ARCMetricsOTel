/// The two remotely controlled switches of the telemetry pipeline.
///
/// Feed these from your remote configuration (for example the `telemetry_otel_enabled` and
/// `telemetry_trace_sample_rate` flags) and push changes with ``OTelTelemetry/update(_:)``.
///
/// ```swift
/// await telemetry.update(TelemetrySettings(isEnabled: true, sampleRate: 0.25))
/// ```
public struct TelemetrySettings: Sendable, Equatable {
    /// The kill switch. While `false`, nothing is recorded, buffered or exported.
    public let isEnabled: Bool

    /// The fraction of sessions whose records are kept, in `0...1`.
    ///
    /// Sampling is decided per session, so a session is either kept whole or dropped whole.
    public let sampleRate: Double

    /// Creates settings.
    ///
    /// - Parameters:
    ///   - isEnabled: Whether telemetry is recorded and exported at all.
    ///   - sampleRate: The fraction of sessions to keep. Values outside `0...1` are clamped,
    ///     and `NaN` is treated as `0`.
    public init(isEnabled: Bool, sampleRate: Double) {
        self.isEnabled = isEnabled
        self.sampleRate = sampleRate.isNaN ? 0 : min(max(sampleRate, 0), 1)
    }

    /// Telemetry off. The default until remote configuration says otherwise.
    public static let disabled = TelemetrySettings(isEnabled: false, sampleRate: 0)
}
