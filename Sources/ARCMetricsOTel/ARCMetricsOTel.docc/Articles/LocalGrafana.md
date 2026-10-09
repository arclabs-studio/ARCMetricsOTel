# Local Grafana

See your telemetry in a local Grafana while developing.

## Overview

`grafana/otel-lgtm` bundles an OpenTelemetry collector, Tempo (traces), Loki (logs) and Grafana in
one container:

```bash
docker run -d --name lgtm -p 3000:3000 -p 4318:4318 grafana/otel-lgtm
```

Point a Debug build at it. A collector on the same Mac is `http://localhost:4318`; one on another
machine on the network is `http://<host>.local:4318`, which needs ``OTelConfiguration/allowsInsecureTransport``
(honoured in Debug builds only) and `NSAllowsLocalNetworking` in the app's `NSAppTransportSecurity`
settings. Add that exception to a Debug-only Info.plist (or build setting), so it never ships.

Open Grafana at `http://localhost:3000` (or the other machine's host), then in **Explore**:

- **Tempo:** `{resource.service.name="YourService"}` lists the spans, each with `session.id`.
- **Loki:** `{service_name="YourService"}` lists the events: `app.screen.view`,
  `device.app.lifecycle`, `app.crash`, `app.hang` and `session.start` / `session.end`.

Never ship an `http` endpoint or ``OTelConfiguration/allowsInsecureTransport``: Release builds
ignore the flag and reject plain `http` on any host but the loopback.
