#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds SoundcoreBar.app for Apple silicon and Intel and zips it for a GitHub Release.
#
# Usage: scripts/package-release.sh   →   build/SoundcoreBar-<version>.zip
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/SoundcoreBar-Info.plist")"
ZIP="$ROOT/build/SoundcoreBar-$VERSION.zip"

ARCHS="arm64 x86_64" "$ROOT/scripts/build-app.sh" SoundcoreBar release
rm -f "$ZIP"
# ditto keeps the bundle's signature and extended attributes intact, unlike zip.
ditto -c -k --sequesterRsrc --keepParent "$ROOT/build/SoundcoreBar.app" "$ZIP"
echo "Packaged $ZIP"
shasum -a 256 "$ZIP"
