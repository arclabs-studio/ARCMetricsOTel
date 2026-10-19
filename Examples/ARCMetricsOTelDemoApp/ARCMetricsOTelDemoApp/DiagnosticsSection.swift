import SwiftUI

/// Simulated MetricKit reports, delivered through the MetricKit bridge.
struct DiagnosticsSection: View {
    let model: DemoModel

    var body: some View {
        Section {
            Button("Simulate a metric report") {
                model.simulateMetricReport()
            }
            Button("Simulate a crash report") {
                model.simulateCrash()
            }
            Button("Simulate a hang report") {
                model.simulateHang()
            }
        } header: {
            Text("MetricKit")
        } footer: {
            Text("Reports describe yesterday, as MetricKit's do, and are sent with the next flush.")
        }
    }
}

#Preview {
    Form {
        DiagnosticsSection(model: DemoModel())
    }
}
