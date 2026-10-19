import Testing
@testable import ARCMetricsOTel

@Suite("AppLifecycleState", .tags(.unit)) struct AppLifecycleStateTests {
    @Test("Raw values are the OTel ios.app.state strings", arguments: [(AppLifecycleState.active, "active"),
                                                                       (.inactive, "inactive"),
                                                                       (.background, "background"),
                                                                       (.foreground, "foreground"),
                                                                       (.terminate, "terminate")])
    func rawValues(state: AppLifecycleState, expected: String) {
        #expect(state.rawValue == expected)
    }
}
