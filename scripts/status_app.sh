#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"

if curl -fsS "$API/status"; then
  echo
  exit 0
fi

echo "SpacesUltimate API is not reachable at $API" >&2
exit 1
