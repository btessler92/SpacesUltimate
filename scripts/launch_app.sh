#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${SPACESULTIMATE_CONFIGURATION:-debug}"
DEFAULT_APP="$HOME/Applications/SpacesUltimate.app"
APP="${SPACESULTIMATE_APP:-$DEFAULT_APP}"
API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"

if [[ ! -d "$APP" ]]; then
  if [[ "$APP" == "$DEFAULT_APP" ]]; then
    "$ROOT/scripts/install_app.sh" >/dev/null
  else
    SPACESULTIMATE_CONFIGURATION="$CONFIGURATION" "$ROOT/scripts/build_app.sh" >/dev/null
  fi
fi

"$ROOT/scripts/quit_app.sh" >/dev/null 2>&1 || true
open -n "$APP"
echo "Launched $APP"
# The developer API is opt-in; launching a normal app must not depend on it.
if [[ "${SPACESULTIMATE_WAIT_FOR_API:-0}" != "1" ]]; then
  exit 0
fi
for _ in {1..80}; do
  if curl -fsS "$API/status" >/dev/null 2>&1; then
    echo "API ready: $API/status"
    exit 0
  fi
  sleep 0.25
done

echo "API not reachable yet: $API/status" >&2
echo "The app may still be starting, or the localhost API may be disabled in Preferences." >&2
exit 1
