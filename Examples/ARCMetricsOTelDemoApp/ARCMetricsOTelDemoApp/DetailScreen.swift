import ARCMetricsOTel
import SwiftUI

/// A second screen, so screen views can be seen changing.
struct DetailScreen: View {
    var body: some View {
        ContentUnavailableView("Detail screen",
                               systemImage: "rectangle.stack",
                               description: Text("Opening this screen recorded an app.screen.view event named Detail."))
            .navigationTitle("Detail")
            .trackScreen("Detail")
    }
}

#Preview {
    NavigationStack {
        DetailScreen()
    }
}
