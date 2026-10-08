# Changelog

All notable changes to ARCMetricsOTel will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Package scaffold: `ARCMetricsOTel` and `ARCMetricsOTelMocks` products, ARCDevTools integration.
- CI runs the tests on an iOS simulator with a 100% line-coverage gate (`scripts/check-coverage.py`); `scripts/coverage.sh` runs the same gate locally.
- ADR 0001 records the opentelemetry-swift dependency and its known upstream debt.
