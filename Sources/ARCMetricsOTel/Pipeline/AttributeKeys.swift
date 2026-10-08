/// Attribute keys this package emits on its own. Every key here must be non-PII;
/// `AttributeKeysTests` pins the full set the package emits.
enum AttributeKeys {
    static let sessionID = "session.id"
    static let sessionPreviousID = "session.previous_id"
    static let errorType = "error.type"
    static let serviceName = "service.name"
    static let serviceVersion = "service.version"
    static let deploymentEnvironment = "deployment.environment.name"
    static let osName = "os.name"
    static let osVersion = "os.version"
    static let osType = "os.type"
    static let deviceModelIdentifier = "device.model.identifier"
}
