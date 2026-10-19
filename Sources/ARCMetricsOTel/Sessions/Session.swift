import Foundation

/// One telemetry session: the id stamped as `session.id` on every record.
struct Session: Equatable {
    /// `session.id`.
    let id: String

    /// `session.previous_id`: the session this one replaced, if any.
    let previousID: String?

    /// When the session began.
    let startedAt: Date

    /// The most recent activity recorded in this session.
    var lastActivityAt: Date
}
