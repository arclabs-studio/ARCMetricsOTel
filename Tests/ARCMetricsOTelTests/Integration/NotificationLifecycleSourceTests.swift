import Foundation
import Testing
import UIKit
@testable import ARCMetricsOTel

@Suite("Notification lifecycle source", .tags(.integration), .serialized, .timeLimit(.minutes(1)))
struct NotificationLifecycleSourceTests {
    private struct Harness {
        let center: NotificationCenter
        let source: NotificationLifecycleSource
    }

    /// A private center, never `.default`, so no other test or UIKit itself can post into the stream.
    private func makeSUT() -> Harness {
        let center = NotificationCenter()
        return Harness(center: center, source: NotificationLifecycleSource(center: center))
    }

    /// Reads `count` states, or returns what it has read when `timeout` passes.
    private func collect(_ count: Int,
                         from stream: AsyncStream<AppLifecycleState>,
                         timeout: Duration = .seconds(10)) async -> [AppLifecycleState] {
        await withTaskGroup(of: [AppLifecycleState]?.self) { group in
            group.addTask {
                var states: [AppLifecycleState] = []
                for await state in stream {
                    states.append(state)
                    if states.count == count {
                        break
                    }
                }
                return states
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first ?? []
        }
    }

    @Test("Each UIApplication notification maps to its state",
          arguments: [(UIApplication.didBecomeActiveNotification, AppLifecycleState.active),
                      (UIApplication.willResignActiveNotification, .inactive),
                      (UIApplication.didEnterBackgroundNotification, .background),
                      (UIApplication.willEnterForegroundNotification, .foreground),
                      (UIApplication.willTerminateNotification, .terminate)])
    func mapsNotification(name: Notification.Name, expected: AppLifecycleState) async {
        // Given a stream, and a post made immediately after states() with nothing awaited in between
        let harness = makeSUT()
        let stream = harness.source.states()
        harness.center.post(name: name, object: nil)

        // Then the post was not missed
        #expect(await collect(1, from: stream) == [expected])
    }

    @Test("A rapid back-to-back sequence is yielded in exactly the posted order") func preservesOrder() async {
        let harness = makeSUT()
        let stream = harness.source.states()
        let cycle: [(Notification.Name, AppLifecycleState)] = [(UIApplication.willResignActiveNotification, .inactive),
                                                               (UIApplication.didEnterBackgroundNotification,
                                                                .background),
                                                               (UIApplication.willEnterForegroundNotification,
                                                                .foreground),
                                                               (UIApplication.didBecomeActiveNotification, .active)]

        // When the cycle is posted ten times with no suspension between posts
        for _ in 0 ..< 10 {
            for (name, _) in cycle {
                harness.center.post(name: name, object: nil)
            }
        }

        // Then the states arrive in the same order, none lost or reordered
        let expected = Array(repeating: cycle.map(\.1), count: 10).flatMap(\.self)
        #expect(await collect(expected.count, from: stream) == expected)
    }

    @Test("Unrelated notifications are ignored") func ignoresOtherNotifications() async {
        let harness = makeSUT()
        let stream = harness.source.states()

        harness.center.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        harness.center.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        harness.center.post(name: Notification.Name("com.example.unrelated"), object: nil)
        harness.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        #expect(await collect(2, from: stream) == [.active, .background])
    }

    @Test("Every states() call gets its own stream that receives each notification") func independentStreams() async {
        let harness = makeSUT()
        let first = harness.source.states()
        let second = harness.source.states()

        harness.center.post(name: UIApplication.willTerminateNotification, object: nil)

        #expect(await collect(1, from: first) == [.terminate])
        #expect(await collect(1, from: second) == [.terminate])
    }

    // Observer removal is not tested here. The only oracle is a NotificationCenter subclass that counts
    // removeObserver(_:) calls, and such a subclass must restate NotificationCenter's inherited
    // `@unchecked Sendable`, which this codebase forbids. It was verified once with that subclass
    // (2026-10-09): releasing an unconsumed stream and cancelling its consumer each removed all five
    // observers, and both checks failed with the removal disabled.
}
