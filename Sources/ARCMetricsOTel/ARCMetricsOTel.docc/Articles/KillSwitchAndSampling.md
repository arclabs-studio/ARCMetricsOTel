# Kill Switch and Sampling

Turn telemetry off remotely, and keep or drop whole sessions.

## Overview

``TelemetrySettings`` carries two values, normally fed from remote flags (`telemetry_otel_enabled`
and `telemetry_trace_sample_rate`) through ``OTelTelemetry/update(_:)``.

### The kill switch

While ``TelemetrySettings/isEnabled`` is `false`:

- recording calls return before reading the clock or enqueuing anything;
- a record already queued is dropped by the telemetry actor;
- the sampler drops every span;
- the disk buffer stops exporting;
- anything already batched or buffered is **discarded**, not sent — even if telemetry is enabled
  again later. That includes records an earlier launch left in the disk buffer.

An upload already in flight when telemetry is disabled is not cancelled: that one request
completes.

Telemetry configured disabled builds nothing at all until the first update that enables it.
Starting disabled alone discards nothing: a buffer left by an earlier launch is kept (and sent once
telemetry is enabled) unless an ``OTelTelemetry/update(_:)`` disables it first.

If your app stores an opt-out of its own (a settings toggle, a cached flag), call
`update(.disabled)` at launch whenever that opt-out is set, before telemetry is enabled again. The
discard is not persisted across launches: without that call, a buffer recorded before the opt-out
survives a relaunch.

### Sampling

The sample rate (0…1; `NaN` counts as 0) is applied per **session**: the decision is derived from
`session.id`, so a session is either exported completely or not at all. Spans, events, MetricKit
reports, lifecycle events and screen views all follow it, and a child span always follows its
parent.
