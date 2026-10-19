# ARCMetricsOTelDemoApp

An iPhone app that exercises every part of ARCMetricsOTel against a real OpenTelemetry collector.

## Run it

1. Start a collector, for example `grafana/otel-lgtm` (see the *Local Grafana* DocC article):

   ```bash
   docker run -d --name lgtm -p 3000:3000 -p 4318:4318 grafana/otel-lgtm
   ```

2. Open `ARCMetricsOTelDemoApp.xcodeproj` and run the `ARCMetricsOTelDemoApp` scheme (Debug).
   The app sends to `http://localhost:4318`. For a collector on another machine, set
   `OTEL_EXPORTER_OTLP_ENDPOINT` (for example `http://mac-mini.local:4318`) in the scheme's
   environment variables. It is read at launch and never committed.

3. Open Grafana (`http://localhost:3000`) → Explore: Tempo for spans, Loki for events.

## What it does

| Control | Records |
|---------|---------|
| Telemetry enabled / Sample rate | `OTelTelemetry.update(_:)` — the kill switch and session sampling |
| Run a traced operation | A `DemoOperation` span through `TeeTracer` (MetricKit signpost + OpenTelemetry) |
| Emit an event | `demo.button_tapped` through `emitEvent(_:attributes:severity:timestamp:)` |
| Start a new session | `session.end` / `session.start` |
| Flush now | Sends everything recorded so far |
| Simulate a metric / crash / hang report | `MXMetricPayload`, `app.crash`, `app.hang` from a `MockMetricsCollector` |
| Open the detail screen | `app.screen.view` for `Controls` and `Detail` |
| Background the app | `device.app.lifecycle` events and a flush |

## Package location

The project references the package as a local package at `../../../ARCMetricsOTel` (relative to
`Examples/ARCMetricsOTelDemoApp`), so the repository must be cloned into a directory named
`ARCMetricsOTel`.

## Development-only settings

This app is never shipped. It allows a plain-`http` collector (`allowsInsecureTransport`, honoured
in Debug builds only) and sets `NSAllowsLocalNetworking` so it can reach a collector on the local
network. A shipping app must use `https`, or keep that exception in a Debug-only Info.plist.
