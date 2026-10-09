/// Event names this package emits on its own.
enum EventNames {
    static let sessionStart = "session.start"
    static let sessionEnd = "session.end"
    static let crash = "app.crash"
    static let hang = "app.hang"
    static let lifecycle = "device.app.lifecycle"
    static let screenView = "app.screen.view"
}
