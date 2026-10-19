import ARCMetrics
import ARCMetricsOTelMocks
import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Screen view tracker", .tags(.unit), .timeLimit(.minutes(1))) struct ScreenViewTrackerTests {
    private func makeSUT() -> (tracker: ScreenViewTracker, recorder: RecordingTelemetryEmitter) {
        let recorder = RecordingTelemetryEmitter()
        return (ScreenViewTracker(emitter: recorder), recorder)
    }

    @Test("Appearing emits one info app.screen.view with the screen name, stamped by the pipeline")
    func emitsScreenView() throws {
        let (tracker, recorder) = makeSUT()

        tracker.screenAppeared("Home", attributes: [:])

        let event = try #require(recorder.events.first)
        #expect(recorder.events.count == 1)
        #expect(event.name == "app.screen.view")
        #expect(event.severity == .info)
        #expect(event.timestamp == nil)
        #expect(event.attributes == ["app.screen.name": "Home"])
    }

    @Test("The screen name is carried verbatim", arguments: ["Home", "Restaurant Detail", "Añadir.Visita", "a/b"])
    func carriesName(name: String) throws {
        let (tracker, recorder) = makeSUT()

        tracker.screenAppeared(name, attributes: [:])

        #expect(try #require(recorder.events.first).attributes["app.screen.name"] == .string(name))
    }

    @Test("Caller attributes are kept, with their types, next to the screen name") func keepsCallerAttributes() throws {
        let (tracker, recorder) = makeSUT()

        tracker.screenAppeared("Detail", attributes: ["source": "map", "rank": 3, "ratio": 0.5, "cached": true])

        let event = try #require(recorder.events.first)
        #expect(event.attributes == ["source": "map", "rank": 3, "ratio": 0.5, "cached": true,
                                     "app.screen.name": "Detail"])
    }

    @Test("The screen name wins over a caller-supplied app.screen.name") func screenNameWins() throws {
        let (tracker, recorder) = makeSUT()

        tracker.screenAppeared("Real", attributes: ["app.screen.name": "Spoofed", "other": 1])

        #expect(try #require(recorder.events.first).attributes == ["app.screen.name": "Real", "other": 1])
    }

    @Test("Every appearance emits, including a repeat of the same screen") func everyAppearanceEmits() {
        let (tracker, recorder) = makeSUT()

        tracker.screenAppeared("Home", attributes: [:])
        tracker.screenAppeared("Settings", attributes: [:])
        tracker.screenAppeared("Home", attributes: [:])

        #expect(recorder.events.compactMap { $0.attributes["app.screen.name"] }
            == [.string("Home"), .string("Settings"), .string("Home")])
    }

    @Test("Without an emitter nothing is emitted and nothing crashes") func nilEmitterIsInert() {
        let recorder = RecordingTelemetryEmitter()

        ScreenViewTracker(emitter: nil).screenAppeared("Home", attributes: ["a": 1])
        ScreenViewTracker(emitter: recorder).screenAppeared("Control", attributes: [:])

        #expect(recorder.events.count == 1)
    }
}
