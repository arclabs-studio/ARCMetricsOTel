# Changelog

All notable changes to ARCMetricsOTel will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Package scaffold: `ARCMetricsOTel` and `ARCMetricsOTelMocks` products, ARCDevTools integration.
- CI runs the tests on an iOS simulator with a 100% line-coverage gate (`scripts/check-coverage.py`); `scripts/coverage.sh` runs the same gate locally.
- ADR 0001 records the opentelemetry-swift dependency and its known upstream debt.
- `OTelBootstrap.configure(_:)` builds an OTLP/HTTP span and log pipeline with a disk buffer,
  sessions (15 min idle, 4 h max, `session.start`/`session.end` events), session-consistent
  sampling and a kill switch (`OTelTelemetry.update(_:)`) that also discards buffered data.
- `OTelTelemetry` runs on its own thread, so upstream's blocking flush never occupies Swift's
  cooperative pool.
- Batches the collector rejects permanently are dropped instead of retried; the disk buffer is
  capped at 16 MB and 6 hours.
- `allowsInsecureTransport` is honoured in Debug builds only.
- `OTelTelemetry.tracer` returns an `OTelTracer`, the ARCMetrics `Tracing` adapter: a span's
  parent becomes its OpenTelemetry parent, `.error(type:)` sets status error and `error.type`, and
  events become info log records. Combine it with `MetricKitSignpostTracer` through `TeeTracer`.
  The span category is not exported; a span that is never ended is never exported.
- While the kill switch is off, recording calls return before enqueuing anything.
- `MetricKitBridge` sends ARCMetrics metric summaries as `MXMetricPayload` spans and diagnostics as
  `app.crash` / `app.hang` events. Reports join the session current when they arrive.
- `AppLifecycleObserver` records `device.app.lifecycle` events with `ios.app.state` from
  `NotificationLifecycleSource` (or any `LifecycleEventSource`) and flushes on background.
- `OTelTelemetry.emitEvent(_:attributes:severity:timestamp:)` records an event with an
  `EventSeverity` and an optional past timestamp.
- `AttributeScrubber` (`OTelConfiguration.attributeScrubber`, `.default`, `then(_:)`) scrubs every
  record's attributes in the telemetry actor before `session.id` is stamped. The default follows
  OpenTelemetry's semantic conventions and Apple's App Privacy data types: it drops personal-data
  keys (by name, and by key segment including camelCase) and redacts credentials, queries and
  fragments in `url.*` values.
- The package ships a privacy manifest (`PrivacyInfo.xcprivacy`).
- `View.trackScreen(_:attributes:)` records `app.screen.view` with `app.screen.name` through the
  `TelemetryEmitting` set with `View.telemetry(_:)`; `RecordingTelemetryEmitter` in
  `ARCMetricsOTelMocks` records events for tests and previews.
- `Examples/ARCMetricsOTelDemoApp`: an iPhone demo that drives every feature against a collector
  set with `OTEL_EXPORTER_OTLP_ENDPOINT`.
- DocC catalog: Getting Started, Kill Switch and Sampling, Sessions, Offline Buffering, Privacy,
  MetricKit Bridge and Local Grafana.

### Changed

- Depends on ARCMetrics `2.1.0` or later, for the `Tracing` protocol.

### Fixed

- A backlog of more than a few hundred spans or log records flushed at once was silently dropped
  by the disk buffer. Batches are now capped at 100 records and buffered objects at 1 MB.
