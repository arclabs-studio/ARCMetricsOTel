# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package Overview

ARCMetricsOTel exports OpenTelemetry spans and logs over OTLP/HTTP for ARC Labs apps.
It is the OpenTelemetry companion to ARCMetrics, which stays dependency-free; opentelemetry-swift
is approved as a dependency **in this package only**.

**Platforms:** iOS 18+
**Swift:** 6.0 tools, Swift 6 language mode
**Products:** `ARCMetricsOTel`, `ARCMetricsOTelMocks` (test doubles)

**Status:** pre-1.0. Work is tracked in FVRS-348 and ships as milestone PRs M1–M4 to `develop`.

## Design decisions to keep

- **One lock: `Mutex`.** `TelemetryGate` (and a few small `Sendable` final classes) guard state with
  `Synchronization.Mutex`, because upstream calls the sampler, `exportCondition` and the exporters
  synchronously from its own threads. That is legitimate `Sendable`, not an escape: never replace it
  with `@unchecked Sendable` or `nonisolated(unsafe)`.
- **Own sessions.** `SessionTracker` is ours, not upstream's Sessions instrumentation (no clock seam,
  static `UserDefaults`, a global logger, `nonisolated(unsafe)` statics).
- **Session time vs record time.** A record about the past (MetricKit, `emitEvent(timestamp:)`)
  keeps its timestamp but joins the session current when it is recorded — never `touch` the
  tracker with a past time.
- **Scrub before stamping.** `AttributeScrubber` runs in the actor before `session.id` is added.
- **Public API stays free of OpenTelemetry types** (`TraceAttributes`, `EventSeverity`), so apps
  never import an OpenTelemetry module.

## Build & Test

Use the Xcode MCP (`BuildProject`, `RunAllTests`) — see the studio constitution. Xcode opens an
SPM package by its **directory** path, not `Package.swift`.

**Coverage:** the Xcode MCP reports none, so `scripts/coverage.sh` runs `xcodebuild test
-enableCodeCoverage` + `scripts/check-coverage.py` — the only sanctioned CLI path (user decision
2026-10-08). Gate: 100% lines on `ARCMetricsOTel` and `ARCMetricsOTelMocks`, also enforced in CI
(`.github/workflows/tests.yml`, iOS simulator — `swift test` on the macOS host cannot build an
iOS-only package).

**Known toolchain warning (Xcode 27), waived by the user 2026-10-08:** linking the test bundle for an iOS simulator emits
`Using sysroot for 'macOS 27.0' but targeting 'arm64-apple-ios18.0.0-simulator'
[-Wincompatible-sysroot]`. It reproduces in a fresh trivial package (same in ARCMetrics) and has
no `Package.swift` lever. The library targets themselves are warning-free — check those.

```bash
make lint      # SwiftLint
make format    # SwiftFormat (dry run)
make fix       # Apply SwiftFormat
```

## Tooling traps

- **`arcdevtools-setup` overwrites `.github/release-drafter.yml`** (and the PR template) on every
  run. Its stock body advertises ARCDevTools; re-apply the ARCMetricsOTel installation snippet after
  any setup run. `tests.yml` is project-owned (template header removed), so setup leaves it alone.
- `.swiftformat` excludes `.claude/` — otherwise the pre-commit hook reformats the vendored
  `arc-package-validator` script and setup reverts it on the next run.
- `arc-package-validator` false positives: it requires `.iOS(.v17)` (we target 18), an MIT
  license (we ship PolyForm) and a host `swift build` (cannot build iOS-only code).
- The Write/Edit hook formats with Homebrew SwiftFormat/SwiftLint, which differ from the pins in
  `.arc-tool-versions`. `make lint` / `make format` (pinned) are what CI runs.
- Third-party dependency rationale and known upstream debt: `docs/adr/0001-opentelemetry-swift-dependency.md`.

## Git Workflow

Gitflow: `main` (releases, tags) + `develop` (integration). Branches
`feature/FVRS-XXX-description`; Conventional Commits; PR titles
`[FEATURE|BUGFIX|HOTFIX|DOCS|CHORE][FVRS-XXX] Title` (CI hard gate). Releases go
`develop` → `main` in a PR titled `[CHORE] Release: vX.Y.Z` — `enforce-gitflow.yml` rejects
`release/*` → `main`. Tags are `vX.Y.Z`, on `main`.
