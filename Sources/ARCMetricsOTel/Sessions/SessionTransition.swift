/// The result of recording activity: the session now in force, and the one that just ended.
struct SessionTransition: Equatable {
    /// The session to stamp on the activity.
    let current: Session

    /// The session that ended to make room for ``current``, if a rotation happened.
    let ended: Session?

    /// Whether ``current`` began with this activity.
    let didStart: Bool
}
