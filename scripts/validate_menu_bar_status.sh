#!/usr/bin/env bash
set -euo pipefail

API="${SPACESULTIMATE_API:-http://127.0.0.1:37655}"
EXPECTED_EXECUTABLE="${SPACESULTIMATE_EXPECTED_EXECUTABLE:-$HOME/Applications/SpacesUltimate.app/Contents/MacOS/SpacesUltimate}"
STATUS_JSON="$(mktemp)"

cleanup() {
  rm -f "$STATUS_JSON"
}
trap cleanup EXIT

curl -fsS "$API/status" >"$STATUS_JSON"

python3 - "$STATUS_JSON" "$EXPECTED_EXECUTABLE" <<'PY'
import json
import sys

status_path, expected_executable = sys.argv[1], sys.argv[2]
with open(status_path, "r", encoding="utf-8") as handle:
    status = json.load(handle)

failures = []
app_identity = status.get("appIdentity") or {}
menu_bar = status.get("menuBar") or {}
menu_items = menu_bar.get("menuItemTitles") or []
settings = status.get("settings") or {}

if app_identity.get("executablePath") != expected_executable:
    failures.append(
        f"expected executable {expected_executable!r}, got {app_identity.get('executablePath')!r}"
    )

if menu_bar.get("isVisible") is not True:
    failures.append("menuBar.isVisible is not true")

badge_text = menu_bar.get("badgeText") or ""
if not badge_text.startswith("D") or len(badge_text) < 2:
    failures.append(f"menuBar.badgeText does not look like a Desktop badge: {badge_text!r}")

if int(menu_bar.get("screenCount") or 0) < 1:
    failures.append(f"menuBar.screenCount is invalid: {menu_bar.get('screenCount')!r}")

expected_items = [
    "SpacesUltimate Settings...",
    "Open Space Editor",
    "Open Overview",
    "Show Desktop Notes Overlay",
    "Status Item Display",
    "Debug Panel",
    "Refresh Spaces",
    "Reset Menu Bar Item",
    "Quit SpacesUltimate",
]
missing_items = [item for item in expected_items if item not in menu_items]
if missing_items:
    failures.append(f"menu is missing expected item(s): {', '.join(missing_items)}")

if len(menu_items) < 2 or menu_items[1] != "SpacesUltimate Settings...":
    failures.append("SpacesUltimate Settings... is not the first command after the current Desktop row")

if failures:
    print("Menu bar status validation failed:", file=sys.stderr)
    for failure in failures:
        print(f"- {failure}", file=sys.stderr)
    sys.exit(1)

print("Menu bar status validation passed")
print(f"- executable: {app_identity.get('executablePath')}")
print(f"- badge: {menu_bar.get('badgeText')} title: {menu_bar.get('title')!r}")
print(f"- visible: {menu_bar.get('isVisible')} screens: {menu_bar.get('screenCount')}")
print(f"- menu items: {', '.join(menu_items)}")
PY
