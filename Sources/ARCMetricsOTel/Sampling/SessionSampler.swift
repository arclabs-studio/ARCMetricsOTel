import OpenTelemetryApi
import OpenTelemetrySdk

/// The tracer's sampler: keeps or drops spans by session.
///
/// In order: drop everything while the kill switch is off; follow the parent's decision when
/// the span has a valid parent; otherwise sample on the `session.id` start attribute through
/// ``TelemetryGate/isSampled(sessionID:)``. A root span without a `session.id` is dropped.
final class SessionSampler: Sampler, Sendable {
    private let gate: TelemetryGate

    init(gate: TelemetryGate) {
        self.gate = gate
    }

    var description: String {
        "SessionSampler"
    }

    // The signature is upstream's `Sampler` requirement.
    // swiftlint:disable:next function_parameter_count
    func shouldSample(parentContext: SpanContext?,
                      traceId _: TraceId,
                      name _: String,
                      kind _: SpanKind,
                      attributes: [String: AttributeValue],
                      parentLinks _: [SpanData.Link]) -> any Decision {
        guard gate.isEnabled else {
            return SamplingDecision.drop
        }
        if let parentContext, parentContext.isValid {
            return parentContext.isSampled ? SamplingDecision.record : SamplingDecision.drop
        }
        guard case let .string(sessionID)? = attributes[AttributeKeys.sessionID] else {
            return SamplingDecision.drop
        }
        return gate.isSampled(sessionID: sessionID) ? SamplingDecision.record : SamplingDecision.drop
    }
}
