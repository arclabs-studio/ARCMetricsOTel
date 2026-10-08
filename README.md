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

### Key Features (planned for 1.0.0)

- ✅ **OTLP/HTTP export** of spans and logs, with a disk buffer for offline runs
- ✅ **Sessions** — 15 min idle, 4 h max, `session.id` and `session.previous_id` on every record
- ✅ **Session-consistent head sampling** and a remote **kill switch**
- ✅ **MetricKit bridge** — ARCMetrics summaries become spans, `app.crash` and `app.hang` events
- ✅ **App lifecycle** events and a SwiftUI `.trackScreen(_:)` modifier
- ✅ **Privacy** — attribute and URL scrubbing, no PII attributes by default

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

Usage documentation lands with the public API in 1.0.0.

---

## 🏗️ Project Structure

```
ARCMetricsOTel/
├── Sources/
│   ├── ARCMetricsOTel/          # Library
│   └── ARCMetricsOTelMocks/     # Test doubles for consumers
├── Tests/ARCMetricsOTelTests/   # Swift Testing suites
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
opentelemetry-swift 2.6.x. The trade-offs — a ~27-package resolve, upstream concurrency escapes,
a blocking flush — are recorded in [ADR 0001](docs/adr/0001-opentelemetry-swift-dependency.md).

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
