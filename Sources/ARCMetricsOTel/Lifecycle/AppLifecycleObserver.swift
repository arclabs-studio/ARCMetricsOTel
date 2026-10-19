import Foundation
import Synchronization

/// Records app lifecycle transitions as `device.app.lifecycle` events, and flushes telemetry
/// when the app moves to the background.
///
/// ```swift
/// let lifecycle = AppLifecycleObserver(telemetry: telemetry)
/// Task { await lifecycle.run() }
/// ```
///
/// Each event carries `ios.app.state`. After the `background` event, the observer starts
/// ``OTelTelemetry/flush()``, so what was recorded so far is sent right away. It holds no
/// background task: if the system suspends the app first, the disk buffer sends the rest on a
/// later launch. `terminate` is recorded but not flushed.
public final class AppLifecycleObserver: Sendable {
    private let telemetry: OTelTelemetry
    private let states: AsyncStream<AppLifecycleState>
    private let hasRun = Mutex(false)

    /// Starts observing `source`. Transitions from now on are kept until ``run()`` records them.
    public init(telemetry: OTelTelemetry, source: any LifecycleEventSource = NotificationLifecycleSource()) {
        self.telemetry = telemetry
        states = source.states()
    }

    /// Records transitions until the source's stream finishes or the task is cancelled.
    ///
    /// Call it once; later calls return immediately, so cancelling it stops the observer for good.
    public func run() async {
        guard hasRun.claimFirst() else { return }
        // A flush can block for the export timeout. It runs beside the loop, so transitions that
        // follow are still recorded (and timestamped) as they happen; `run()` returns once both
        // the stream and any flush in progress have finished.
        await withDiscardingTaskGroup { group in
            for await state in states {
                telemetry.emitEvent(name: EventNames.lifecycle,
                                    attributes: [AttributeKeys.appState: .string(state.rawValue)],
                                    severity: .info)
                if state == .background {
                    group.addTask { await self.telemetry.flush() }
                }
            }
        }
    }
}
