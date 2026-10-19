import ARCMetrics

/// Records screen views as `app.screen.view` events.
struct ScreenViewTracker {
    let emitter: (any TelemetryEmitting)?

    /// Records that the screen `name` appeared. `app.screen.name` overrides a key of the same
    /// name in `attributes`.
    func screenAppeared(_ name: String, attributes: TraceAttributes) {
        var attributes = attributes
        attributes[AttributeKeys.screenName] = .string(name)
        emitter?.emitEvent(EventNames.screenView, attributes: attributes, severity: .info, timestamp: nil)
    }
}
