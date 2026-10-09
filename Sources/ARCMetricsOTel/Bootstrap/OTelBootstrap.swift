/// The entry point: builds an ``OTelTelemetry`` from an ``OTelConfiguration``.
///
/// ```swift
/// let telemetry = try await OTelBootstrap.configure(configuration)
/// await telemetry.update(TelemetrySettings(isEnabled: remoteFlag, sampleRate: remoteRate))
/// ```
public enum OTelBootstrap {
    /// Validates the configuration and starts telemetry.
    ///
    /// When ``OTelConfiguration/initialSettings`` has telemetry disabled, nothing is built and no
    /// directory is created until ``OTelTelemetry/update(_:)`` enables it.
    ///
    /// - Throws: ``OTelBootstrapError`` when the endpoint is invalid or insecure, or the disk
    ///   buffer cannot be created.
    public static func configure(_ configuration: OTelConfiguration) async throws(OTelBootstrapError)
    -> OTelTelemetry {
        try await configure(configuration, dependencies: OTelDependencies())
    }

    /// ``configure(_:)`` with injected dependencies — the test seam.
    static func configure(_ configuration: OTelConfiguration,
                          dependencies: OTelDependencies) async throws(OTelBootstrapError) -> OTelTelemetry {
        try EndpointValidator.validate(configuration.endpoint,
                                       allowsInsecureTransport: configuration.allowsInsecureTransport)
        let telemetry = OTelTelemetry(configuration: configuration, dependencies: dependencies)
        try await telemetry.start()
        return telemetry
    }
}
