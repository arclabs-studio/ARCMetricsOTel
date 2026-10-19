import Foundation
import Synchronization
import Testing
@testable import ARCMetricsOTel

/// An attribute scrubber that parks the telemetry actor's thread inside the first record marked `"A"`
/// until the test releases it, so the test decides exactly what is queued behind that record.
private final class ParkingScrubber: Sendable {
    private struct State {
        var entered = false
        var released = false
    }

    private let state = Mutex(State())

    var hasEntered: Bool {
        state.withLock { $0.entered }
    }

    func release() {
        state.withLock { $0.released = true }
    }

    var scrubber: AttributeScrubber {
        AttributeScrubber { [self] attributes in
            if attributes["marker"] == "A" {
                state.withLock { $0.entered = true }
                // Blocks the actor thread on purpose; bounded so a broken test cannot hang the run.
                let deadline = ContinuousClock.now.advanced(by: .seconds(20))
                while !state.withLock({ $0.released }), ContinuousClock.now < deadline {
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
            return attributes
        }
    }
}

@Suite("Acceptance: kill switch and the write path", .tags(.integration, .critical), .serialized,
       .timeLimit(.minutes(1)))
struct KillSwitchBufferTests {
    private let enabled = TelemetrySettings(isEnabled: true, sampleRate: 1)

    // MARK: Commands queued before a discard

    /// Every way a record can enter the queue.
    enum EntryPoint: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case spanStartAndEnd
        case emitEvent
        case completedSpan
        case tracerEvent

        var testDescription: String {
            rawValue
        }

        /// Enqueues a record named "B" through this entry point.
        func enqueueB(on telemetry: OTelTelemetry) {
            switch self {
            case .spanStartAndEnd:
                telemetry.startSpan(id: 2, name: "B", parentID: nil, attributes: [:])
                telemetry.endSpan(id: 2, errorType: nil, attributes: [:])
            case .emitEvent:
                telemetry.emitEvent("B")
            case .completedSpan:
                telemetry.recordSpan(name: "B", attributes: [:], start: Date(), end: Date())
            case .tracerEvent:
                telemetry.tracer.event("B", category: .network, attributes: [:])
            }
        }
    }

    /// Parks the actor in record "A", queues "B" behind it through `entryPoint`, optionally throws and lifts
    /// the kill switch while the actor is parked, then releases "A" and flushes. Returns the names of every
    /// delivered span and event.
    private func deliveredNames(via entryPoint: EntryPoint, throwingKillSwitch: Bool) async throws -> [String] {
        let parking = ParkingScrubber()
        let sut = try await IntegrationSUT.makeSUT(attributeScrubber: parking.scrubber)
        defer { sut.cleanUp() }
        sut.telemetry.emitEvent("A", attributes: ["marker": "A"])
        #expect(await eventually { parking.hasEntered })
        entryPoint.enqueueB(on: sut.telemetry)

        var updates: [Task<Void, Never>] = []
        if throwingKillSwitch {
            // `update` changes the gate before it suspends, so polling the gate shows when each change landed
            // even though the parked actor cannot run the discard yet.
            let telemetry = sut.telemetry
            updates.append(Task { await telemetry.update(.disabled) })
            #expect(await eventually { !telemetry.gate.isEnabled })
            let settings = enabled
            updates.append(Task { await telemetry.update(settings) })
            #expect(await eventually { telemetry.gate.isEnabled })
        }
        parking.release()
        for update in updates {
            await update.value
        }
        await sut.telemetry.flush()
        return sut.deliveredLogs.records.map(\.eventName) + sut.deliveredTraces.spans.map(\.name)
    }

    @Test("(b) Positive control: a record queued behind a busy actor is delivered when nothing was disabled",
          arguments: EntryPoint.allCases)
    func queuedRecordIsDelivered(entryPoint: EntryPoint) async throws {
        let names = try await deliveredNames(via: entryPoint, throwingKillSwitch: false)

        #expect(names.contains("B"))
    }

    @Test("(b) A record queued before disable and enable is never delivered, even though it is handled afterwards",
          arguments: EntryPoint.allCases)
    func queuedRecordDoesNotSurviveKillSwitch(entryPoint: EntryPoint) async throws {
        let names = try await deliveredNames(via: entryPoint, throwingKillSwitch: true)

        #expect(!names.contains("B"))
    }

    // MARK: Records reach the buffer from the actor

    /// Like `IntegrationSUT.makeSUT`, with the batch timer set by the test and the collector unreachable,
    /// so whatever reaches the disk buffer stays there.
    private func makeOfflineSUT(scheduleDelay: TimeInterval) async throws -> IntegrationSUT {
        let testID = UUID().uuidString
        let scratch = TemporaryDirectory()
        let clock = FakeClock()
        let store = InMemorySessionStore()
        StubServer.shared.register(testID: testID, behavior: .offline)
        let configuration = try TestConfiguration.make(headers: [StubServer.testIDHeader: testID],
                                                       settings: enabled)
        var dependencies = IntegrationSUT.makeDependencies(clock: clock,
                                                           store: store,
                                                           sessionIDs: ["session-1"],
                                                           exporters: nil,
                                                           storageRoot: scratch.root)
        dependencies.scheduleDelay = scheduleDelay
        let telemetry = try await OTelBootstrap.configure(configuration, dependencies: dependencies)
        return IntegrationSUT(telemetry: telemetry, testID: testID, scratch: scratch, clock: clock, store: store)
    }

    private func waitForActor(_ sut: IntegrationSUT) async {
        await withCheckedContinuation { continuation in
            _ = sut.telemetry.ingress.send(.barrier(continuation))
        }
    }

    @Test("Records reach the disk buffer once the batch timer fires, with no flush")
    func recordsAreBufferedWhenTheBatchTimerFires() async throws {
        // Given enabled telemetry whose batch timer is 50 ms and whose collector is unreachable
        let sut = try await makeOfflineSUT(scheduleDelay: 0.05)
        defer { sut.cleanUp() }

        // When a span ends and an event is emitted, and nobody flushes
        sut.recordSpan(id: 1, name: "buffered-span")
        sut.recordEvent("buffered-event")
        await waitForActor(sut)

        // Then each signal ends up as a file in its buffer directory
        #expect(await eventually { !TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty })
        #expect(await eventually { !TemporaryDirectory.files(in: sut.logsDirectory).isEmpty })
    }

    @Test("Control: with the batch timer an hour away, records are not on disk before a flush")
    func recordsWaitInMemoryWithoutTimer() async throws {
        // Given enabled telemetry whose batch timer is an hour away
        let sut = try await makeOfflineSUT(scheduleDelay: 3600)
        defer { sut.cleanUp() }

        // When a span ends and an event is emitted, and the actor has processed both
        sut.recordSpan(id: 1, name: "buffered-span")
        sut.recordEvent("buffered-event")
        await waitForActor(sut)

        // Then nothing is on disk yet
        #expect(TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
        #expect(TemporaryDirectory.files(in: sut.logsDirectory).isEmpty)

        // And a flush does put them there (the control is not vacuous)
        await sut.telemetry.flush()
        #expect(!TemporaryDirectory.files(in: sut.tracesDirectory).isEmpty)
    }

    @Test("(b) Records still waiting in memory when telemetry is disabled are never delivered after re-enabling")
    func disableDropsRecordsWaitingInMemory() async throws {
        // Given records the actor has processed but not yet written to disk (batch timer an hour away)
        let sut = try await IntegrationSUT.makeSUT()
        defer { sut.cleanUp() }
        sut.recordSpan(id: 1, name: "waiting-span")
        sut.recordEvent("waiting-event")
        await waitForActor(sut)

        // When the kill switch is thrown and lifted again, with the collector reachable
        await sut.telemetry.update(.disabled)
        await sut.telemetry.update(enabled)
        await sut.telemetry.flush()

        // Then nothing was delivered
        #expect(sut.deliveries.isEmpty)
    }
}
