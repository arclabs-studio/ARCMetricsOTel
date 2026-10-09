import ARCMetrics
import Foundation
import OpenTelemetryApi
import Testing
@testable import ARCMetricsOTel

@Suite("Public emitEvent", .tags(.integration), .serialized, .timeLimit(.minutes(1))) struct EmitEventTests {
    private func makeSUT(settings: TelemetrySettings = TelemetrySettings(isEnabled: true, sampleRate: 1)) async throws
    -> ExporterHarness {
        try await ExporterHarness.make(settings: settings)
    }

    @Test("An event exports one record with its name, severity, typed attributes and the session")
    func exportsTypedRecord() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // When an event is emitted with one attribute of each type
        harness.telemetry.emitEvent("cache.purge",
                                    attributes: ["source": "disk", "count": 2, "ratio": 0.5, "warm": false],
                                    severity: .warn)
        await harness.telemetry.flush()

        // Then it is a single warn record carrying the matching OTel attribute types
        let matching = harness.logs.exportedRecords.filter { $0.eventName == "cache.purge" }
        let record = try #require(matching.first)
        #expect(matching.count == 1)
        #expect(record.severity == .warn)
        #expect(record.attributes["source"] == .string("disk"))
        #expect(record.attributes["count"] == .int(2))
        #expect(record.attributes["ratio"] == .double(0.5))
        #expect(record.attributes["warm"] == .bool(false))
        #expect(LogSummary(record).sessionID == "s-1")
    }

    @Test("Each EventSeverity maps to its OpenTelemetry severity", arguments: [(EventSeverity.debug, Severity.debug),
                                                                               (.info, .info),
                                                                               (.warn, .warn),
                                                                               (.error, .error),
                                                                               (.fatal, .fatal)])
    func severityMapping(severity: EventSeverity, expected: Severity) async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        harness.telemetry.emitEvent("sev.test", severity: severity)
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "sev.test" })
        #expect(record.severity == expected)
    }

    @Test("Without a severity or timestamp the record is info, stamped with the clock's now")
    func defaults() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        harness.sut.clock.advance(by: 5)

        harness.telemetry.emitEvent("defaults.test")
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "defaults.test" })
        #expect(record.severity == .info)
        #expect(record.timestamp == Date(timeIntervalSince1970: 1_800_000_005))
    }

    @Test("A given timestamp becomes the record's timestamp") func explicitTimestamp() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }
        let past = Date(timeIntervalSince1970: 1_799_000_000)

        harness.telemetry.emitEvent("stamped.test", timestamp: past)
        await harness.telemetry.flush()

        let record = try #require(harness.logs.exportedRecords.first { $0.eventName == "stamped.test" })
        #expect(record.timestamp == past)
    }

    @Test("A past timestamp never drives session tracking: the session is the one current at the call",
          .tags(.critical))
    func pastTimestampDoesNotDriveSession() async throws {
        let harness = try await makeSUT()
        defer { harness.sut.cleanUp() }

        // Given a first-ever record carrying a timestamp a day in the past
        harness.telemetry.emitEvent("old.event", timestamp: Date(timeIntervalSince1970: 1_799_913_600))
        // When normal activity follows a minute later by the clock
        harness.sut.clock.advance(by: 60)
        harness.sut.recordEvent("later.event")
        await harness.telemetry.flush()

        // Then there is one session, started at the clock's now, and nothing was ended
        let records = harness.logs.exportedRecords
        let starts = records.filter { $0.eventName == "session.start" }
        #expect(starts.count == 1)
        #expect(starts.first?.timestamp == FakeClock.epoch)
        #expect(!records.contains { $0.eventName == "session.end" })
        #expect(records.filter { $0.eventName == "old.event" || $0.eventName == "later.event" }
            .allSatisfy { LogSummary($0).sessionID == "s-1" })
    }

    @Test("With the kill switch off nothing is recorded or sent") func disabledProducesNothing() async throws {
        let harness = try await makeSUT(settings: .disabled)
        defer { harness.sut.cleanUp() }

        harness.telemetry.emitEvent("quiet.event", severity: .fatal)
        await harness.telemetry.flush()

        #expect(harness.logs.exportedRecords.isEmpty)
        #expect(harness.sut.requests.isEmpty)
    }

    @Test("In an unsampled session nothing is exported") func unsampledProducesNothing() async throws {
        let harness = try await makeSUT(settings: TelemetrySettings(isEnabled: true, sampleRate: 0))
        defer { harness.sut.cleanUp() }

        harness.telemetry.emitEvent("dropped.event")
        await harness.telemetry.flush()

        #expect(harness.logs.exportedRecords.isEmpty)
    }
}
