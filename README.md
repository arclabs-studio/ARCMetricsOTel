# 📡 ARCMetricsOTel

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B-blue.svg)
![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-orange.svg)
![Version](https://img.shields.io/badge/Version-unreleased-lightgrey.svg)

**OpenTelemetry export for ARC Labs apps — spans and logs over OTLP/HTTP.**

OTLP/HTTP Export • Offline Disk Buffer • Sessions • Session-Consistent Sampling • Kill Switch • MetricKit Bridge

> **Status: under construction.** Nothing is usable before 1.0.0.

---

## 🎯 Overview

ARCMetricsOTel exports spans and logs over OTLP/HTTP, built on
[opentelemetry-swift](https://github.com/open-telemetry/opentelemetry-swift). It is the
OpenTelemetry companion to [ARCMetrics](https://github.com/arclabs-studio/ARCMetrics), which
stays dependency-free.

### Key Features (1.0.0)

- ✅ **OTLP/HTTP export** of spans and logs, with a disk buffer for offline runs
- ✅ **Sessions** — 15 min idle, 4 h max, `session.id` and `session.previous_id` on every record
- ✅ **Session-consistent head sampling** and a remote **kill switch**
- ✅ **ARCMetrics tracing** — `telemetry.tracer` adapts ARCMetrics `Tracing`; with `TeeTracer`
  each span reaches MetricKit and the collector together
- ✅ **MetricKit bridge** — ARCMetrics summaries become `MXMetricPayload` spans, `app.crash` and
  `app.hang` events
- ✅ **App lifecycle** — `device.app.lifecycle` events, and a flush when the app goes to the background
- ✅ **Screen views** — a SwiftUI `.trackScreen(_:)` modifier
- ✅ **Privacy** — an `AttributeScrubber` (OpenTelemetry and Apple data types) runs on every record,
  and the package ships its own privacy manifest

### Tracing with ARCMetrics

```swift
let tracer = TeeTracer([MetricKitSignpostTracer(), telemetry.tracer])

let restaurants = try await tracer.trace("FetchAll", category: .persistence,
                                         attributes: ["store": "cloudkit"]) { _ in
    try await repository.fetchAll()
}
```

A span's `parent` becomes its OpenTelemetry parent; a thrown error ends it with status error and
`error.type` (the type name, never the message). The span category is not exported, and a span
that is never ended is never exported. Attributes leave the device: never put personal data in
them.

### MetricKit and app lifecycle

```swift
let bridge = MetricKitBridge(collector: collector, telemetry: telemetry)
let lifecycle = AppLifecycleObserver(telemetry: telemetry)
Task { await bridge.run() }
Task { await lifecycle.run() }
collector.startCollecting()
```

- Each ARCMetrics metric summary becomes one `MXMetricPayload` span over the report's interval.
  Where a value means exactly what upstream opentelemetry-swift's MetricKit instrumentation
  reports, the attribute uses upstream's name and base unit (`metrickit.memory.peak_memory_usage`
  in bytes, `metrickit.cpu.cpu_time` in seconds, …), so its dashboards work. Where ARCMetrics
  computes something different, the name is our own and carries the unit:
  `metrickit.app_responsiveness.hang_time_total_s`, `metrickit.app_launch.time_to_first_draw_average_s`,
  `metrickit.animation.hitch_time_ratio_ms_per_s` and `…scroll_hitch_time_ratio_ms_per_s`.
- Each crash becomes an `app.crash` event (fatal) with `exception.type`, `exception.signal` and
  `exception.termination_reason`; each hang an `app.hang` event (warn) with `app.hang.duration_s`.
  The crash's virtual-memory region is never exported.
- Reports describe the past but join the session current when they arrive. They follow sampling
  and the kill switch. The bridge never starts the collector: the app owns it.
- `AppLifecycleObserver` records each transition with `ios.app.state` and flushes after
  `background`. `telemetry.emitEvent(_:attributes:severity:timestamp:)` records any other event;
  its name and attributes leave the device, so use constant names and no personal data.
- `exception.termination_reason` is exported only in its structured form
  (`Namespace SIGNAL, Code 11`); free text the OS appends, such as a library path, is left out.

### Privacy

Every record's attributes pass through an `AttributeScrubber` before they are created. The default
follows OpenTelemetry's semantic conventions and Apple's App Privacy data types: it drops
personal-data keys (`user.email`, `userEmail`, `geo.location.lat`, `auth_token`, …) and redacts
credentials, queries and fragments in `url.*` values. It is a best-effort backstop: never put
personal data in attributes or names, and add your own rules with `AttributeScrubber.then(_:)`.

The package ships a `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`; crash, performance and other
diagnostic data, product interaction and a device ID, none linked or used for tracking). Your App
Store privacy label must cover the same data:

| Data the app sends | App Privacy data type |
|--------------------|-----------------------|
| `app.crash` | Diagnostics — Crash Data |
| `MXMetricPayload`, `app.hang` | Diagnostics — Performance Data |
| Your spans, `session.start` / `session.end` | Diagnostics — Other Diagnostic Data |
| `app.screen.view`, `device.app.lifecycle` | Usage Data — Product Interaction |
| `session.id`, `session.previous_id` | Identifiers — Device ID |

`session.previous_id` is persisted across launches, so a collector can chain every session of an
install; with `device.model.identifier`, `os.version` and the client IP it is a pseudonymous install
identifier. Declare the data as **linked to you** as soon as your attributes or your collector join
it to an account or other personal data. Details: the *Privacy* article in the DocC catalog.

---

## 📋 Requirements

- **Swift:** 6.0+
- **Platforms:** iOS 18.0+
- **Xcode:** 16.0+

---

## 🚀 Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/arclabs-studio/ARCMetricsOTel.git", from: "1.0.0")
]
```

Then add `ARCMetricsOTel` to your target, and `ARCMetricsOTelMocks` to your test target.

---

## 📖 Usage

See the DocC catalog (*Getting Started* first) and the demo app in
`Examples/ARCMetricsOTelDemoApp`, which drives every feature against a collector.

---

## 🏗️ Project Structure

```
ARCMetricsOTel/
├── Sources/
│   ├── ARCMetricsOTel/          # Library
│   └── ARCMetricsOTelMocks/     # Test doubles for consumers
├── Tests/ARCMetricsOTelTests/   # Swift Testing suites
├── Examples/ARCMetricsOTelDemoApp/  # iPhone demo app (see its README)
├── docs/adr/                    # Architecture decision records
└── scripts/                     # Coverage gate
```

---

## 🧪 Testing

Tests use Swift Testing and run on an iOS simulator (the package is iOS-only). CI enforces
**100% line coverage** on `ARCMetricsOTel` and `ARCMetricsOTelMocks`. Locally:

```bash
scripts/coverage.sh            # xcodebuild test + coverage gate
```

---

## 📦 Dependencies & Known Debt

ARC packages avoid third-party code; this package is the approved exception. It depends on
opentelemetry-swift 2.6.x (core and contrib). Known upstream debt, accepted and worked around
here — details in [ADR 0001](docs/adr/0001-opentelemetry-swift-dependency.md):

- **Resolve size:** contrib resolves ~27 packages (gRPC, NIO, protobuf, …), although only the
  OTLP/HTTP exporter and the persistence decorator are linked.
- **Concurrency escapes:** upstream uses `@unchecked Sendable`, `nonisolated(unsafe)` and GCD. This
  package adds none; its one lock is a `Mutex`.
- **Blocking flush:** upstream's export and flush block the calling thread. `OTelTelemetry` runs on
  its own thread, so a flush never occupies Swift's cooperative pool.
- **Flush ignores the export condition:** the disk buffer's flush bypasses `exportCondition`, so the
  kill switch also gates the exporter inside the buffer.
- **Oversized batches vanish:** the buffer silently drops a stored batch above its object limit;
  batches are capped at 100 records and objects at 1 MB.

---

## 🛠️ Development

```bash
make lint      # SwiftLint (pinned)
make format    # SwiftFormat dry run (pinned)
make fix       # Apply SwiftFormat
```

---

## 🤝 Contributing

Internal to ARC Labs Studio. Branches `feature/FVRS-XXX-description` off `develop`, Conventional
Commits, PR titles `[FEATURE][FVRS-XXX] Title`.

---

## 📦 Versioning

[Semantic Versioning](https://semver.org). Release tags are `vX.Y.Z` on `main`; see the
[CHANGELOG](CHANGELOG.md).

---

## 📄 License

[PolyForm Noncommercial 1.0.0](LICENSE). ARC Labs Studio's own products are covered by the
[internal use grant](INTERNAL-USE.md).

---

## 🔗 Related Resources

- [ARCMetrics](https://github.com/arclabs-studio/ARCMetrics)
- [ARCKnowledge](https://github.com/arclabs-studio/ARCKnowledge)
- [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/)

---

<div align="center">

Made with 💛 by ARC Labs Studio

</div>
