#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/.build/release/SpacesUltimate.app"
ARTIFACT_DIR="$ROOT/.build/artifacts"
ZIP="$ARTIFACT_DIR/SpacesUltimate.zip"

SPACESULTIMATE_CONFIGURATION=release "$ROOT/scripts/build_app.sh" >/dev/null

mkdir -p "$ARTIFACT_DIR"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "$ZIP"
