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
  again later.

Telemetry configured disabled builds nothing at all until the first update that enables it.

### Sampling

The sample rate (0…1; `NaN` counts as 0) is applied per **session**: the decision is derived from
`session.id`, so a session is either exported completely or not at all. Spans, events, MetricKit
reports, lifecycle events and screen views all follow it, and a child span always follows its
parent.
