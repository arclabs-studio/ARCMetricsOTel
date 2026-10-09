import OpenTelemetryApi
import OpenTelemetrySdk
import Testing
@testable import ARCMetricsOTel

@Suite("SessionSampler", .tags(.unit)) struct SessionSamplerTests {
    private let kept = ReferenceSampling.id(sampledAt: 0.5, wantSampled: true)
    private let dropped = ReferenceSampling.id(sampledAt: 0.5, wantSampled: false)

    private func makeSUT(enabled: Bool = true, rate: Double = 0.5) -> SessionSampler {
        SessionSampler(gate: TelemetryGate(TelemetrySettings(isEnabled: enabled, sampleRate: rate)))
    }

    private func parent(sampled: Bool) -> SpanContext {
        SpanContext.create(traceId: TraceId(idHi: 1, idLo: 2),
                           spanId: SpanId(id: 3),
                           traceFlags: TraceFlags().settingIsSampled(sampled),
                           traceState: TraceState())
    }

    private func decide(_ sampler: SessionSampler,
                        parent: SpanContext?,
                        attributes: [String: AttributeValue]) -> Bool {
        sampler.shouldSample(parentContext: parent,
                             traceId: TraceId(idHi: 1, idLo: 2),
                             name: "op",
                             kind: .internal,
                             attributes: attributes,
                             parentLinks: []).isSampled
    }

    @Test("A root span follows its session id") func rootFollowsSession() {
        let sampler = makeSUT()

        #expect(decide(sampler, parent: nil, attributes: [AttributeKeys.sessionID: .string(kept)]))
        #expect(!decide(sampler, parent: nil, attributes: [AttributeKeys.sessionID: .string(dropped)]))
    }

    @Test("A valid parent decides, whatever the session says") func parentDecides() {
        let sampler = makeSUT()

        #expect(decide(sampler, parent: parent(sampled: true), attributes: [AttributeKeys.sessionID: .string(dropped)]))
        #expect(!decide(sampler, parent: parent(sampled: false), attributes: [AttributeKeys.sessionID: .string(kept)]))
    }

    @Test("An invalid parent context is treated as no parent") func invalidParentIsIgnored() {
        let sampler = makeSUT()
        let invalid = SpanContext.create(traceId: TraceId(),
                                         spanId: SpanId(),
                                         traceFlags: TraceFlags(),
                                         traceState: TraceState())

        #expect(decide(sampler, parent: invalid, attributes: [AttributeKeys.sessionID: .string(kept)]))
    }

    @Test("The kill switch drops even a sampled parent and a sampled session, until it is lifted")
    func disabledDropsEverything() {
        let gate = TelemetryGate(TelemetrySettings(isEnabled: false, sampleRate: 1))
        let sampler = SessionSampler(gate: gate)
        let attributes: [String: AttributeValue] = [AttributeKeys.sessionID: .string(kept)]

        #expect(!decide(sampler, parent: parent(sampled: true), attributes: attributes))
        #expect(!decide(sampler, parent: nil, attributes: attributes))

        gate.update(TelemetrySettings(isEnabled: true, sampleRate: 1))
        #expect(decide(sampler, parent: nil, attributes: attributes))
    }

    @Test("A root span without a string session id is dropped, even at rate 1") func missingSessionDrops() {
        let sampler = makeSUT(rate: 1)

        #expect(!decide(sampler, parent: nil, attributes: [:]))
        #expect(!decide(sampler, parent: nil, attributes: [AttributeKeys.sessionID: .int(7)]))
        // Control: the same sampler keeps a root span that does carry a sampled session id.
        #expect(decide(sampler, parent: nil, attributes: [AttributeKeys.sessionID: .string(kept)]))
    }

    @Test("The sampler names itself in SDK diagnostics, independent of its settings") func describesItself() {
        #expect(makeSUT(enabled: true, rate: 1).description == "SessionSampler")
        #expect(makeSUT(enabled: false, rate: 0).description == "SessionSampler")
    }
}
