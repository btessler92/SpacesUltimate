#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION_DIR="${SPACESULTIMATE_INSTALL_DIR:-$HOME/Applications}"
APP_NAME="SpacesUltimate.app"
SOURCE_APP="$ROOT/.build/release/$APP_NAME"
DESTINATION_APP="$DESTINATION_DIR/$APP_NAME"
CODESIGN_IDENTITY="${SPACESULTIMATE_CODESIGN_IDENTITY:-}"

if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F '"' '/Apple Development:/{print $2; exit}')"
fi
if [[ -z "$CODESIGN_IDENTITY" ]]; then
  CODESIGN_IDENTITY="-"
fi

cd "$ROOT"
swift build -c release
SPACESULTIMATE_CONFIGURATION=release SPACESULTIMATE_SKIP_BUILD=1 "$ROOT/scripts/build_app.sh" >/dev/null

mkdir -p "$DESTINATION_DIR"
rm -rf "$DESTINATION_APP"
ditto "$SOURCE_APP" "$DESTINATION_APP"
codesign --force --deep --sign "$CODESIGN_IDENTITY" "$DESTINATION_APP" >/dev/null

echo "$DESTINATION_APP"
echo "Signed with: $CODESIGN_IDENTITY"
echo "Launch with:"
echo "SPACESULTIMATE_APP=\"$DESTINATION_APP\" ./scripts/launch_app.sh"
