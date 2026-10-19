#!/usr/bin/env bash
# Local coverage gate — mirrors the CI `Build (macOS)` job.
#
# Usage: scripts/coverage.sh [simulator-name]   (default: iPhone 18 Pro)
#
# Builds and runs the tests on an iOS simulator with code coverage, then applies the
# 100% gate from scripts/check-coverage.py. The Xcode MCP has no coverage output, so
# this is the one sanctioned CLI path (user decision 2026-10-08). Use the Xcode MCP
# for every other build and test run.
set -euo pipefail

cd "$(dirname "$0")/.."
SIMULATOR="${1:-iPhone 18 Pro}"
RESULT=".build/coverage/TestResults.xcresult"

rm -rf "$RESULT"
mkdir -p "$(dirname "$RESULT")"

xcodebuild test \
    -quiet \
    -scheme ARCMetricsOTel-Package \
    -destination "platform=iOS Simulator,name=$SIMULATOR" \
    -enableCodeCoverage YES \
    -resultBundlePath "$RESULT" \
    CODE_SIGNING_ALLOWED=NO

python3 scripts/check-coverage.py "$RESULT" 100 ARCMetricsOTel ARCMetricsOTelMocks
