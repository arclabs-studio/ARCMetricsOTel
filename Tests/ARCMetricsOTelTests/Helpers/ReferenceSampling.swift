/// An independent re-statement of the sampling maths, used only to choose test inputs.
///
/// Written from the published FNV-1a definition (offset basis `0xcbf29ce484222325`, prime
/// `0x100000001b3`), not from the production code, so a bug in `SamplingPolicy` cannot hide behind it.
enum ReferenceSampling {
    static func fnv1a64(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    static func fraction(_ text: String) -> Double {
        Double(fnv1a64(text) >> 11) / 9_007_199_254_740_992
    }

    /// The first generated id whose session is (or is not) kept at `rate`.
    static func id(sampledAt rate: Double, wantSampled: Bool) -> String {
        var index = 0
        while (fraction("ref-\(index)") < rate) != wantSampled {
            index += 1
        }
        return "ref-\(index)"
    }
}
