#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IDENTITY="${SPACESULTIMATE_CODESIGN_IDENTITY:-}"
PROFILE="${SPACESULTIMATE_NOTARY_PROFILE:-}"
UNSIGNED="${SPACESULTIMATE_UNSIGNED:-0}"

if [[ "$UNSIGNED" != "1" ]]; then
  if [[ "$IDENTITY" != "Developer ID Application:"* || -z "$PROFILE" ]]; then
    echo 'Set SPACESULTIMATE_CODESIGN_IDENTITY to a Developer ID Application certificate name and SPACESULTIMATE_NOTARY_PROFILE to a notarytool Keychain profile.' >&2
    echo 'For local testing only, set SPACESULTIMATE_UNSIGNED=1.' >&2
    exit 1
  fi
fi

cd "$ROOT"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
SPACESULTIMATE_CONFIGURATION=release SPACESULTIMATE_SKIP_BUILD=1 \
  SPACESULTIMATE_BINARY="$BIN_DIR/SpacesUltimate" "$ROOT/scripts/build_app.sh" >/dev/null

APP="$ROOT/.build/release/SpacesUltimate.app"
ARTIFACT_DIR="$ROOT/.build/artifacts"
VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
mkdir -p "$ARTIFACT_DIR"
ARCHITECTURES=" $(lipo -archs "$APP/Contents/MacOS/SpacesUltimate") "
for ARCH in arm64 x86_64; do
  if [[ "$ARCHITECTURES" != *" $ARCH "* ]]; then
    echo "Missing $ARCH in release executable: $ARCHITECTURES" >&2
    exit 1
  fi
done

if [[ "$UNSIGNED" == "1" ]]; then
  ZIP="$ARTIFACT_DIR/SpacesUltimate-$VERSION-universal-unsigned.zip"
  echo 'Local test build only: ad-hoc signed, not notarized. Do not describe this as a trusted public binary.' >&2
else
  ZIP="$ARTIFACT_DIR/SpacesUltimate-$VERSION-universal.zip"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
  codesign --verify --deep --strict "$APP"
  SUBMISSION="$ARTIFACT_DIR/notarization-submission.zip"
  rm -f "$SUBMISSION"
  ditto -c -k --keepParent "$APP" "$SUBMISSION"
  xcrun notarytool submit "$SUBMISSION" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  rm -f "$SUBMISSION"
fi

SPACESULTIMATE_CONFIGURATION=release "$ROOT/scripts/verify_app_bundle.sh"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
cd "$ARTIFACT_DIR"
shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256"
echo "$ZIP"
