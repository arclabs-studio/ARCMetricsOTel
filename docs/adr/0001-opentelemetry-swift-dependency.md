# ADR 0001 — Depend on opentelemetry-swift

**Status:** Accepted, 2026-10-08 (FVRS-348)

## Context

ARC packages avoid third-party dependencies, and ARCMetrics core stays dependency-free.
FavRes needs OpenTelemetry spans and logs exported over OTLP/HTTP (Grafana's mobile
observability stack). Writing an OTLP SDK in-house means re-implementing the data model,
protobuf/JSON encoding, batching and exporter semantics that the CNCF SDK already provides.

On 2026-10-05 the studio approved opentelemetry-swift as a dependency **of this package only**.
A spike on 2026-10-08 built `opentelemetry-swift-core` and `opentelemetry-swift` (contrib)
2.6.0 under Xcode 27 / Swift 6 mode with zero warnings and no concurrency escapes in our code.

## Decision

Depend on:

- `opentelemetry-swift-core` — `OpenTelemetryApi`, `OpenTelemetrySdk`
- `opentelemetry-swift` (contrib) — `OpenTelemetryProtocolExporterHTTP`, `PersistenceExporter`;
  `InMemoryExporter` in the test target only

pinned `.upToNextMinor(from: "2.6.0")`, and keep every upstream type behind this package's own API.
Sessions are our own (`SessionTracker`), not upstream's Sessions instrumentation: it has no clock
seam, uses static `UserDefaults` and a global logger, and keeps `nonisolated(unsafe)` statics.

## Consequences — known debt

Accepted as upstream debt, not repeated in our code:

- **Resolve size.** Contrib resolves ~27 packages (gRPC, NIO, protobuf, …) even though we link
  only the HTTP exporter.
- **Concurrency escapes upstream.** ~20 `@unchecked Sendable` and 6 `nonisolated(unsafe)` files,
  plus GCD. Our code adds none; the one lock we own is a `Mutex` inside a checked-`Sendable` gate.
- **Blocking flush.** Export and flush block the calling thread (`DispatchSemaphore`,
  `OperationQueue.waitUntilAllOperationsAreFinished`) for up to the export timeout. On Swift's
  cooperative pool this deadlocks once concurrent flushes occupy every pool thread (observed
  2026-10-08: 10/10 threads parked in `BatchSpanProcessor.forceFlush`). `OTelTelemetry`
  therefore runs on its own serial executor backed by a dedicated `Thread`
  (`TelemetryExecutor`, SE-0392), so no upstream call ever runs on the pool. We still keep
  flushes rare (explicit `flush()`, app backgrounding).
- **Flush ignores `exportCondition`.** `DataExportWorker.flush()` bypasses the export condition,
  so the kill switch adds its own gated exporter inside the persistence decorator.
- **Unsafe defaults we override.** `requeueOnFailure` defaults to `true` (double delivery with the
  disk buffer) — always `false`. `envVarHeaders` reads the process environment — always `nil`.
- **Protobuf only.** The OTLP/HTTP exporters always send `application/x-protobuf` and ignore
  `OtlpConfiguration.exportAsJson`. Standard OTLP; collectors (Grafana Alloy, otel-lgtm) accept
  it. Tests decode the wire format by field number.
- **Every non-2xx response is retried.** Upstream's `BaseHTTPClient` reports any non-2xx as a
  generic failure and the disk buffer retries every failure, so a batch the collector will never
  accept (revoked token, malformed or oversized payload) would be resent from every device for
  the file's lifetime. We inject our own `OTLPHTTPClient`: per the OTLP/HTTP specification only
  429, 502, 503, 504 and transport errors are retryable; any other status deletes the batch.
  `Retry-After` is not honoured — the buffer's own back-off decides when to retry.
- **Completion-handler `HTTPClient`, not `Sendable`.** The protocol's completion is not
  `@Sendable`, so it cannot cross into `URLSession`'s callback without `nonisolated(unsafe)`
  (upstream's own approach). `OTLPHTTPClient` instead blocks its calling thread on a
  `BlockingResult` (`NSCondition`) until an async `URLSession` request finishes, then calls the
  completion on that same thread. Callers are upstream's export threads or `OTelTelemetry`'s
  dedicated thread, never the cooperative pool. Tests stub the network with `URLProtocol`.
  The wait has an absolute deadline (the request timeout plus one second); past it the request
  is cancelled and reported as timed out, so a stalled or trickling response cannot hold a
  thread. TLS failures count as transport errors and are retried; no data is sent on them.
- **Generous buffer defaults.** Upstream's default preset keeps 512 MB for 18 h and retries
  every 20 s at most. We use `PersistencePerformancePreset.arcMetricsOTel`: 16 MB, 6 h, back-off
  up to 60 s. Upstream offers no jitter.

Revisit on every upstream minor bump (`arc-dependency-auditor`).
