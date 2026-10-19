import Foundation

/// A ``SessionStore`` backed by `UserDefaults`.
///
/// `UserDefaults` is not `Sendable`, so the store keeps the suite name and resolves the
/// defaults on every call.
struct UserDefaultsSessionStore: SessionStore {
    /// The defaults key holding the latest session id.
    static let key = "com.arclabs.arcmetricsotel.session.id"

    /// The `UserDefaults` suite, or `nil` for `.standard`.
    let suiteName: String?

    init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    func lastSessionID() -> String? {
        defaults.string(forKey: Self.key)
    }

    func save(sessionID: String) {
        defaults.set(sessionID, forKey: Self.key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
