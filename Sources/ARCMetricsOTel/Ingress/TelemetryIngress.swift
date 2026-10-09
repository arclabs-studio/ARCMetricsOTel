/// The FIFO queue from synchronous call sites into the ``OTelTelemetry`` actor.
///
/// Bounded: once `capacity` commands are waiting, new ones are dropped (the oldest are kept,
/// so a span's start is never dropped in favour of its end). Ending a span whose start was
/// dropped is a no-op.
struct TelemetryIngress {
    /// The single consumer's stream.
    let stream: AsyncStream<TelemetryCommand>
    private let continuation: AsyncStream<TelemetryCommand>.Continuation

    init(capacity: Int = 10000) {
        (stream, continuation) = AsyncStream.makeStream(of: TelemetryCommand.self,
                                                        bufferingPolicy: .bufferingOldest(capacity))
    }

    /// Enqueues `command`. Returns `false` when it was dropped (queue full or finished).
    @discardableResult func send(_ command: TelemetryCommand) -> Bool {
        if case .enqueued = continuation.yield(command) {
            return true
        }
        return false
    }

    /// Ends the stream once the buffered commands have been consumed.
    func finish() {
        continuation.finish()
    }
}
