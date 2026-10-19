# Getting Started

Configure the pipeline once at launch and keep the returned telemetry for the app's lifetime.

## Overview

```swift
import ARCMetrics
import ARCMetricsOTel

guard let endpoint = URL(string: "https://otlp.example.com") else { return }
let configuration = OTelConfiguration(serviceName: "FavRes",
                                      serviceVersion: "1.4.0",
                                      environment: "production",
                                      endpoint: endpoint,
                                      headers: ["Authorization": authorization])
let telemetry = try await OTelBootstrap.configure(configuration)
```

``OTelBootstrap/configure(_:)`` validates the endpoint and returns an ``OTelTelemetry``. It starts
**disabled** (``TelemetrySettings/disabled``): nothing is built or sent until you enable it, usually
from a remote flag:

```swift
await telemetry.update(TelemetrySettings(isEnabled: true, sampleRate: 0.1))
```

The authorization header ships inside the app, so anyone can extract it. Use a token that can only
**write** telemetry to your collector — never a Grafana or admin token that can read data — and
rotate it. Keep it out of source code; a value from Remote Config is readable by anyone who has the
app's configuration keys. ``OTelConfiguration`` redacts header values from its descriptions and
from reflection.

### Record work

Combine the OpenTelemetry tracer with the MetricKit signpost tracer, so each span reaches both:

```swift
let tracer = TeeTracer([MetricKitSignpostTracer(), telemetry.tracer])

let restaurants = try await tracer.trace("FetchAll", category: .persistence) { _ in
    try await repository.fetchAll()
}
```

Run the MetricKit bridge and the lifecycle observer for the app's lifetime:

```swift
let bridge = MetricKitBridge(collector: collector, telemetry: telemetry)
let lifecycle = AppLifecycleObserver(telemetry: telemetry)
Task { await bridge.run() }
Task { await lifecycle.run() }
```

Track screens in SwiftUI by putting the telemetry in the environment once, near the root:

```swift
RootView()
    .telemetry(telemetry)

// …in any descendant
RestaurantListView()
    .trackScreen("RestaurantList")
```
