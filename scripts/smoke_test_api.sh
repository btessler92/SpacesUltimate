#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"
STATUS_FILE="$(mktemp -t spacesultimate-status.XXXXXX.json)"
trap 'rm -f "$STATUS_FILE"' EXIT

echo "== Status =="
curl -fsS "$API/status" | tee "$STATUS_FILE"
echo

echo "== Refresh =="
curl -fsS "$API/refresh"
echo

echo "== Login Item Status =="
curl -fsS "$API/login-item/status"
echo

echo "== Config Backups =="
curl -fsS "$API/config/backups"
echo

echo "== Preferences Show =="
curl -fsS "$API/preferences/show"
echo

echo "== Rule Suggestions =="
curl -fsS "$API/rules/suggestions"
echo

echo "== Preview Status =="
curl -fsS "$API/previews/status"
echo

if [[ "${SPACESULTIMATE_DESTRUCTIVE:-0}" == "1" ]]; then
  echo "== Assign Visible Apps To Desktop 1 =="
  curl -fsS "$API/rules/assign-visible?space=1"
  echo
  echo "== Resolve Duplicate App Rules =="
  curl -fsS "$API/rules/resolve-duplicates"
  echo
fi

echo "== HUD Desktop 1 =="
curl -fsS "$API/hud?space=1"
echo

echo "== Settings Update Round Trip =="
RESTORE_SETTINGS_QUERY="$(python3 - "$STATUS_FILE" <<'PY'
import json
import sys
from urllib.parse import urlencode

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    settings = json.load(handle)["settings"]

print(urlencode({
    "hudEnabled": str(settings["hudEnabled"]).lower(),
    "hudDuration": settings["hudDurationSeconds"],
    "apiEnabled": str(settings["apiEnabled"]).lower(),
    "globalHotkeyEnabled": str(settings["globalHotkeyEnabled"]).lower(),
    "globalHotkeyShortcut": settings["globalHotkeyShortcut"],
    "autoLaunchAssignedApps": str(settings["autoLaunchAssignedApps"]).lower(),
    "onboardingCompleted": str(settings["onboardingCompleted"]).lower(),
    "screenshotDirectoryPath": settings["screenshotDirectoryPath"],
    "menuBarDisplayMode": settings["menuBarDisplayMode"],
    "menuBarLabelPosition": settings["menuBarLabelPosition"],
}))
PY
)"
curl -fsS "$API/settings/update?hudEnabled=true&hudDuration=1.2&apiEnabled=true&globalHotkeyEnabled=false&globalHotkeyShortcut=Control%2BOption%2BSpace&autoLaunchAssignedApps=false&onboardingCompleted=true&menuBarDisplayMode=numberAndName&menuBarLabelPosition=rightOfCenter"
echo
curl -fsS "$API/settings/update?$RESTORE_SETTINGS_QUERY" >/dev/null

if [[ "${SPACESULTIMATE_DESTRUCTIVE:-0}" == "1" ]]; then
  echo "== Config Update Desktop 1 =="
  curl -fsS "$API/config/update?space=1&name=Focus&color=%232F80ED&icon=F&apps=Codex,Terminal"
  echo
fi

echo "== Overview Show =="
curl -fsS "$API/overview/show"
echo

echo "== Labels Show/Hide =="
curl -fsS "$API/labels/show"
echo
curl -fsS "$API/labels/hide"
echo

echo "== Screenshot =="
SCREEN_CAPTURE_TRUSTED="$(python3 - "$STATUS_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    print(str(json.load(handle).get("screenCaptureTrusted", False)).lower())
PY
)"
if [[ "$SCREEN_CAPTURE_TRUSTED" == "true" && "${SPACESULTIMATE_SKIP_SCREENSHOTS:-0}" != "1" ]]; then
  echo "== Capture Desktop 1 Preview =="
  curl -fsS "$API/previews/capture?space=1"
  echo

  SCREENSHOT_FILE="$(mktemp -t spacesultimate-screenshot.XXXXXX.json)"
  curl -fsS "$API/screenshot" | tee "$SCREENSHOT_FILE"
  python3 - "$SCREENSHOT_FILE" <<'PY'
import json
import os
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    payload = json.load(handle)

if not payload.get("ok"):
    raise SystemExit("screenshot endpoint did not return ok=true")

files = payload.get("files", [])
if not files:
    raise SystemExit("screenshot endpoint returned no files")

for path in files:
    if not os.path.isfile(path):
        raise SystemExit(f"screenshot file missing: {path}")
    if os.path.getsize(path) == 0:
        raise SystemExit(f"screenshot file is empty: {path}")
    with open(path, "rb") as image:
        if image.read(8) != b"\x89PNG\r\n\x1a\n":
            raise SystemExit(f"screenshot file is not a PNG: {path}")

print(f"Validated {len(files)} screenshot PNG file(s).")
PY
  rm -f "$SCREENSHOT_FILE"
else
  echo "Skipped: Screen Recording is not granted or SPACESULTIMATE_SKIP_SCREENSHOTS=1."
fi
echo

echo "== Diagnostics Export =="
curl -fsS "$API/diagnostics/export"
echo

echo "== Overview Hide =="
curl -fsS "$API/overview/hide"
echo

if [[ "${SPACESULTIMATE_DESTRUCTIVE:-0}" == "1" ]]; then
  echo "== Reset Config =="
  curl -fsS "$API/config/reset"
  echo
fi
