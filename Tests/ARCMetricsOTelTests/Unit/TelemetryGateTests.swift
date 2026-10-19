import Testing
@testable import ARCMetricsOTel

@Suite("TelemetryGate", .tags(.unit)) struct TelemetryGateTests {
    private func makeSUT(_ settings: TelemetrySettings) -> TelemetryGate {
        TelemetryGate(settings)
    }

    @Test("An update takes effect for the very next read") func updateIsImmediate() {
        // Given a gate that starts disabled
        let gate = makeSUT(.disabled)
        let sampled = ReferenceSampling.id(sampledAt: 0.5, wantSampled: true)
        #expect(!gate.isSampled(sessionID: sampled))

        // When it is enabled
        gate.update(TelemetrySettings(isEnabled: true, sampleRate: 0.5))

        // Then the settings and the decision change at once
        #expect(gate.isEnabled)
        #expect(gate.settings == TelemetrySettings(isEnabled: true, sampleRate: 0.5))
        #expect(gate.isSampled(sessionID: sampled))
    }

    @Test("A disabled gate keeps nothing, even at rate 1") func disabledKeepsNothing() {
        let gate = makeSUT(TelemetrySettings(isEnabled: false, sampleRate: 1))
        let id = ReferenceSampling.id(sampledAt: 1, wantSampled: true)

        #expect(!gate.isEnabled)
        #expect(!gate.isSampled(sessionID: id))

        // Control: the very same id is kept once the switch is on.
        gate.update(TelemetrySettings(isEnabled: true, sampleRate: 1))
        #expect(gate.isSampled(sessionID: id))
    }

    @Test("An enabled gate follows the session fraction") func enabledFollowsFraction() {
        let gate = makeSUT(TelemetrySettings(isEnabled: true, sampleRate: 0.5))
        let kept = ReferenceSampling.id(sampledAt: 0.5, wantSampled: true)
        let dropped = ReferenceSampling.id(sampledAt: 0.5, wantSampled: false)

        #expect(gate.isSampled(sessionID: kept))
        #expect(!gate.isSampled(sessionID: dropped))
    }

    @Test("Lowering the rate drops a session that was kept") func rateIsReadLive() {
        let gate = makeSUT(TelemetrySettings(isEnabled: true, sampleRate: 0.5))
        let id = ReferenceSampling.id(sampledAt: 0.5, wantSampled: true)
        #expect(gate.isSampled(sessionID: id))

        gate.update(TelemetrySettings(isEnabled: true, sampleRate: 0))

        #expect(!gate.isSampled(sessionID: id))
    }

    private let enabled = TelemetrySettings(isEnabled: true, sampleRate: 1)

    @Test("An enabled gate with nothing to discard allows export") func allowsExportWhenEnabled() {
        let gate = makeSUT(enabled)

        #expect(gate.allowsExport)
        #expect(gate.pendingDiscard == nil)
    }

    @Test("Disabling closes exports and requests a discard") func disableRequestsDiscard() {
        let gate = makeSUT(enabled)

        gate.update(.disabled)

        #expect(!gate.allowsExport)
        #expect(gate.pendingDiscard == 1)
    }

    @Test("Enabling again does not reopen exports until the discard is carried out") func reEnableKeepsExportsClosed() {
        let gate = makeSUT(enabled)
        gate.update(.disabled)

        gate.update(enabled)

        #expect(gate.isEnabled)
        #expect(!gate.allowsExport)
        #expect(gate.pendingDiscard == 1)

        gate.completeDiscard(1)

        #expect(gate.allowsExport)
        #expect(gate.pendingDiscard == nil)
    }

    @Test("A disable that arrives during a discard stays pending after the first one completes")
    func laterDisableStaysPending() {
        let gate = makeSUT(enabled)
        gate.update(.disabled)
        gate.update(enabled)
        gate.update(.disabled)
        gate.update(enabled)
        #expect(gate.pendingDiscard == 2)

        gate.completeDiscard(1)

        #expect(gate.pendingDiscard == 2)
        #expect(!gate.allowsExport)

        gate.completeDiscard(2)

        #expect(gate.pendingDiscard == nil)
        #expect(gate.allowsExport)
    }

    @Test("A disabled gate never allows export, even with no discard outstanding") func disabledNeverExports() {
        let gate = makeSUT(.disabled)

        #expect(!gate.allowsExport)
        #expect(gate.pendingDiscard == nil)
    }

    @Test("Completing an older discard never lowers the completed mark") func completionIsMonotonic() {
        let gate = makeSUT(enabled)
        gate.update(.disabled)
        gate.update(.disabled)
        gate.completeDiscard(2)

        gate.completeDiscard(1)

        #expect(gate.pendingDiscard == nil)
    }
}
