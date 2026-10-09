import ARCMetrics
import Foundation
import OpenTelemetryApi

/// A running telemetry pipeline. Create it with ``OTelBootstrap/configure(_:)`` and keep it for
/// the app's lifetime.
///
/// Records flow from synchronous call sites through a FIFO queue into this actor, which owns
/// every OpenTelemetry object. Each record is stamped with `session.id` (and
/// `session.previous_id` when there is one); a session's first record emits `session.start`,
/// and a rotation emits `session.end` for the old session before it.
///
/// The kill switch is enforced at every stage: while ``TelemetrySettings/isEnabled`` is `false`
/// nothing is built, no record is created, the sampler drops, the disk buffer stops exporting,
/// and anything already batched or buffered is discarded rather than sent — even if telemetry is
/// enabled again later.
public actor OTelTelemetry {
    let configuration: OTelConfiguration
    let dependencies: OTelDependencies
    nonisolated let gate: TelemetryGate
    nonisolated let ingress: TelemetryIngress
    private nonisolated let clock: any TelemetryClock
    private nonisolated let executor = TelemetryExecutor(name: "ARCMetricsOTel")

    private var pipeline: Pipeline?
    private var tracker: SessionTracker
    private var openSpans: [UInt64: any Span] = [:]
    private var consumer: Task<Void, Never>?
    private var shutdownTask: Task<Void, Never>?

    init(configuration: OTelConfiguration, dependencies: OTelDependencies) {
        self.configuration = configuration
        self.dependencies = dependencies
        gate = TelemetryGate(configuration.initialSettings)
        ingress = TelemetryIngress()
        clock = dependencies.clock
        tracker = SessionTracker(policy: configuration.sessionPolicy,
                                 store: dependencies.sessionStore,
                                 makeID: dependencies.makeSessionID)
    }

    deinit {
        // Closes the queue, so the consumer ends instead of waiting for a command that never comes.
        ingress.finish()
        executor.stop()
    }

    /// The dedicated thread every call on this actor runs on.
    public nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    /// Builds the pipeline if telemetry starts enabled, and starts consuming the queue.
    func start() throws(OTelBootstrapError) {
        if gate.isEnabled {
            pipeline = try buildPipeline()
        }
        let stream = ingress.stream
        // Nonisolated: it captures `self` weakly, so it does not inherit the actor's isolation
        // and hops onto the actor once per command. It ends when `shutdown()` or `deinit` finishes
        // the stream; commands still queued after a release are skipped.
        consumer = Task { [weak self] in
            for await command in stream {
                await self?.handle(command)
            }
        }
    }

    /// Whether the export pipeline has been built.
    var isActive: Bool {
        pipeline != nil
    }

    /// Applies new settings.
    ///
    /// The kill switch and sample rate take effect for every stage before this method waits for
    /// anything, so they are not delayed by a flush in progress. Enabling telemetry for the first
    /// time then builds the pipeline; if the on-disk buffer cannot be created, telemetry stays
    /// dormant. Disabling it abandons spans still open and discards everything already batched or
    /// buffered, so none of it is ever exported.
    public nonisolated func update(_ settings: TelemetrySettings) async {
        gate.update(settings)
        await applyGate()
    }

    /// Processes everything enqueued so far, then pushes it through the buffer to the network.
    ///
    /// Blocks for up to ``OTelConfiguration/exportTimeout`` per stage. Call it rarely — for
    /// example when the app moves to the background.
    public func flush() async {
        await withCheckedContinuation { continuation in
            if !ingress.send(.barrier(continuation)) {
                continuation.resume()
            }
        }
        pipeline?.flush(timeout: configuration.exportTimeout.timeInterval)
    }

    /// Processes everything enqueued, flushes, and shuts the exporters down. Later records are ignored.
    ///
    /// Concurrent and repeated calls all return once the first shutdown has finished.
    public func shutdown() async {
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        let task = Task {
            await performShutdown()
        }
        shutdownTask = task
        await task.value
    }

    /// A tracer that records ARCMetrics spans and events through this pipeline.
    public nonisolated var tracer: OTelTracer {
        OTelTracer(telemetry: self)
    }

    /// Ends the current session and starts a new one, as if it had expired.
    ///
    /// Queued like every record, so records enqueued earlier keep the old session.
    public nonisolated func resetSession() {
        ingress.send(.resetSession(clock.now))
    }

    // MARK: Recording (internal: `tracer` is the public entry point for spans)

    //
    // While the kill switch is off these return before reading the clock or enqueuing, so a
    // disabled app pays almost nothing per call. `handle(_:)` still drops anything enqueued just
    // before a disable.

    /// Enqueues the start of a span.
    nonisolated func startSpan(id: UInt64,
                               name: String,
                               parentID: UInt64?,
                               attributes: TraceAttributes) {
        guard gate.isEnabled else { return }
        ingress.send(.startSpan(SpanStart(id: id,
                                          name: name,
                                          parentID: parentID,
                                          attributes: attributes,
                                          time: clock.now)))
    }

    /// Enqueues the end of a span. `errorType` marks it failed.
    nonisolated func endSpan(id: UInt64, errorType: String?, attributes: TraceAttributes) {
        guard gate.isEnabled else { return }
        ingress.send(.endSpan(SpanEnd(id: id, errorType: errorType, attributes: attributes, time: clock.now)))
    }

    /// Enqueues a log event, timestamped `timestamp` or now.
    ///
    /// The record joins the session current now, even when `timestamp` is in the past.
    nonisolated func emitEvent(name: String,
                               attributes: TraceAttributes,
                               severity: Severity,
                               timestamp: Date? = nil) {
        guard gate.isEnabled else { return }
        let now = clock.now
        ingress.send(.event(EventRecord(name: name,
                                        attributes: attributes,
                                        severity: severity,
                                        time: timestamp ?? now,
                                        sessionTime: now)))
    }

    /// Enqueues a span that ran from `start` to `end`, with no parent.
    ///
    /// The span joins the session current now, even when it ran in the past.
    nonisolated func recordSpan(name: String, attributes: TraceAttributes, start: Date, end: Date) {
        guard gate.isEnabled else { return }
        ingress.send(.completedSpan(CompletedSpan(name: name,
                                                  attributes: attributes,
                                                  start: start,
                                                  end: end,
                                                  sessionTime: clock.now)))
    }
}

