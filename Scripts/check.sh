#!/usr/bin/env bash
# Build with warnings as errors, lint formatting, run all tests. Non-zero exit on any failure.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift build (warnings as errors)"
swift build -Xswiftc -warnings-as-errors

echo "==> swift format lint"
swift format lint --strict --recursive Sources Tests

echo "==> swift test"
# With only the Command Line Tools, SwiftPM's build system does not load the Swift Testing macro plugin
# by itself ("plugin for module 'TestingMacros' not found"). Point the compiler at it when it exists.
TESTING_PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [[ -d "$TESTING_PLUGINS" ]]; then
  swift test -Xswiftc -plugin-path -Xswiftc "$(cd "$TESTING_PLUGINS" && pwd)"
else
  swift test
fi

echo "OK: all checks passed."
