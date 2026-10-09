import OpenTelemetryApi
import OpenTelemetrySdk

/// Builds the Resource shared by every span and log record.
///
/// SDK defaults (`telemetry.sdk.*`) plus `service.name`, `service.version`,
/// `deployment.environment.name`, `os.name`, `os.version`, `os.type` and
/// `device.model.identifier`. The session id is deliberately not here: a Resource is fixed for
/// the pipeline's lifetime, but sessions rotate, so `session.id` goes on each record.
enum ResourceBuilder {
    static func make(configuration: OTelConfiguration, device: DeviceInfo) -> Resource {
        let attributes: [String: AttributeValue] = [AttributeKeys.serviceName: .string(configuration.serviceName),
                                                    AttributeKeys.serviceVersion: .string(configuration.serviceVersion),
                                                    AttributeKeys
                                                        .deploymentEnvironment: .string(configuration.environment),
                                                    AttributeKeys.osName: .string(device.osName),
                                                    AttributeKeys.osVersion: .string(device.osVersion),
                                                    AttributeKeys.osType: .string("darwin"),
                                                    AttributeKeys
                                                        .deviceModelIdentifier: .string(device.modelIdentifier)]
        return Resource().merging(other: Resource(attributes: attributes))
    }
}
