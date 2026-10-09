import SwiftUI

/// The kill switch and the session sample rate, as remote flags would set them.
struct SettingsSection: View {
    @Bindable var model: DemoModel

    var body: some View {
        Section {
            Toggle("Telemetry enabled", isOn: $model.isEnabled)
            LabeledContent("Sample rate", value: model.sampleRate.formatted(.percent))
                .accessibilityHidden(true)
            Slider(value: $model.sampleRate, in: 0 ... 1, step: 0.1) {
                Text("Sample rate")
            }
        } header: {
            Text("Remote settings")
        } footer: {
            Text("Turning telemetry off discards anything not yet sent. The sample rate applies to new sessions.")
        }
    }
}

#Preview {
    Form {
        SettingsSection(model: DemoModel())
    }
}
