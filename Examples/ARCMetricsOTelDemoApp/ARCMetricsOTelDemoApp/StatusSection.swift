import SwiftUI

/// Where telemetry goes and what the last action did.
struct StatusSection: View {
    let state: DemoState
    let lastAction: String
    let actionCount: Int

    var body: some View {
        Section("Status") {
            LabeledContent("Collector", value: state.collectorHost ?? "—")
                .accessibilityValue(state.collectorHost ?? "None")
            if !lastAction.isEmpty {
                LabeledContent("Last action", value: lastAction)
            }
        }
        .onChange(of: actionCount) {
            AccessibilityNotification.Announcement(lastAction).post()
        }
    }
}

#Preview {
    Form {
        StatusSection(state: .sampleRunning, lastAction: "Flushed", actionCount: 1)
    }
}
