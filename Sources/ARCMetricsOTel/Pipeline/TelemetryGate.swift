import Synchronization

/// The live ``TelemetrySettings``, readable from any thread.
///
/// Upstream calls the sampler, the persistence `exportCondition` and the exporters
/// synchronously from its own threads, so the kill switch and sample rate cannot live only
/// inside the ``OTelTelemetry`` actor. A `Mutex` makes this a checked `Sendable` type.
///
/// Disabling telemetry also requests a discard of everything already batched or buffered.
/// Exports stay closed until ``OTelTelemetry`` has carried the discard out, even if telemetry is
/// enabled again in the meantime, so concurrent updates can never let the old data through.
final class TelemetryGate: Sendable {
    private struct State {
        var settings: TelemetrySettings
        /// Discards requested by disabling, and the latest one carried out.
        var discardsRequested = 0
        var discardsCompleted = 0
    }

    private let state: Mutex<State>

    init(_ settings: TelemetrySettings) {
        state = Mutex(State(settings: settings))
    }

    /// The settings in force.
    var settings: TelemetrySettings {
        state.withLock { $0.settings }
    }

    /// The kill switch.
    var isEnabled: Bool {
        settings.isEnabled
    }

    /// Whether batches may leave the device: enabled, with no discard outstanding.
    var allowsExport: Bool {
        state.withLock { $0.settings.isEnabled && $0.discardsCompleted == $0.discardsRequested }
    }

    /// Replaces the settings. Takes effect for the very next record or export. Disabling requests
    /// a discard.
    func update(_ settings: TelemetrySettings) {
        state.withLock { state in
            state.settings = settings
            if !settings.isEnabled {
                state.discardsRequested += 1
            }
        }
    }

    /// The latest discard requested, if one is outstanding.
    var pendingDiscard: Int? {
        state.withLock { $0.discardsCompleted == $0.discardsRequested ? nil : $0.discardsRequested }
    }

    /// Records that every discard up to `discard` has been carried out.
    func completeDiscard(_ discard: Int) {
        state.withLock { $0.discardsCompleted = max($0.discardsCompleted, discard) }
    }

    /// Whether a record of `sessionID` is kept: telemetry enabled and the session sampled.
    func isSampled(sessionID: String) -> Bool {
        let settings = settings
        return settings.isEnabled && SamplingPolicy.isSampled(sessionID: sessionID, rate: settings.sampleRate)
    }
}
