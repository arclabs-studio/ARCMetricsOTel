/// Where the demo's telemetry pipeline is.
enum DemoState: Equatable {
    case starting
    case running(endpointHost: String)
    case failed(String)
}

// MARK: - Display

extension DemoState {
    /// The collector's host while running, `nil` otherwise.
    var collectorHost: String? {
        if case let .running(endpointHost) = self {
            return endpointHost
        }
        return nil
    }
}

// MARK: - Sample data

extension DemoState {
    /// For previews.
    static let sampleRunning = DemoState.running(endpointHost: "mac-mini.local")
}
