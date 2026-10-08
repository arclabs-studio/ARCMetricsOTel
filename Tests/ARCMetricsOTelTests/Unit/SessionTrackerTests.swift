import Foundation
import Testing
@testable import ARCMetricsOTel

@Suite("SessionTracker", .tags(.unit)) struct SessionTrackerTests {
    private let start = FakeClock.epoch

    private func makeSUT(policy: SessionPolicy = .faro,
                         store: InMemorySessionStore = InMemorySessionStore(),
                         ids: [String] = ["s1", "s2", "s3", "s4"]) -> SessionTracker {
        let sequence = SessionIDSequence(ids)
        return SessionTracker(policy: policy, store: store, makeID: { sequence.next() })
    }

    private func minutes(_ value: Double) -> Date {
        start.addingTimeInterval(value * 60)
    }

    @Test("The first activity starts a session linked to the persisted one") func firstTouchStartsSession() {
        let store = InMemorySessionStore(lastSessionID: "previous-launch")
        var tracker = makeSUT(store: store)

        let transition = tracker.touch(at: start)

        #expect(transition.didStart)
        #expect(transition.ended == nil)
        #expect(transition.current.id == "s1")
        #expect(transition.current.previousID == "previous-launch")
        #expect(transition.current.startedAt == start)
        #expect(transition.current.lastActivityAt == start)
        #expect(store.lastSessionID() == "s1")
        #expect(tracker.current?.id == "s1")
    }

    @Test("A first launch has no previous session") func firstLaunchHasNoPrevious() {
        let store = InMemorySessionStore()
        var tracker = makeSUT(store: store)

        let transition = tracker.touch(at: start)

        #expect(transition.current.id == "s1")
        #expect(transition.current.previousID == nil)
        #expect(store.lastSessionID() == "s1")
    }

    @Test("A cold start with the same store links to the earlier launch") func coldStartLinksToPreviousLaunch() {
        let store = InMemorySessionStore()
        var firstLaunch = makeSUT(store: store, ids: ["launch-1"])
        _ = firstLaunch.touch(at: start)

        var secondLaunch = makeSUT(store: store, ids: ["launch-2"])
        let transition = secondLaunch.touch(at: minutes(1))

        #expect(transition.current.id == "launch-2")
        #expect(transition.current.previousID == "launch-1")
    }

    @Test("Activity 14:59 later keeps the session and refreshes its last activity")
    func activityWithinIdleKeepsSession() {
        var tracker = makeSUT()
        _ = tracker.touch(at: start)

        let transition = tracker.touch(at: start.addingTimeInterval(14 * 60 + 59))

        #expect(!transition.didStart)
        #expect(transition.ended == nil)
        #expect(transition.current.id == "s1")
        #expect(transition.current.lastActivityAt == start.addingTimeInterval(14 * 60 + 59))
    }

    @Test("Exactly the idle limit still keeps the session, because the rule is 'more than'")
    func exactIdleLimitKeeps() {
        var tracker = makeSUT()
        _ = tracker.touch(at: start)

        #expect(tracker.touch(at: minutes(15)).current.id == "s1")
    }

    @Test("Activity 15:01 later ends the session and starts the next one") func idleRotates() {
        let store = InMemorySessionStore()
        var tracker = makeSUT(store: store)
        let first = tracker.touch(at: start).current

        let transition = tracker.touch(at: start.addingTimeInterval(15 * 60 + 1))

        #expect(transition.didStart)
        #expect(transition.ended?.id == first.id)
        #expect(transition.current.id == "s2")
        #expect(transition.current.previousID == "s1")
        #expect(transition.current.startedAt == start.addingTimeInterval(15 * 60 + 1))
        #expect(store.lastSessionID() == "s2")
    }

    @Test("Continuous activity rotates exactly when the session reaches four hours") func lifetimeRotates() {
        var tracker = makeSUT()
        _ = tracker.touch(at: start)

        // Touch every 10 minutes up to 3h50m: never idle, never old enough.
        for step in 1 ... 23 {
            #expect(tracker.touch(at: minutes(Double(step) * 10)).current.id == "s1")
        }
        // 3h59m: still inside the lifetime.
        let beforeLimit = tracker.touch(at: minutes(3 * 60 + 59))
        #expect(!beforeLimit.didStart)
        #expect(beforeLimit.current.id == "s1")

        // 4h00m: the lifetime is reached, even though the user is active.
        let atLimit = tracker.touch(at: minutes(4 * 60))
        #expect(atLimit.didStart)
        #expect(atLimit.ended?.id == "s1")
        #expect(atLimit.current.id == "s2")
        #expect(atLimit.current.previousID == "s1")
    }

    @Test("A timestamp earlier than the last activity never rotates") func clockSkewNeverRotates() {
        var tracker = makeSUT()
        _ = tracker.touch(at: minutes(10))

        let beforeLastActivity = tracker.touch(at: minutes(1))
        let beforeStart = tracker.touch(at: minutes(-30))

        #expect(!beforeLastActivity.didStart)
        #expect(beforeLastActivity.ended == nil)
        #expect(!beforeStart.didStart)
        #expect(beforeStart.current.id == "s1")
    }

    @Test("The policy in force decides, not the Faro defaults") func customPolicy() {
        var tracker = makeSUT(policy: SessionPolicy(maxIdle: .seconds(60), maxLifetime: .seconds(600)))
        _ = tracker.touch(at: start)

        #expect(tracker.touch(at: start.addingTimeInterval(61)).didStart)
        #expect(!tracker.touch(at: start.addingTimeInterval(61 + 30)).didStart)
    }

    @Test("Reset ends the current session and starts a linked one at once") func resetRotates() {
        let store = InMemorySessionStore()
        var tracker = makeSUT(store: store)
        let first = tracker.touch(at: start).current

        let transition = tracker.reset(at: minutes(1))

        #expect(transition.didStart)
        #expect(transition.ended?.id == first.id)
        #expect(transition.current.id == "s2")
        #expect(transition.current.previousID == "s1")
        #expect(transition.current.startedAt == minutes(1))
        #expect(store.lastSessionID() == "s2")
        #expect(tracker.current?.id == "s2")
    }

    @Test("Resetting before any activity starts the first session, linked to the persisted one")
    func resetWithoutSession() {
        let store = InMemorySessionStore(lastSessionID: "earlier-launch")
        var tracker = makeSUT(store: store, ids: ["fresh"])

        let transition = tracker.reset(at: start)

        #expect(transition.didStart)
        #expect(transition.ended == nil)
        #expect(transition.current.id == "fresh")
        #expect(transition.current.previousID == "earlier-launch")
        #expect(store.lastSessionID() == "fresh")
    }
}
