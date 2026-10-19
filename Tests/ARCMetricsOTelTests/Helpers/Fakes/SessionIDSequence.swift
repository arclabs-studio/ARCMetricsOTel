import Synchronization

/// Hands out a fixed list of session ids, then `exhausted-N`, so a test controls every id.
final class SessionIDSequence: Sendable {
    private let ids: [String]
    private let cursor = Mutex(0)

    init(_ ids: [String]) {
        self.ids = ids
    }

    func next() -> String {
        let index = cursor.withLock { value -> Int in
            defer { value += 1 }
            return value
        }
        return index < ids.count ? ids[index] : "exhausted-\(index)"
    }
}