// MARK: - Events

public extension OTelTelemetry {
    /// Records a log event named `name`.
    ///
    /// Returns immediately. The event is stamped with the current session, like every record, and
    /// follows the kill switch and session sampling.
    ///
    /// - Parameters:
    ///   - name: The event name, for example `cache.purge`. It is exported: use a constant, never
    ///     a string built from user data.
    ///   - attributes: The event's attributes. Never put personal data here.
    ///   - severity: The record's severity.
    ///   - timestamp: When the event happened; now when `nil`. A past timestamp does not affect
    ///     sessions: the event joins the session current at the time of this call.
    nonisolated func emitEvent(_ name: String,
                               attributes: TraceAttributes = [:],
                               severity: EventSeverity = .info,
                               timestamp: Date? = nil) {
        emitEvent(name: name, attributes: attributes, severity: severity.otelSeverity, timestamp: timestamp)
    }
}

// MARK: - Processing

private extension OTelTelemetry {
    /// The pipeline, when records should reach it.
    var activePipeline: Pipeline? {
        gate.isEnabled ? pipeline : nil
    }

    var isShutDown: Bool {
        shutdownTask != nil
    }

    /// Brings the pipeline in line with the gate. Reads the gate rather than the settings passed
    /// to ``update(_:)``, so concurrent updates always converge on the latest settings.
    func applyGate() {
        if let discard = gate.pendingDiscard {
            openSpans.removeAll()
            // Exports stay closed while a discard is pending, so this flush deletes what is
            // batched or on disk instead of sending it.
            pipeline?.flush(timeout: configuration.exportTimeout.timeInterval)
            gate.completeDiscard(discard)
        }
        guard gate.isEnabled, pipeline == nil, !isShutDown else {
            return
        }
        do {
            pipeline = try buildPipeline()
        } catch {
            // Telemetry must never take the app down: without a disk buffer it stays dormant,
            // and the next `update(_:)` that enables it tries again.
        }
    }

    func performShutdown() async {
        ingress.finish()
        await consumer?.value
        pipeline?.shutdown(timeout: configuration.exportTimeout.timeInterval)
        pipeline = nil
        openSpans.removeAll()
    }

    func buildPipeline() throws(OTelBootstrapError) -> Pipeline {
        let root = dependencies.storageRoot ?? StorageLocation.defaultRoot()
        return try PipelineFactory.make(configuration: configuration,
                                        dependencies: dependencies,
                                        gate: gate,
                                        storage: StorageLocation(root: root))
    }

    func handle(_ command: TelemetryCommand) {
        guard let pipeline = activePipeline else {
            // Records are dropped, but a flush waiting on a barrier must still return.
            if case let .barrier(continuation) = command {
                continuation.resume()
            }
            return
        }
        handle(command, in: pipeline)
    }

