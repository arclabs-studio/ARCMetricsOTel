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
- **Blocking flush.** Export and flush block on a `DispatchSemaphore` for up to the export
  timeout. We keep flushes rare (explicit `flush()`, app backgrounding).
- **Flush ignores `exportCondition`.** `DataExportWorker.flush()` bypasses the export condition,
  so the kill switch adds its own gated exporter inside the persistence decorator.
- **Unsafe defaults we override.** `requeueOnFailure` defaults to `true` (double delivery with the
  disk buffer) — always `false`. `envVarHeaders` reads the process environment — always `nil`.
- **Completion-handler `HTTPClient`, not `Sendable`.** Injected as `BaseHTTPClient(session:)`
  backed by a `URLSession`, so tests stub the network with `URLProtocol`.

Revisit on every upstream minor bump (`arc-dependency-auditor`).
