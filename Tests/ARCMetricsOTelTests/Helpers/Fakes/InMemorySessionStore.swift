import Synchronization
@testable import ARCMetricsOTel

/// A `SessionStore` that keeps the id in memory, so tests never touch `UserDefaults`.
final class InMemorySessionStore: SessionStore {
    private let state: Mutex<String?>

    init(lastSessionID: String? = nil) {
        state = Mutex(lastSessionID)
    }

    func lastSessionID() -> String? {
        state.withLock { $0 }
    }

    func save(sessionID: String) {
        state.withLock { $0 = sessionID }
    }
}
