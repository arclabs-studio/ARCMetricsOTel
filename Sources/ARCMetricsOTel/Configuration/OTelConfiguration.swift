import Foundation

/// Everything ``OTelBootstrap`` needs to build the export pipeline.
///
/// ```swift
/// guard let endpoint = URL(string: "https://otlp.example.com") else { return }
/// let configuration = OTelConfiguration(serviceName: "FavRes",
///                                       serviceVersion: "1.4.0",
///                                       environment: "production",
///                                       endpoint: endpoint,
///                                       headers: ["Authorization": "Basic …"])
/// ```
///
/// The ``headers`` usually carry credentials, so their values are redacted from ``description``,
/// ``debugDescription`` and reflection (`dump`, `Mirror`, the debugger).
public struct OTelConfiguration: Sendable {
    /// `service.name` on every record.
    public var serviceName: String

    /// `service.version` on every record.
    public var serviceVersion: String

    /// `deployment.environment.name` on every record, for example `production`.
    public var environment: String

    /// The OTLP/HTTP base URL. Traces go to `v1/traces` and logs to `v1/logs` below it.
    ///
    /// Must be `https`, unless the host is `localhost` / a loopback address or, in Debug builds,
    /// ``allowsInsecureTransport`` is `true`. Credentials belong in ``headers``: an endpoint with
    /// a user name or password is rejected.
    public var endpoint: URL

    /// HTTP headers sent with every export request, typically authentication.
    public var headers: [String: String]

    /// The settings in force until the first ``OTelTelemetry/update(_:)``.
    public var initialSettings: TelemetrySettings

    /// When sessions end.
    public var sessionPolicy: SessionPolicy

    /// The longest a single export or flush may block.
    public var exportTimeout: Duration

    /// Allows a plain `http` endpoint on a non-loopback host, for a local collector during
    /// development. Honoured in Debug builds only: Release builds ignore it.
    public var allowsInsecureTransport: Bool

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - serviceName: `service.name`.
    ///   - serviceVersion: `service.version`.
    ///   - environment: `deployment.environment.name`.
    ///   - endpoint: The OTLP/HTTP base URL.
    ///   - headers: Headers sent with every export request.
    ///   - initialSettings: The settings in force at launch. Defaults to ``TelemetrySettings/disabled``.
    ///   - sessionPolicy: When sessions end. Defaults to ``SessionPolicy/faro``.
    ///   - exportTimeout: The longest an export or flush may block. Defaults to 10 seconds.
    ///   - allowsInsecureTransport: Allows `http` on a non-loopback host in Debug builds. Defaults to `false`.
    public init(serviceName: String,
                serviceVersion: String,
                environment: String,
                endpoint: URL,
                headers: [String: String] = [:],
                initialSettings: TelemetrySettings = .disabled,
                sessionPolicy: SessionPolicy = .faro,
                exportTimeout: Duration = .seconds(10),
                allowsInsecureTransport: Bool = false) {
        self.serviceName = serviceName
        self.serviceVersion = serviceVersion
        self.environment = environment
        self.endpoint = endpoint
        self.headers = headers
        self.initialSettings = initialSettings
        self.sessionPolicy = sessionPolicy
        self.exportTimeout = exportTimeout
        self.allowsInsecureTransport = allowsInsecureTransport
    }
}

// MARK: - CustomStringConvertible

extension OTelConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    /// A summary with header values redacted.
    public var description: String {
        let headerNames = headers.keys.sorted().joined(separator: ", ")
        return "OTelConfiguration(service: \(serviceName) \(serviceVersion), environment: \(environment), "
            + "endpoint host: \(endpointHost), headers: [\(headerNames)] (values redacted))"
    }

    /// Same as ``description``: header values stay redacted.
    public var debugDescription: String {
        description
    }
}

// MARK: - CustomReflectable

extension OTelConfiguration: CustomReflectable {
    /// Every property, with header values replaced by `<redacted>` and the endpoint reduced to its
    /// host, as in ``description``.
    public var customMirror: Mirror {
        Mirror(self,
               children: ["serviceName": serviceName,
                          "serviceVersion": serviceVersion,
                          "environment": environment,
                          "endpointHost": endpointHost,
                          "headers": headers.mapValues { _ in "<redacted>" },
                          "initialSettings": initialSettings,
                          "sessionPolicy": sessionPolicy,
                          "exportTimeout": exportTimeout,
                          "allowsInsecureTransport": allowsInsecureTransport],
               displayStyle: .struct)
    }
}

// MARK: - Redaction

private extension OTelConfiguration {
    /// The endpoint's host alone: its path, query and any user info may carry secrets.
    var endpointHost: String {
        endpoint.host(percentEncoded: false) ?? ""
    }
}
