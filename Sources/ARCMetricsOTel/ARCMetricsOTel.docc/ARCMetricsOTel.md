# ``ARCMetricsOTel``

Export OpenTelemetry spans and logs from ARC Labs apps over OTLP/HTTP, with sessions,
session-consistent sampling, a kill switch and an offline disk buffer.

## Overview

ARCMetricsOTel is the OpenTelemetry companion to ARCMetrics. ARCMetrics stays dependency-free and
emits signposts and MetricKit summaries; this package sends the same work to an OpenTelemetry
collector:

- ARCMetrics spans and events, through ``OTelTracer``.
- MetricKit reports, through ``MetricKitBridge``.
- App lifecycle transitions, through ``AppLifecycleObserver``.
- Screen views, through the `trackScreen(_:attributes:)` view modifier.
- Any other event, through ``OTelTelemetry/emitEvent(_:attributes:severity:timestamp:)``.

Every record carries `session.id`, follows the remote kill switch and the session's sampling
decision, and is scrubbed by an ``AttributeScrubber`` before it is created.

## Topics

### Essentials

- <doc:GettingStarted>
- ``OTelBootstrap``
- ``OTelConfiguration``
- ``OTelTelemetry``

### Remote control

- <doc:KillSwitchAndSampling>
- ``TelemetrySettings``

### Sessions and buffering

- <doc:Sessions>
- ``SessionPolicy``
- <doc:OfflineBuffering>

### Recording

- ``OTelTracer``
- ``EventSeverity``
- ``TelemetryEmitting``

### MetricKit and app lifecycle

- <doc:MetricKitBridge>
- ``MetricKitBridge``
- ``AppLifecycleObserver``
- ``LifecycleEventSource``
- ``NotificationLifecycleSource``
- ``AppLifecycleState``

### Privacy

- <doc:Privacy>
- ``AttributeScrubber``

### Development

- <doc:LocalGrafana>
- ``OTelBootstrapError``
