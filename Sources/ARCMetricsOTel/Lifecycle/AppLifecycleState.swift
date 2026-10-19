/// An app lifecycle transition, named as OpenTelemetry's `ios.app.state` values.
public enum AppLifecycleState: String, Sendable {
    /// The app became active (`didBecomeActive`).
    case active
    /// The app is about to become inactive (`willResignActive`).
    case inactive
    /// The app moved to the background (`didEnterBackground`).
    case background
    /// The app is about to move to the foreground (`willEnterForeground`).
    case foreground
    /// The app is about to terminate (`willTerminate`).
    case terminate
}
