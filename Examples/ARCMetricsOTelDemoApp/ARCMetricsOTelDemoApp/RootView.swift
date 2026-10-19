import SwiftUI

/// Shows the controls once telemetry is running, so the first screen view is recorded.
struct RootView: View {
    let model: DemoModel

    var body: some View {
        switch model.state {
        case .starting:
            ProgressView("Configuring telemetry…")
        case .running:
            ContentView(model: model)
        case let .failed(message):
            ContentUnavailableView("Telemetry unavailable",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        }
    }
}

#Preview {
    RootView(model: DemoModel())
}
