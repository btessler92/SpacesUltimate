#!/usr/bin/env bash
set -euo pipefail
NOTES_PREVIEW_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTES_PREVIEW_BUILD_DIR="$(mktemp -d /tmp/spacesultimate-notes-preview.XXXXXX)"
trap 'rm -rf "$NOTES_PREVIEW_BUILD_DIR"' EXIT
swiftc -o "$NOTES_PREVIEW_BUILD_DIR/render-notes-previews" \
  "$NOTES_PREVIEW_ROOT/Sources/SpacesUltimate/Models.swift" \
  "$NOTES_PREVIEW_ROOT/Sources/SpacesUltimate/KeyboardShortcut.swift" \
  "$NOTES_PREVIEW_ROOT/Sources/SpacesUltimate/InlineEditableNameField.swift" \
  "$NOTES_PREVIEW_ROOT/Sources/SpacesUltimate/NotesOverlayLayout.swift" \
  "$NOTES_PREVIEW_ROOT/Sources/SpacesUltimate/LabelOverlayView.swift" \
  "$NOTES_PREVIEW_ROOT/scripts/render_notes_layout_previews.swift"
"$NOTES_PREVIEW_BUILD_DIR/render-notes-previews" "${1:-$NOTES_PREVIEW_ROOT/.spacesultimate/previews/adaptive-notes}" "${@:2}"
