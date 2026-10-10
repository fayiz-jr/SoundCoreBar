#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds SoundcoreProbe.app and runs it through LaunchServices, so macOS treats it as its own app
# (and asks for Bluetooth permission for it, not for your terminal). Output goes to build/probe.log
# and is printed when the probe exits.
#
# Usage: scripts/probe.sh [--listen <seconds>] [--device <name substring>]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG="$ROOT/build/probe.log"

"$ROOT/scripts/build-app.sh" SoundcoreProbe debug
: > "$LOG"
echo "Running probe (if macOS asks for Bluetooth permission, click Allow)…"
open -W -n --stdout "$LOG" --stderr "$LOG" "$ROOT/build/SoundcoreProbe.app" --args "$@"
cat "$LOG"
