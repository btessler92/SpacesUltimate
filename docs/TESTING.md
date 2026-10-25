# Development and testing

Use macOS 14+, Xcode with Swift 6+, and Python 3 for script checks. Start with:

```sh
make test
```

This runs Swift unit tests, script tests with fake commands, and debug bundle
verification. It does not launch the app, require the control API, or change your
installed copy. CI also builds and verifies a release bundle on Apple silicon
and Intel runners.

## Commands

| Command | Purpose |
| --- | --- |
| `make build` | Build the debug executable. |
| `make app` / `make app-release` | Build a debug/release `.app` under `.build/`. |
| `make verify` | Build and verify the debug bundle's identity, icon, and signature. |
| `make unit-test` / `make script-test` | Run only the Swift/script tests. |
| `make install` | Rebuild release and replace `~/Applications/SpacesUltimate.app`. |
| `make launch` | Open the installed app, installing it first if absent; reuse a running instance. |
| `make quit` | Quit SpacesUltimate, with a process-termination fallback if the API is unavailable. |
| `make package` | Produce an ad-hoc-signed local test ZIP. See [Distribution](DISTRIBUTION.md) for public releases. |
| `make status` / `make smoke` | Read live API status / run read-only endpoint checks. Requires opt-in API. |

Quit before replacing an installed bundle. Prefer Finder when manually opening
an installed build so macOS can attribute permissions to the intended app.
`SPACESULTIMATE_INSTALL_DIR` overrides the install directory;
`SPACESULTIMATE_APP` selects an existing bundle for the launch helper. A missing
custom path fails instead of building a different copy.

## Control API

Enable **Settings → Advanced → control API** in the running app. It defaults to
`http://127.0.0.1:37655`; script helpers accept `SPACESULTIMATE_API` to override it.
Use `SPACESULTIMATE_WAIT_FOR_API=1 ./scripts/launch_app.sh` if a script needs to
wait for API startup. Regular app launch does not depend on the API.

```sh
make smoke
curl -fsS 'http://127.0.0.1:37655/status'
./scripts/open_editor.sh
./scripts/validate_menu_bar_status.sh
```

The editor helper requires an already-running app with the API enabled. It only
requests the editor; it does not change hotkeys, HUD, onboarding, or other settings.
The menu bar validator checks bundle identity and menu configuration. Inspect the
screen and click the badge yourself: `isVisible` is not proof of on-screen visibility.
For a development bundle, set `SPACESULTIMATE_EXPECTED_EXECUTABLE` to its executable path.

The smoke test checks read-only endpoints and JSON responses, printing pass/fail
lines rather than private payloads. It does not refresh detection, show UI, change
settings, capture screenshots, or write diagnostic exports. The former destructive
mode and `smoke-destructive` target were removed; resets belong in manual tests
with disposable data. The old `SPACESULTIMATE_SKIP_SCREENSHOTS` flag is unnecessary.

[AppControlAPI.swift](../Sources/SpacesUltimate/AppControlAPI.swift) is the endpoint
reference; unknown routes also return a list of examples with HTTP 404. Some GET
routes **perform actions**, including config writes, switching, and quitting.
Quote URLs containing `?` or `&` in shell commands. Read [Security](../SECURITY.md)
before exposing this optional local control surface.

## Manual release checks

Use disposable test data for resets, imports, recovery, and app assignment changes.
Back up existing config first. `SpaceStore` unit tests use temporary directories;
a normal running app uses your real Application Support directory.

