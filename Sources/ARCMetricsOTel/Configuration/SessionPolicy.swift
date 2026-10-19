/// When a telemetry session ends and the next one begins.
///
/// A session ends after ``maxIdle`` without any recorded activity, or once it has lasted
/// ``maxLifetime``, whichever comes first. Every cold start begins a new session.
public struct SessionPolicy: Sendable, Equatable {
    /// The longest gap between two recorded activities that keeps a session alive.
    public let maxIdle: Duration

    /// The longest a session may last, however active it is.
    public let maxLifetime: Duration

    /// Creates a session policy.
    ///
    /// - Parameters:
    ///   - maxIdle: The inactivity that ends a session.
    ///   - maxLifetime: The total duration that ends a session.
    public init(maxIdle: Duration, maxLifetime: Duration) {
        self.maxIdle = maxIdle
        self.maxLifetime = maxLifetime
    }

    /// Grafana Faro's rules: 15 minutes of inactivity or 4 hours in total.
    public static let faro = SessionPolicy(maxIdle: .seconds(15 * 60), maxLifetime: .seconds(4 * 60 * 60))
}
