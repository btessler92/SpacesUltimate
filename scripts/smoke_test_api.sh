#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"
if [[ "${SPACESULTIMATE_DESTRUCTIVE:-0}" == "1" ]]; then
  echo "Destructive smoke testing was removed. Use the manual checklist with disposable test data." >&2
  exit 1
fi

RESPONSE="$(mktemp)"
trap 'rm -f "$RESPONSE"' EXIT

# Only read state: no settings writes, refreshes, UI actions, exports, or captures.
for endpoint in status login-item/status config/backups config/invalid config/name-bindings settings/defaults rules/suggestions previews/status overlay/status; do
  curl -fsS --connect-timeout 2 --max-time 10 "$API/$endpoint" >"$RESPONSE"
  python3 - "$RESPONSE" "$endpoint" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
if not isinstance(payload, dict) or payload.get("ok") is False or "error" in payload:
    raise SystemExit(f"FAIL /{sys.argv[2]}: unexpected API response")
if sys.argv[2] == "status" and payload.get("app") != "SpacesUltimate":
    raise SystemExit("FAIL /status: not a SpacesUltimate response")
print(f"PASS /{sys.argv[2]}")
PY
done

echo "Read-only API smoke test passed. UI behavior requires manual checks (docs/TESTING.md)."
