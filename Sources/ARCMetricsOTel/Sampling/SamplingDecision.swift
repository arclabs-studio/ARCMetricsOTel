import OpenTelemetryApi
import OpenTelemetrySdk

/// A sampling decision that adds no attributes.
struct SamplingDecision: Decision {
    let isSampled: Bool

    var attributes: [String: AttributeValue] {
        [:]
    }

    static let record = SamplingDecision(isSampled: true)
    static let drop = SamplingDecision(isSampled: false)
}
