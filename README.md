# ARCMetricsOTel

![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Platforms](https://img.shields.io/badge/Platforms-iOS%2018%2B-blue.svg)
![License](https://img.shields.io/badge/License-PolyForm%20Noncommercial%201.0.0-orange.svg)

**OpenTelemetry export for ARC Labs apps.**

> **Status: under construction.** Nothing is usable before 1.0.0.

---

## 🎯 Overview

ARCMetricsOTel exports spans and logs over OTLP/HTTP, built on
[opentelemetry-swift](https://github.com/open-telemetry/opentelemetry-swift). It is the
OpenTelemetry companion to [ARCMetrics](https://github.com/arclabs-studio/ARCMetrics), which
stays dependency-free.

Planned for 1.0.0:

- OTLP/HTTP export of spans and logs, with a disk buffer for offline runs
- Sessions (15 min idle, 4 h max) with `session.id` on every record
- Session-consistent head sampling and a remote kill switch
- A bridge from ARCMetrics' MetricKit summaries to spans and `app.crash` / `app.hang` events
- App lifecycle events, a SwiftUI `.trackScreen(_:)` modifier, and attribute scrubbing

Part of the ARC Labs Studio package ecosystem.

---

## 📋 Requirements

- **Swift:** 6.0+
- **Platforms:** iOS 18.0+

---

## 📄 License

[PolyForm Noncommercial 1.0.0](LICENSE). ARC Labs Studio's own products are covered by the
[internal use grant](INTERNAL-USE.md).
