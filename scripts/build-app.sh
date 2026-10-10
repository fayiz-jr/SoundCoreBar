#!/usr/bin/env bash
# Builds a SwiftPM executable and wraps it in a signed .app bundle under build/.
#
# Usage: scripts/build-app.sh [SoundcoreBar|SoundcoreProbe] [release|debug]
#
# Signs ad-hoc by default. A plain ad-hoc signature is identified by its code hash, which changes
# on every rebuild, so macOS would ask for Bluetooth permission again after each one. To avoid that,
# ad-hoc builds get a designated requirement that matches on the bundle identifier alone.
# To sign with a real identity instead (its requirement then includes your team), run e.g.:
#   SIGN_IDENTITY="Apple Development" scripts/build-app.sh
set -euo pipefail

PRODUCT="${1:-SoundcoreBar}"
CONFIG="${2:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="$ROOT/Resources/$PRODUCT-Info.plist"
APP="$ROOT/build/$PRODUCT.app"

[[ -f "$PLIST" ]] || { echo "No Info.plist for $PRODUCT at $PLIST" >&2; exit 1; }

swift build --package-path "$ROOT" -c "$CONFIG" --product "$PRODUCT"
BIN_DIR="$(swift build --package-path "$ROOT" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp "$PLIST" "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
    codesign --force --sign - --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
else
    codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"
fi
codesign --verify --strict "$APP"
echo "Built $APP (signed with: $([[ "$SIGN_IDENTITY" == "-" ]] && echo ad-hoc || echo "$SIGN_IDENTITY"))"
