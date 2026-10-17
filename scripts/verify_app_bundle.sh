#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${SPACESULTIMATE_CONFIGURATION:-debug}"
APP="${SPACESULTIMATE_APP:-$ROOT/.build/$CONFIGURATION/SpacesUltimate.app}"
PLIST="$APP/Contents/Info.plist"
EXECUTABLE="$APP/Contents/MacOS/SpacesUltimate"
ICON="$APP/Contents/Resources/SpacesUltimate.icns"

fail() {
  echo "verify_app_bundle: $*" >&2
  exit 1
}

[[ -d "$APP" ]] || fail "missing app bundle: $APP"
[[ -f "$PLIST" ]] || fail "missing Info.plist"
[[ -x "$EXECUTABLE" ]] || fail "missing executable: $EXECUTABLE"
[[ -s "$ICON" ]] || fail "missing icon resource: $ICON"

plutil -lint "$PLIST" >/dev/null

BUNDLE_NAME="$(plutil -extract CFBundleName raw "$PLIST")"
BUNDLE_EXECUTABLE="$(plutil -extract CFBundleExecutable raw "$PLIST")"
BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$PLIST")"
BUNDLE_ICON="$(plutil -extract CFBundleIconFile raw "$PLIST")"

[[ "$BUNDLE_NAME" == "SpacesUltimate" ]] || fail "unexpected CFBundleName: $BUNDLE_NAME"
[[ "$BUNDLE_EXECUTABLE" == "SpacesUltimate" ]] || fail "unexpected CFBundleExecutable: $BUNDLE_EXECUTABLE"
[[ "$BUNDLE_IDENTIFIER" == "local.spacesultimate.menubar" ]] || fail "unexpected CFBundleIdentifier: $BUNDLE_IDENTIFIER"
[[ "$BUNDLE_ICON" == "SpacesUltimate" ]] || fail "unexpected CFBundleIconFile: $BUNDLE_ICON"

codesign --verify --deep --strict "$APP"

echo "Verified $APP"
