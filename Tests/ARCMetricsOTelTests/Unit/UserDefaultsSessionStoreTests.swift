import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("UserDefaultsSessionStore", .tags(.unit)) struct UserDefaultsSessionStoreTests {
    private func makeSUT() -> (store: UserDefaultsSessionStore, suiteName: String) {
        let suiteName = "ARCMetricsOTelTests.\(UUID().uuidString)"
        return (UserDefaultsSessionStore(suiteName: suiteName), suiteName)
    }

    private func clean(_ suiteName: String) {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test("A saved id is read back, also by a fresh store on the same suite") func roundTrip() {
        let (store, suiteName) = makeSUT()
        defer { clean(suiteName) }
        #expect(store.lastSessionID() == nil)

        store.save(sessionID: "session-a")

        #expect(store.lastSessionID() == "session-a")
        #expect(UserDefaultsSessionStore(suiteName: suiteName).lastSessionID() == "session-a")
    }

    @Test("Saving again replaces the earlier id") func saveOverwrites() {
        let (store, suiteName) = makeSUT()
        defer { clean(suiteName) }

        store.save(sessionID: "session-a")
        store.save(sessionID: "session-b")

        #expect(store.lastSessionID() == "session-b")
    }

    @Test("A named suite leaves the standard defaults alone") func suiteIsIsolated() {
        let (store, suiteName) = makeSUT()
        defer { clean(suiteName) }
        let marker = "isolation-\(UUID().uuidString)"

        store.save(sessionID: marker)

        #expect(store.lastSessionID() == marker)
        #expect(UserDefaults.standard.string(forKey: UserDefaultsSessionStore.key) != marker)
    }

    @Test("With no suite name the store persists in the standard defaults") func standardDefaultsFallback() {
        let previous = UserDefaults.standard.object(forKey: UserDefaultsSessionStore.key)
        defer {
            if let previous {
                UserDefaults.standard.set(previous, forKey: UserDefaultsSessionStore.key)
            } else {
                UserDefaults.standard.removeObject(forKey: UserDefaultsSessionStore.key)
            }
        }
        let marker = "standard-\(UUID().uuidString)"

        UserDefaultsSessionStore().save(sessionID: marker)

        #expect(UserDefaults.standard.string(forKey: UserDefaultsSessionStore.key) == marker)
        #expect(UserDefaultsSessionStore().lastSessionID() == marker)
    }
}
