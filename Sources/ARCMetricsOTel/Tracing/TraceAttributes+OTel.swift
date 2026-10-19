import ARCMetrics
import OpenTelemetryApi

extension [String: TraceAttributeValue] {
    /// The same attributes as OpenTelemetry values, keeping their types.
    var otelAttributes: [String: AttributeValue] {
        mapValues { value in
            switch value {
            case let .string(string):
                .string(string)
            case let .int(int):
                .int(int)
            case let .double(double):
                .double(double)
            case let .bool(bool):
                .bool(bool)
            }
        }
    }
}
