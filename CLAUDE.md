# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Package Overview

ARCMetricsOTel exports OpenTelemetry spans and logs over OTLP/HTTP for ARC Labs apps.
It is the OpenTelemetry companion to ARCMetrics, which stays dependency-free; opentelemetry-swift
is approved as a dependency **in this package only**.

**Platforms:** iOS 18+
**Swift:** 6.0 tools, Swift 6 language mode
**Products:** `ARCMetricsOTel`, `ARCMetricsOTelMocks` (test doubles)

**Status:** scaffold. Work is tracked in FVRS-348 and ships as milestone PRs M1–M4 to `develop`.

## Build & Test

Use the Xcode MCP (`BuildProject`, `RunAllTests`) — see the studio constitution. Xcode opens an
SPM package by its **directory** path, not `Package.swift`.

**Known toolchain warning (Xcode 27):** linking the test bundle for an iOS simulator emits
`Using sysroot for 'macOS 27.0' but targeting 'arm64-apple-ios18.0.0-simulator'
[-Wincompatible-sysroot]`. It reproduces in a fresh trivial package (same in ARCMetrics) and has
no `Package.swift` lever. The library targets themselves are warning-free — check those.

```bash
make lint      # SwiftLint
make format    # SwiftFormat (dry run)
make fix       # Apply SwiftFormat
```

## Git Workflow

Gitflow: `main` (releases, tags) + `develop` (integration). Branches
`feature/FVRS-XXX-description`; Conventional Commits. Release tags go on `main`.
