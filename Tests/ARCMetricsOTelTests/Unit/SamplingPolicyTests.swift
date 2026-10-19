import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("SamplingPolicy", .tags(.unit)) struct SamplingPolicyTests {
    struct Vector: Sendable, CustomTestStringConvertible {
        let input: String
        let hash: UInt64
        var testDescription: String {
            "\"\(input)\""
        }
    }

    /// Published FNV-1a 64-bit test vectors.
    static let vectors = [Vector(input: "", hash: 0xCBF2_9CE4_8422_2325),
                          Vector(input: "a", hash: 0xAF63_DC4C_8601_EC8C),
                          Vector(input: "foobar", hash: 0x8594_4171_F739_67E8)]

    /// Deterministic, random-looking UUID strings (SplitMix64), so the distribution test never flakes.
    static func uuidStrings(count: Int) -> [String] {
        var state: UInt64 = 0x1234_5678_9ABC_DEF0
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
        return (0 ..< count).map { _ in
            let high = next()
            let low = next()
            let bytes = (0 ..< 16).map { index in
                UInt8(truncatingIfNeeded: (index < 8 ? high : low) >> (UInt64(index % 8) * 8))
            }
            return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
                               bytes[15])).uuidString
        }
    }

    @Test("FNV-1a 64 matches the published vectors", arguments: vectors)
    func fnvMatchesPublishedVectors(_ vector: Vector) {
        #expect(SamplingPolicy.fnv1a64(vector.input.utf8) == vector.hash)
    }

    @Test("Fraction is the top 53 bits of the hash over 2^53") func fractionUsesTopBits() {
        // Oracle: the published hash of "a", shifted and scaled by hand.
        let hashOfA: UInt64 = 0xAF63_DC4C_8601_EC8C
        let expected = Double(hashOfA >> 11) / 9_007_199_254_740_992

        #expect(SamplingPolicy.fraction(for: "a") == expected)
    }

    @Test("Fraction stays in [0, 1)") func fractionIsInUnitInterval() {
        let fractions = Self.uuidStrings(count: 2000).map { SamplingPolicy.fraction(for: $0) }

        #expect(fractions.allSatisfy { $0 >= 0 && $0 < 1 })
        // A constant would also be inside [0, 1): require the values to actually spread out.
        #expect(fractions.contains { $0 < 0.1 })
        #expect(fractions.contains { $0 > 0.9 })
    }

    @Test("Rate 0 keeps no session and rate 1 keeps every session") func extremeRates() {
        let ids = Self.uuidStrings(count: 2000)

        #expect(ids.allSatisfy { !SamplingPolicy.isSampled(sessionID: $0, rate: 0) })
        #expect(ids.allSatisfy { SamplingPolicy.isSampled(sessionID: $0, rate: 1) })
    }

    @Test("Raising the rate only adds sessions") func monotonicSubset() {
        let ids = Self.uuidStrings(count: 5000)

        let atLow = Set(ids.filter { SamplingPolicy.isSampled(sessionID: $0, rate: 0.2) })
        let atHigh = Set(ids.filter { SamplingPolicy.isSampled(sessionID: $0, rate: 0.5) })

        #expect(!atLow.isEmpty)
        #expect(atLow.isSubset(of: atHigh))
        #expect(atHigh.count > atLow.count)
    }

    @Test("The decision is session < rate on the reference fraction") func decisionMatchesReference() {
        for id in Self.uuidStrings(count: 2000) {
            let expected = ReferenceSampling.fraction(id) < 0.37
            #expect(SamplingPolicy.isSampled(sessionID: id, rate: 0.37) == expected)
        }
    }

    @Test("10,000 UUIDs at 0.25 keep a quarter of the sessions, within 2 points") func distributionIsUniform() {
        let ids = Self.uuidStrings(count: 10000)

        let kept = ids.filter { SamplingPolicy.isSampled(sessionID: $0, rate: 0.25) }.count

        let share = Double(kept) / Double(ids.count)
        #expect(abs(share - 0.25) <= 0.02)
    }
}
