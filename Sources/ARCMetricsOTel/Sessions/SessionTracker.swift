import Foundation

/// Decides which session each recorded activity belongs to.
///
/// - The first activity after launch starts a new session whose `previousID` is the id the
///   ``SessionStore`` persisted, so a cold start always begins a new session.
/// - An activity more than ``SessionPolicy/maxIdle`` after the previous one, or at least
///   ``SessionPolicy/maxLifetime`` after the session began, ends the session and starts the
///   next one, with `previousID` set to the ended session.
/// - A timestamp earlier than the last activity (clock skew) counts as activity and never rotates.
///
/// Owned by ``OTelTelemetry``; not thread-safe on its own.
struct SessionTracker {
    private let policy: SessionPolicy
    private let store: any SessionStore
    private let makeID: @Sendable () -> String

    /// The session in force, or `nil` before the first activity.
    private(set) var current: Session?

    init(policy: SessionPolicy, store: any SessionStore, makeID: @escaping @Sendable () -> String) {
        self.policy = policy
        self.store = store
        self.makeID = makeID
    }

    /// Records activity at `now` and returns the session it belongs to.
    mutating func touch(at now: Date) -> SessionTransition {
        guard var session = current else {
            return start(at: now, previousID: store.lastSessionID(), ending: nil)
        }
        if isExpired(session, at: now) {
            return start(at: now, previousID: session.id, ending: session)
        }
        session.lastActivityAt = max(session.lastActivityAt, now)
        current = session
        return SessionTransition(current: session, ended: nil, didStart: false)
    }

    /// Ends the current session at `now` and starts a new one, as if it had expired.
    mutating func reset(at now: Date) -> SessionTransition {
        guard let session = current else {
            return touch(at: now)
        }
        return start(at: now, previousID: session.id, ending: session)
    }
}

// MARK: - Rotation

private extension SessionTracker {
    func isExpired(_ session: Session, at now: Date) -> Bool {
        now.timeIntervalSince(session.lastActivityAt) > policy.maxIdle.timeInterval
            || now.timeIntervalSince(session.startedAt) >= policy.maxLifetime.timeInterval
    }

    mutating func start(at now: Date, previousID: String?, ending ended: Session?) -> SessionTransition {
        let session = Session(id: makeID(), previousID: previousID, startedAt: now, lastActivityAt: now)
        store.save(sessionID: session.id)
        current = session
        return SessionTransition(current: session, ended: ended, didStart: true)
    }
}
