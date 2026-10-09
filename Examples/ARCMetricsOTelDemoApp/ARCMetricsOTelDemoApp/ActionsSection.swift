import SwiftUI

/// Records spans and events, and controls sessions and flushing.
struct ActionsSection: View {
    let model: DemoModel

    var body: some View {
        Section("Record") {
            Button("Run a traced operation") {
                Task { await model.runTracedOperation() }
            }
            Button("Emit an event") {
                model.emitEvent()
            }
            Button("Start a new session") {
                model.resetSession()
            }
            Button("Flush now") {
                Task { await model.flush() }
            }
        }
    }
}

#Preview {
    Form {
        ActionsSection(model: DemoModel())
    }
}
