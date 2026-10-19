import ARCMetrics
import ARCMetricsOTelMocks
import Foundation
import OpenTelemetryApi
import SwiftUI
import Testing
import UIKit
@testable import ARCMetricsOTel

@Suite("Screen view tracking", .tags(.integration), .serialized,
       .timeLimit(.minutes(1))) struct ScreenViewTrackingTests {
    // MARK: Through the real pipeline

    @Test("A screen view exports as app.screen.view with the screen name and the session", .tags(.critical))
    func exportsScreenView() async throws {
        let harness = try await ExporterHarness.make()
        defer { harness.sut.cleanUp() }

        ScreenViewTracker(emitter: harness.telemetry).screenAppeared("Home", attributes: ["source": "tab"])
        await harness.telemetry.flush()

        let matching = harness.logs.exportedRecords.filter { $0.eventName == "app.screen.view" }
        let record = try #require(matching.first)
        #expect(matching.count == 1)
        #expect(record.severity == .info)
        #expect(record.timestamp == FakeClock.epoch)
        #expect(record.attributes == ["app.screen.name": .string("Home"), "source": .string("tab"),
                                      "session.id": .string("s-1")])
    }

    @Test("Personal data passed with a screen view is scrubbed by default") func screenViewScrubbed() async throws {
        let harness = try await ExporterHarness.make()
        defer { harness.sut.cleanUp() }

        ScreenViewTracker(emitter: harness.telemetry).screenAppeared("Profile", attributes: ["user.email": "a@b.test"])
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "app.screen.view" })
        #expect(record.attributes["user.email"] == nil)
        #expect(record.attributes["app.screen.name"] == .string("Profile"))
    }

    // MARK: Hosted SwiftUI

    @MainActor private func host(_ view: some View) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        return window
    }

    @Test("A hosted view tracked with trackScreen emits exactly one app.screen.view when it appears")
    @MainActor func hostedViewEmitsOnce() async {
        let recorder = RecordingTelemetryEmitter()
        let window = host(Text("Home").trackScreen("Home").telemetry(recorder))
        defer { window.isHidden = true }

        let appeared = await eventually { !recorder.events.isEmpty }
        try? await Task.sleep(for: .milliseconds(300))

        #expect(appeared)
        #expect(recorder.events.count == 1)
        #expect(recorder.events.first?.name == "app.screen.view")
        #expect(recorder.events.first?.attributes == ["app.screen.name": "Home"])
    }

    @Test("trackScreen passes its attributes along") @MainActor func hostedViewPassesAttributes() async {
        let recorder = RecordingTelemetryEmitter()
        let window = host(Text("Detail").trackScreen("Detail", attributes: ["source": "map"]).telemetry(recorder))
        defer { window.isHidden = true }

        let appeared = await eventually { !recorder.events.isEmpty }

        #expect(appeared)
        #expect(recorder.events.first?.attributes == ["source": "map", "app.screen.name": "Detail"])
    }

    @Test("A tracked view without a telemetry emitter emits nothing and does not crash")
    @MainActor func hostedViewWithoutEmitter() async {
        let recorder = RecordingTelemetryEmitter()
        // Given a tracked view with no emitter beside a control view that has one,
        // so the control proves onAppear fired in this host
        let window = host(VStack {
            Text("Orphan").trackScreen("Orphan")
            Text("Control").trackScreen("Control").telemetry(recorder)
        })
        defer { window.isHidden = true }

        let controlAppeared = await eventually { !recorder.events.isEmpty }
        try? await Task.sleep(for: .milliseconds(300))

        #expect(controlAppeared)
        #expect(recorder.events.compactMap { $0.attributes["app.screen.name"] } == [.string("Control")])
    }
}
