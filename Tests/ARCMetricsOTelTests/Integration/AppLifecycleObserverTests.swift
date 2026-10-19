import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
import UIKit
@testable import ARCMetricsOTel

@Suite("App lifecycle observer", .tags(.integration), .serialized, .timeLimit(.minutes(1)))
struct AppLifecycleObserverTests {
    private struct Harness {
        let exporters: ExporterHarness
        let source: ScriptedLifecycleSource
        let observer: AppLifecycleObserver

        var sut: IntegrationSUT {
            exporters.sut
        }

        var lifecycleRecords: [ReadableLogRecord] {
            exporters.logs.exportedRecords.filter { $0.eventName == "device.app.lifecycle" }
        }
    }

    private func makeSUT() async throws -> Harness {
        let exporters = try await ExporterHarness.make()
        let source = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: exporters.telemetry, source: source)
        return Harness(exporters: exporters, source: source, observer: observer)
    }

    @Test("Each state becomes an info device.app.lifecycle record with its ios.app.state, in order")
    func recordsEveryState() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given the full set of states, ending with a background that flushes
        let states: [AppLifecycleState] = [.active, .inactive, .foreground, .terminate, .background]
        for state in states {
            harness.source.send(state)
        }
        harness.source.finish()
        await harness.observer.run()
        await harness.exporters.telemetry.flush()

        // Then one record per state, in order, with the literal OTel values
        let records = harness.lifecycleRecords
        #expect(records.count == 5)
        #expect(records.map { $0.attributes["ios.app.state"] }
            == [.string("active"), .string("inactive"), .string("foreground"), .string("terminate"),
                .string("background")])
        #expect(records.allSatisfy { $0.severity == .info })
        #expect(records.allSatisfy { LogSummary($0).sessionID == "s-1" })
    }

    @Test("The source is asked for states in init, so states sent before run() are not lost") func subscribesInInit() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        #expect(harness.source.statesCallCount == 1)
        harness.source.send(.active)
        harness.source.finish()
        await harness.observer.run()
        await harness.exporters.telemetry.flush()

        #expect(harness.source.statesCallCount == 1)
        #expect(harness.lifecycleRecords.count == 1)
    }

    @Test("run() returns when the source stream finishes") func returnsWhenSourceFinishes() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let observer = harness.observer

        harness.source.finish()

        #expect(await completes { await observer.run() })
    }

    @Test("A second run() returns immediately and does not consume") func secondRunReturnsImmediately() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let observer = harness.observer
        let first = Task { await observer.run() }
        // Given the first run() is consuming: a state goes through before the second call, so the
        // two calls cannot race for the claim.
        harness.source.send(.active)
        let consuming = await flushing(harness.exporters.telemetry) { harness.lifecycleRecords.count == 1 }

        // When run() is called again
        let returned = await completes { await observer.run() }
        harness.source.send(.inactive)
        let delivered = await flushing(harness.exporters.telemetry) { harness.lifecycleRecords.count == 2 }
        harness.source.finish()
        await first.value

        // Then it came back at once, and each state was recorded exactly once, by the first run
        #expect(consuming)
        #expect(returned)
        #expect(delivered)
        #expect(harness.lifecycleRecords.count == 2)
    }

    @Test("Entering the background flushes to the network without an explicit flush", .tags(.critical))
    func backgroundFlushesToNetwork() async throws {
        // Given the real stubbed transport (the harness timers are an hour, so only a flush delivers)
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        let source = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: sut.telemetry, source: source)

        // When the app goes to the background
        source.send(.inactive)
        source.send(.background)
        source.finish()
        await observer.run()

        // Then both records were delivered without the test flushing
        let delivered = sut.deliveredLogs.records.filter { $0.eventName == "device.app.lifecycle" }
        #expect(delivered.map { $0.attributes["ios.app.state"] } == ["inactive", "background"])
        #expect(delivered.allSatisfy { $0.severityNumber == 9 })
    }

    @Test("States other than background do not trigger a delivery") func otherStatesDoNotFlush() async throws {
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        let source = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: sut.telemetry, source: source)

        for state in [AppLifecycleState.active, .inactive, .foreground, .terminate] {
            source.send(state)
        }
        source.finish()
        await observer.run()

        #expect(sut.deliveries.isEmpty)
    }

    @Test("End to end: notifications on a private center become lifecycle records, background delivers")
    func endToEndWithNotifications() async throws {
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        let center = NotificationCenter()
        let observer = AppLifecycleObserver(telemetry: sut.telemetry,
                                            source: NotificationLifecycleSource(center: center))
        let task = Task { await observer.run() }

        // When the app resigns active and enters the background
        center.post(name: UIApplication.willResignActiveNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let delivered = await eventually {
            sut.deliveredLogs.records.filter { $0.eventName == "device.app.lifecycle" }.count == 2
        }
        task.cancel()
        await task.value

        // Then both reached the network in order
        #expect(delivered)
        let states = sut.deliveredLogs.records.filter { $0.eventName == "device.app.lifecycle" }
            .map { $0.attributes["ios.app.state"] }
        #expect(states == ["inactive", "background"])
    }

    @Test("A transition after background is recorded while the background flush is still running")
    func flushDoesNotDelayLaterTransitions() async throws {
        // Given a collector that never answers, so the background flush blocks until it times out
        let sut = try await IntegrationSUT.makeSUT(behavior: .hang)
        defer { sut.cleanUp() }
        let source = ScriptedLifecycleSource()
        let observer = AppLifecycleObserver(telemetry: sut.telemetry, source: source)
        let running = Task { await observer.run() }
        source.send(.background)
        #expect(await eventually { !sut.requests.isEmpty })
        let readsDuringFlush = sut.clock.reads

        // When the app returns to the foreground while that flush is still waiting
        source.send(.foreground)

        // Then the transition is recorded now (its timestamp is read), not after the flush gives up
        // (10 s per stage)
        #expect(await eventually(timeout: .seconds(8)) { sut.clock.reads > readsDuringFlush })
        source.finish()
        await running.value
    }
}
