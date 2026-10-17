#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${SPACESULTIMATE_APP:-$HOME/Applications/SpacesUltimate.app}"
API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"

if [[ ! -d "$APP" ]]; then
  "$ROOT/scripts/install_app.sh" >/dev/null
fi

SPACESULTIMATE_APP="$APP" "$ROOT/scripts/launch_app.sh" >/dev/null
curl -fsS "$API/settings/update?hudEnabled=true&hudDuration=1.0&apiEnabled=true&globalHotkeyEnabled=false&onboardingCompleted=true" >/dev/null
curl -fsS "$API/editor/show" >/dev/null

echo "SpacesUltimate editor opened from $APP"
echo "Global overview hotkey is disabled to avoid Mission Control conflicts."
