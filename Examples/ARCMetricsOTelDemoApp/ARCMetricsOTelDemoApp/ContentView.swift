import ARCMetricsOTel
import SwiftUI

/// The demo's controls screen.
struct ContentView: View {
    let model: DemoModel

    var body: some View {
        NavigationStack {
            Form {
                StatusSection(state: model.state, lastAction: model.lastAction, actionCount: model.actionCount)
                SettingsSection(model: model)
                ActionsSection(model: model)
                DiagnosticsSection(model: model)
                Section {
                    NavigationLink("Open the detail screen", value: DemoRoute.detail)
                }
            }
            .navigationTitle("ARCMetricsOTel")
            .navigationDestination(for: DemoRoute.self) { _ in
                DetailScreen()
            }
            .trackScreen("Controls")
        }
    }
}

#Preview {
    ContentView(model: DemoModel())
}
