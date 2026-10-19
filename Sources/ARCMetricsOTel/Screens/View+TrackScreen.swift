import ARCMetrics
import SwiftUI

public extension EnvironmentValues {
    /// Where `trackScreen(_:attributes:)` records screen views. `nil` (the
    /// default) records nothing.
    @Entry var telemetryEmitter: (any TelemetryEmitting)?
}

public extension View {
    /// Sets the emitter that screen views in this hierarchy are recorded with.
    ///
    /// ```swift
    /// RootView()
    ///     .telemetry(telemetry)
    /// ```
    func telemetry(_ emitter: (any TelemetryEmitting)?) -> some View {
        environment(\.telemetryEmitter, emitter)
    }

    /// Records an `app.screen.view` event with `app.screen.name` each time this view appears.
    ///
    /// Uses the emitter set with `telemetry(_:)` higher up; without one it does
    /// nothing. The name and attributes leave the device: use a constant name and no personal data.
    func trackScreen(_ name: String, attributes: TraceAttributes = [:]) -> some View {
        modifier(TrackScreenModifier(name: name, attributes: attributes))
    }
}

/// Records a screen view on appear.
private struct TrackScreenModifier: ViewModifier {
    @Environment(\.telemetryEmitter) private var emitter
    let name: String
    let attributes: TraceAttributes

    func body(content: Content) -> some View {
        content.onAppear {
            ScreenViewTracker(emitter: emitter).screenAppeared(name, attributes: attributes)
        }
    }
}
