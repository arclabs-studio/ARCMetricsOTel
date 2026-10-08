/// Session-consistent head sampling.
///
/// A session is kept when the fraction derived from its id is below the sample rate. The
/// fraction comes from a fixed hash (64-bit FNV-1a), never `Hasher`, which is seeded per
/// process — so every record of a session, on every launch, gets the same answer, and raising
/// the rate only adds sessions, never drops ones already kept.
enum SamplingPolicy {
    /// 64-bit FNV-1a of `bytes`.
    static func fnv1a64(_ bytes: some Sequence<UInt8>) -> UInt64 {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01B3
        }
        return hash
    }

    /// The session's position in `[0, 1)`: the top 53 bits of its hash over 2⁵³.
    static func fraction(for sessionID: String) -> Double {
        Double(fnv1a64(sessionID.utf8) >> 11) / 0x1p53
    }

    /// Whether the session is kept at `rate`.
    static func isSampled(sessionID: String, rate: Double) -> Bool {
        fraction(for: sessionID) < rate
    }
}
