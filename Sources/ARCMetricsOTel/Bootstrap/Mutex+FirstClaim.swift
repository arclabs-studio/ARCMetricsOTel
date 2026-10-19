import Synchronization

extension Mutex where Value == Bool {
    /// Sets the flag and returns `true` only for the first caller.
    func claimFirst() -> Bool {
        withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}