    func handle(_ command: TelemetryCommand, in pipeline: Pipeline) {
        switch command {
        case let .barrier(continuation):
            continuation.resume()
        case let .startSpan(start):
            startSpan(start, in: pipeline)
        case let .endSpan(end):
            endSpan(end, in: pipeline)
        case let .event(event):
            emitLog(event, session: session(at: event.sessionTime, in: pipeline), in: pipeline)
        case let .completedSpan(span):
            recordSpan(span, in: pipeline)
        case let .resetSession(time):
            announce(tracker.reset(at: time), at: time, in: pipeline)
        }
    }

    func startSpan(_ start: SpanStart, in pipeline: Pipeline) {
        let session = session(at: start.time, in: pipeline)
        let builder = pipeline.tracer.spanBuilder(spanName: start.name).setStartTime(time: start.time)
        if let parentID = start.parentID, let parent = openSpans[parentID] {
            builder.setParent(parent)
        } else {
            builder.setNoParent()
        }
        for (key, value) in recorded(start.attributes, session: session) {
            builder.setAttribute(key: key, value: value)
        }
        openSpans[start.id] = builder.startSpan()
    }

    func endSpan(_ end: SpanEnd, in pipeline: Pipeline) {
        _ = session(at: end.time, in: pipeline)
        guard let span = openSpans.removeValue(forKey: end.id) else {
            return
        }
        // The session was stamped at start; never let end attributes replace it.
        var attributes = scrubbed(end.attributes)
        attributes[AttributeKeys.sessionID] = nil
        attributes[AttributeKeys.sessionPreviousID] = nil
        span.setAttributes(attributes)
        if let errorType = end.errorType {
            span.status = .error(description: errorType)
            span.setAttribute(key: AttributeKeys.errorType, value: .string(errorType))
        }
        span.end(time: end.time)
    }

    func recordSpan(_ completed: CompletedSpan, in pipeline: Pipeline) {
        let session = session(at: completed.sessionTime, in: pipeline)
        let builder = pipeline.tracer.spanBuilder(spanName: completed.name)
            .setStartTime(time: completed.start)
            .setNoParent()
        for (key, value) in recorded(completed.attributes, session: session) {
            builder.setAttribute(key: key, value: value)
        }
        builder.startSpan().end(time: completed.end)
    }

    /// Records activity at `time` and returns its session, announcing any session change.
    func session(at time: Date, in pipeline: Pipeline) -> Session {
        let transition = tracker.touch(at: time)
        announce(transition, at: time, in: pipeline)
        return transition.current
    }

    /// Emits `session.end` for an ended session and `session.start` for a new one.
    func announce(_ transition: SessionTransition, at time: Date, in pipeline: Pipeline) {
        if let ended = transition.ended {
            emitLog(EventRecord(name: EventNames.sessionEnd, attributes: [:], severity: .info, time: time),
                    session: ended,
                    in: pipeline)
        }
        if transition.didStart {
            emitLog(EventRecord(name: EventNames.sessionStart, attributes: [:], severity: .info, time: time),
                    session: transition.current,
                    in: pipeline)
        }
    }

    /// Emits `record` as a log event of `session`, if the session is sampled.
    func emitLog(_ record: EventRecord, session: Session, in pipeline: Pipeline) {
        guard gate.isSampled(sessionID: session.id) else {
            return
        }
        pipeline.logger.logRecordBuilder()
            .setEventName(record.name)
            .setTimestamp(record.time)
            .setSeverity(record.severity)
            .setAttributes(recorded(record.attributes, session: session))
            .emit()
    }

    /// `attributes` after the configured scrubber, as OpenTelemetry values.
    func scrubbed(_ attributes: TraceAttributes) -> [String: AttributeValue] {
        configuration.attributeScrubber.scrub(attributes).otelAttributes
    }

    /// A record's attributes: scrubbed, then stamped with `session`. Stamping comes last, so a
    /// scrubber can neither remove nor forge `session.id` and `session.previous_id`.
    func recorded(_ attributes: TraceAttributes, session: Session) -> [String: AttributeValue] {
        var recorded = scrubbed(attributes)
        recorded[AttributeKeys.sessionID] = .string(session.id)
        if let previousID = session.previousID {
            recorded[AttributeKeys.sessionPreviousID] = .string(previousID)
        }
        return recorded
    }
}

// MARK: - CustomReflectable

extension OTelTelemetry: CustomReflectable {
    /// Only the redacted ``OTelConfiguration``: the pipeline holds the raw headers.
    public nonisolated var customMirror: Mirror {
        Mirror(self, children: ["configuration": configuration], displayStyle: .class)
    }
}