| Area | Check |
| --- | --- |
| Startup and menu bar | Launch from Applications; visually find and click the badge. Check Settings, editor, overview, notes, debug, refresh, and quit. Keep the menu open through several detection polls and confirm commands still work. |
| Hidden status item | Check macOS menu bar controls and menu bar managers. Verify the application Settings menu and ⌘, remain reachable. Test compact and name display modes, crowded bars, and each display that shows status items. |
| Permissions | Confirm the installed bundle path in Debug. Test switching with Accessibility granted and denied, and preview capture with Screen Recording granted and denied. Failure should explain the missing permission. |
| Detection and names | Switch using keys, gestures, Mission Control, and fullscreen apps on one and multiple displays, including empty Desktops. Inspect detection source/confidence after transitions settle. Add/remove/reorder Desktops, reboot, and confirm custom names stay attached where stable IDs are available. |
| Recovery | Test ID outage/recovery, import/export, Backup/Restore, automatic placeholder renumbering, and Repair Names. Confirm ID/Order badges and name-binding diagnostics agree. Corrupt-config tests must preserve the original in `InvalidConfigs`. |
| Overview and previews | Confirm current-Desktop window layouts, cached preview ages, and display-only app rule matches. Switch from a card; failures should leave the overview open with a reason. Test all displays, many Desktops, and custom shortcuts including Desktop 10+. |
| Assignments | Assign visible apps, resolve duplicates, launch assigned apps, and use Switch + Launch. Check opt-in auto-launch on Desktop changes. Existing windows are not moved by these rules. |
| Preferences and login | Check persistence, both hotkeys, screenshot directory, onboarding completion, and Launch at Login from a stable installed bundle. Open/reopen Settings and switch categories without focusing shortcut fields or changing their values. |
| HUD | Independently vary fade-in, hold, fade-out, size, opacity, position, and Desktop number. Preview while automatic HUD is off. Repeated previews or fast Desktop changes must not let an earlier fade dismiss a newer HUD or steal keyboard focus. |
| Defaults | Save a personal preset, change values, restore it, and reset individual sliders. Factory Reset must retain names/notes and the saved preset while applying factory preferences and disabling Launch at Login. Restore Default should still recover the preset. |
| Capture and diagnostics | Explicitly capture previews/screenshots and check nonempty PNGs for every display and the selected output directory. Export diagnostics, verify settings match, and redact private content before sharing. |

## Mission Control notes regression checks

For active-Desktop detection, include a Desktop containing only a window moved
from another Desktop, several moved windows, and an empty Desktop. Menu bar and
notes should agree with the native Desktop, with resolution source
`live macOS current Space UUID`. Recheck with multiple displays and fullscreen
apps. Automated live-reader/resolver tests use fixtures and do not move windows.

- Open Mission Control with keys, gestures, and a hot corner. Notes should appear
  on every display, remain during window dragging, and dismiss on exit unless a
  card interaction has retained them. Repeat across several open/close cycles.
- Click and double-click cards with another app active. Rename and commit with
  Return; the first click must work and a refresh must not discard the edit.
- Test Go with and without Accessibility. A click consumed by Dock should run
  once after Mission Control exits and the mouse releases; dragging away cancels it.
- Native window/thumbnail clicks must keep their normal effect. Background/gap
  clicks keep notes while Mission Control stays open, then dismiss them on exit.
- Close must hide notes immediately and keep them hidden for that Mission Control
  session. After exit, outside clicks and Escape dismiss retained notes. Manually
  opened notes should dismiss on an outside click, including on another display.
- Open Settings while notes are visible. Clicking its menu entry and controls must
  retain notes; opening Settings alone must not show previously hidden notes.
- Right-click and Control-click the badge twice: notes should open then close.
  Normal left-click must still open the menu.
- Test narrow/wide displays, odd/even Desktop counts, long names, and light/dark
  appearance. Check one-row and staggered two-row layouts, Go hit areas, gaps,
  minimum height, note truncation/hover text, and screen bounds.
- Adjust card and background opacity independently; text and geometry must remain
  stable. Confirm scrolling reaches all Settings controls and values persist.

`/overlay/status` includes Mission Control state, mouse observations, and panel/card
frames to help diagnose these failures. Real macOS testing is required because
Dock can consume events that offscreen tests cannot reproduce.

## Offscreen UI previews

These render production views without switching Desktops or editing saved config:

```sh
./scripts/render_notes_layout_previews.sh
# Optional output directory and a config whose names/settings should be previewed:
./scripts/render_notes_layout_previews.sh .spacesultimate/previews/current "$HOME/Library/Application Support/SpacesUltimate/spaces-config.json"

SPACESULTIMATE_HUD_PREVIEW_DIR="$PWD/.spacesultimate/previews/hud" swift test --filter HUDTests
SPACESULTIMATE_PREFERENCES_PREVIEW_DIR="$PWD/.spacesultimate/previews/preferences" swift test --filter PreferenceDefaultsTests
```

Inspect both appearances, compact and wide layouts, minimum-height notes, and all
Preferences category images. Unit tests cover layout/hit regions, mouse tracking,
HUD timing, neutral keyboard focus, legacy settings migration, and preset recovery;
they complement the manual checks above.
