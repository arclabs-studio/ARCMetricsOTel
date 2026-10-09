# MetricKit Bridge

Send ARCMetrics' MetricKit reports to OpenTelemetry.

## Overview

``MetricKitBridge`` subscribes to an ARCMetrics `MetricsCollecting` collector when it is created
and, while ``MetricKitBridge/run()`` runs, records:

- each metric summary as one `MXMetricPayload` span covering the report's interval;
- each crash as an `app.crash` event (fatal) with `exception.type`, `exception.signal` and
  `exception.termination_reason`;
- each hang as an `app.hang` event (warn) with `app.hang.duration_s`.

Diagnostic events are timestamped at the end of the report's interval. A report without an
interval is skipped. The bridge never starts or stops the collector: the app owns it.

### Attribute names

Where an ARCMetrics value means exactly what upstream opentelemetry-swift's MetricKit
instrumentation reports, the span uses upstream's key and base unit, so dashboards built for it
work: `metrickit.memory.peak_memory_usage` and `metrickit.memory.suspended_memory_average`,
`metrickit.network_transfer.{cellular,wifi}_{download,upload}` and
`metrickit.diskio.logical_write_count` (bytes); `metrickit.cpu.cpu_time`, `metrickit.gpu.time`,
`metrickit.app_time.foreground_time` and `metrickit.app_time.background_time` (seconds).

Where ARCMetrics computes something different, the key is our own and names its unit:

| Key | Why it differs |
|-----|----------------|
| `metrickit.app_responsiveness.hang_time_total_s` | ARCMetrics reports total hang time; upstream an average. |
| `metrickit.app_launch.time_to_first_draw_average_s` | ARCMetrics weights histogram buckets by their lower edge; upstream by their midpoint. |
| `metrickit.animation.hitch_time_ratio_ms_per_s` | Milliseconds per second; only when reported. |
| `metrickit.animation.scroll_hitch_time_ratio_ms_per_s` | Milliseconds per second; only when reported. |

### App lifecycle

``AppLifecycleObserver`` records each transition from a ``LifecycleEventSource`` — by default
``NotificationLifecycleSource`` — as a `device.app.lifecycle` event with `ios.app.state`, and starts
a flush when the app moves to the background.
