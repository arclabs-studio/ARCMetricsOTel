import Foundation
import Synchronization
import UIKit

/// Lifecycle transitions from `UIApplication`'s notifications.
public struct NotificationLifecycleSource: LifecycleEventSource {
    private static let states: [AppLifecycleState] = [.active, .inactive, .background, .foreground, .terminate]

    private let center: NotificationCenter

    /// - Parameter center: The center the notifications are posted to.
    public init(center: NotificationCenter = .default) {
        self.center = center
    }

    /// Observes the five lifecycle notifications from this call until the stream ends.
    ///
    /// Uses block observers rather than `notifications(named:)`: a block runs synchronously on the
    /// posting thread, so transitions are yielded in posting order (UIKit posts all five on the
    /// main thread) and observing starts before this method returns. One async sequence per name
    /// would give neither guarantee: back-to-back notifications such as `willResignActive` and
    /// `didEnterBackground` could arrive swapped. The observers are removed when the stream ends,
    /// that is when its consumer is cancelled or the stream is released.
    public func states() -> AsyncStream<AppLifecycleState> {
        let (stream, continuation) = AsyncStream.makeStream(of: AppLifecycleState.self)
        let observers = Observers()
        let center = center
        for state in Self.states {
            observers.observe(Self.notificationName(for: state), on: center) { _ in
                continuation.yield(state)
            }
        }
        continuation.onTermination = { _ in
            observers.removeAll(from: center)
        }
        return stream
    }
}

// MARK: - Notifications

private extension NotificationLifecycleSource {
    static func notificationName(for state: AppLifecycleState) -> Notification.Name {
        switch state {
        case .active:
            UIApplication.didBecomeActiveNotification
        case .inactive:
            UIApplication.willResignActiveNotification
        case .background:
            UIApplication.didEnterBackgroundNotification
        case .foreground:
            UIApplication.willEnterForegroundNotification
        case .terminate:
            UIApplication.willTerminateNotification
        }
    }
}

// MARK: - Observers

private extension NotificationLifecycleSource {
    /// The observer tokens of one stream, removed when it ends.
    final class Observers: Sendable {
        private let tokens = Mutex<[any NSObjectProtocol]>([])

        /// Adds a block observer. The token is created inside the lock, so it never leaves it.
        func observe(_ name: Notification.Name,
                     on center: NotificationCenter,
                     using block: @escaping @Sendable (Notification) -> Void) {
            tokens.withLock { tokens in
                tokens.append(center.addObserver(forName: name, object: nil, queue: nil, using: block))
            }
        }

        func removeAll(from center: NotificationCenter) {
            tokens.withLock { tokens in
                for token in tokens {
                    center.removeObserver(token)
                }
                tokens.removeAll()
            }
        }
    }
}
