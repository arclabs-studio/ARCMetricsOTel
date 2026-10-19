import Foundation

/// Persists the latest session id across launches, so a cold start can set `session.previous_id`.
protocol SessionStore: Sendable {
    /// The id of the most recent session, from this launch or an earlier one.
    func lastSessionID() -> String?

    /// Records `sessionID` as the most recent session.
    func save(sessionID: String)
}
