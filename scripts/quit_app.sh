#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"
PROCESS_PATTERN="SpacesUltimate.app/Contents/MacOS/SpacesUltimate"

wait_for_exit() {
  for _ in {1..40}; do
    if ! pgrep -f "$PROCESS_PATTERN" >/dev/null; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

if curl -fsS "$API/app/quit" >/dev/null; then
  echo "Requested quit through $API/app/quit"
  if wait_for_exit; then
    echo "SpacesUltimate exited"
    exit 0
  fi
  echo "API quit did not finish in time; falling back to TERM" >&2
else
  echo "API quit failed; falling back to TERM" >&2
fi

pkill -TERM -f "$PROCESS_PATTERN" || true
if wait_for_exit; then
  echo "SpacesUltimate exited after TERM"
else
  echo "SpacesUltimate still appears to be running after TERM" >&2
  exit 1
fi
