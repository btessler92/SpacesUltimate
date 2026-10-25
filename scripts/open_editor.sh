#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"

# Opening the editor must not restart the app or change the user's preferences.
if ! curl -fsS --connect-timeout 2 --max-time 10 "$API/editor/show" >/dev/null; then
  echo "Could not open the editor. Launch SpacesUltimate and enable the control API in Settings → Advanced, or choose Open Space Editor from the menu bar." >&2
  exit 1
fi

echo "SpacesUltimate editor opened."
