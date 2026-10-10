import ARCMetricsOTel
import SwiftUI

@main
struct ARCMetricsOTelDemoAppApp: App {
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .telemetry(model.telemetry)
                .task { await model.start() }
        }
    }
}
