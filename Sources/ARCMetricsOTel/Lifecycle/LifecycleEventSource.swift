/// A source of app lifecycle transitions for ``AppLifecycleObserver``.
public protocol LifecycleEventSource: Sendable {
    /// A new stream of transitions, in the order they happen, starting from this call.
    func states() -> AsyncStream<AppLifecycleState>
}
