#!/usr/bin/env bash
# Runs the unit tests. With only the Command Line Tools installed, SwiftPM does not find
# swift-testing's macro plugin on its own, so point it there when that directory exists.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
EXTRA=()
[[ -d "$PLUGINS" ]] && EXTRA=(-Xswiftc -plugin-path -Xswiftc "$PLUGINS")

swift test --package-path "$ROOT" ${EXTRA[@]+"${EXTRA[@]}"} "$@"
