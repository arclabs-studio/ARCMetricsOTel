import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("Session events", .tags(.integration), .timeLimit(.minutes(1))) struct SessionEventsTests {
    private struct Harness {
        let sut: IntegrationSUT
        let logs: RecordingLogExporter
    }

    private func makeSUT() async throws -> Harness {
        let logs = RecordingLogExporter()
        let sut = try await IntegrationSUT.makeSUT(sessionIDs: ["s-1", "s-2"],
                                                   exporters: ExporterOverride(spans: RecordingSpanExporter(),
                                                                               logs: logs))
        return Harness(sut: sut, logs: logs)
    }

    @Test("Idle rotation emits session.end for the old session and session.start for the new one")
    func idleRotationEmitsEvents() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let sut = harness.sut

        // Given activity, then 16 idle minutes, then more activity
        sut.recordEvent("first")
        sut.clock.advance(by: 16 * 60)
        sut.recordEvent("second")
        await sut.telemetry.flush()

        // Then the session changed between them, with the old one ended and the new one linked to it
        let records = harness.logs.exportedRecords.map(LogSummary.init)
        let ended = try #require(records.first { $0.eventName == EventNames.sessionEnd })
        let started = try #require(records.first { $0.eventName == EventNames.sessionStart && $0.sessionID == "s-2" })
        let second = try #require(records.first { $0.eventName == "second" })
        let first = try #require(records.first { $0.eventName == "first" })

        #expect(ended.sessionID == "s-1")
        #expect(started.previousID == "s-1")
        #expect(first.sessionID == "s-1")
        #expect(second.sessionID == "s-2")
        #expect(second.previousID == "s-1")
        #expect(!records.contains { $0.eventName == EventNames.sessionEnd && $0.sessionID == "s-2" })
    }

    @Test("Activity inside the idle window keeps one session and ends none") func activityKeepsSession() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let sut = harness.sut

        sut.recordEvent("first")
        sut.clock.advance(by: 14 * 60)
        sut.recordEvent("second")
        await sut.telemetry.flush()

        let records = harness.logs.exportedRecords.map(LogSummary.init)
        #expect(records.first { $0.eventName == "second" }?.sessionID == "s-1")
        #expect(!records.contains { $0.eventName == EventNames.sessionEnd })
    }

    @Test("resetSession keeps earlier records on the old session and moves later ones to a new one")
    func resetSessionRotates() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let sut = harness.sut

        sut.recordEvent("before")
        sut.telemetry.resetSession()
        sut.recordEvent("after")
        await sut.telemetry.flush()

        let records = harness.logs.exportedRecords.map(LogSummary.init)
        #expect(records.first { $0.eventName == "before" }?.sessionID == "s-1")
        let after = records.first { $0.eventName == "after" }
        #expect(after?.sessionID == "s-2")
        #expect(after?.previousID == "s-1")
        #expect(records.contains { $0.eventName == EventNames.sessionEnd && $0.sessionID == "s-1" })
        #expect(records.contains {
            $0.eventName == EventNames.sessionStart && $0.sessionID == "s-2" && $0.previousID == "s-1"
        })
    }

    @Test("A cold start links to the session id persisted by the earlier launch")
    func coldStartLinksPersistedSession() async throws {
        let logs = RecordingLogExporter()
        let store = InMemorySessionStore(lastSessionID: "launch-1")
        let sut = try await IntegrationSUT.makeSUT(sessionIDs: ["launch-2"],
                                                   store: store,
                                                   exporters: ExporterOverride(spans: RecordingSpanExporter(),
                                                                               logs: logs))
        defer { sut.cleanUp() }
        sut.recordEvent("hello")
        await sut.telemetry.flush()

        let hello = logs.exportedRecords.map(LogSummary.init).first { $0.eventName == "hello" }
        #expect(hello?.sessionID == "launch-2")
        #expect(hello?.previousID == "launch-1")
        #expect(store.lastSessionID() == "launch-2")
    }
}
