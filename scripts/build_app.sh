#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${SPACESULTIMATE_CONFIGURATION:-debug}"
BUILD_DIR="$ROOT/.build/$CONFIGURATION"
APP="$BUILD_DIR/SpacesUltimate.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
BINARY="${SPACESULTIMATE_BINARY:-$BUILD_DIR/SpacesUltimate}"

cd "$ROOT"
if [[ "${SPACESULTIMATE_SKIP_BUILD:-0}" != "1" ]]; then
  if [[ "$CONFIGURATION" == "release" ]]; then
    swift build -c release
  else
    swift build
  fi
fi

if [[ ! -x "$BINARY" ]]; then
  echo "Missing $BINARY. Run swift build first." >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$MACOS" "$RESOURCES"
cp "$BINARY" "$MACOS/SpacesUltimate"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
if [[ -f "$ROOT/Resources/SpacesUltimate.icns" ]]; then
  cp "$ROOT/Resources/SpacesUltimate.icns" "$RESOURCES/SpacesUltimate.icns"
fi
chmod +x "$MACOS/SpacesUltimate"
cp "$ROOT/LICENSE" "$RESOURCES/LICENSE"
codesign --force --deep --sign - "$APP" >/dev/null

echo "$APP"
