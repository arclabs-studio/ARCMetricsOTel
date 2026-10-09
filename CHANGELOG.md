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

### Changed

- Depends on ARCMetrics `2.1.0` or later, for the `Tracing` protocol.
