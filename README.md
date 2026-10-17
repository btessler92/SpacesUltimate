# SpacesUltimate

SpacesUltimate is a stability-first macOS menu bar app that labels native macOS Spaces instead of replacing them. Native Spaces and Mission Control remain the backend; this app adds a visible UI layer for names, colors, a transient HUD, an editor, a custom overview, and diagnostics.

Free and open source under the [MIT license](LICENSE). Requires **macOS 14 or newer**.

- [Releases](https://github.com/btessler92/SpacesUltimate/releases)
- [Report a bug](https://github.com/btessler92/SpacesUltimate/issues)
- [Contribute](CONTRIBUTING.md) · [Privacy](docs/PRIVACY.md) · [Security](SECURITY.md)

This is an early-stage utility. Check each release's signing status before downloading.
The full-featured app is distributed outside the Mac App Store because its Spaces
detection and switching rely on capabilities incompatible with App Sandbox.
See [Distribution](docs/DISTRIBUTION.md) for signing and release instructions.

## Quick start from source

Install Xcode with Swift 6 or newer, then:

```sh
git clone https://github.com/btessler92/SpacesUltimate.git
cd SpacesUltimate
make install
open ~/Applications/SpacesUltimate.app
```

Open the menu bar item to edit Desktop names and notes. Grant Accessibility if
you want click-to-switch, and Screen Recording if you want preview thumbnails.
The developer control API is optional and off by default for new installations.

## Reference Takeaways

- FastMissionControl demonstrates that a fast custom Mission Control-style overview can be useful when it avoids Dock internals and keeps layout work lightweight.
- rename-spaces demonstrates the right stability posture for Space naming: store metadata by Space ID when `com.apple.spaces` exposes IDs, fall back to ordered Desktop labels, and be explicit about heuristic overlays.

## MVP Architecture

- `SpaceStore`: stores JSON config in `~/Library/Application Support/SpacesUltimate/spaces-config.json`, reconciles detected Space IDs with order fallback, remembers prior stable-ID metadata for recovery after ID outages/removals, imports/exports config.
- `SpaceDetector`: polls safely, reads Dock Spaces preferences through CoreFoundation with plist/UserDefaults fallbacks, runs delayed settling refreshes after macOS Space-change notifications, infers active Desktop conservatively, and emits active-space changes.
- `WindowScanner`: scans visible windows via public CGWindow APIs and requests Accessibility permission for later richer scanning.
- `NativeBridge`: isolates switching. MVP uses Accessibility-gated keyboard automation, preferring relative `Control+Left/Right` moves when the current Desktop is known and falling back to `Control+1...Control+9`.
- `MenuBarController`: shows a visible active Desktop number badge/label with configurable placement, full name in the tooltip/menu, and editor, overview, debug, and refresh actions.
- `SpaceEditorWindowController`: AppKit editor for name, color, icon, desktop note, optional switch shortcut, suggested app rules, per-Desktop visible-app assignment, assigned-app launch flows, name binding status, and conservative name repair.
- `HUDController`: non-activating multi-monitor HUD for Space changes.
- `OverviewController`: fast custom overview with large colored Space cards, live current-desktop window mini-layouts, cached Space preview thumbnails, display-only rule matches, and visible switch failure feedback.
- `RuleEngine`: evaluates display-only app-to-Space suggestions and duplicate assignments with forgiving app-name matching.
- `DebugWindowController`: diagnostics for permissions, known Spaces, config path, visible windows, and logs.
- `DiagnosticsService`: exports a JSON bug-report snapshot from the debug panel or API.

## Current Limitations

- This does not rename Spaces at the system level.
- Space IDs depend on Dock preferences being readable and shaped as expected; otherwise labels follow Desktop order.
- Window-to-Space association is not reliable in public APIs, so inactive Space cards show only rule-based suggestions.
- Switching requires Accessibility permission for the installed app and compatible macOS Mission Control keyboard shortcuts. If Accessibility is not granted for the exact installed app path, click-to-switch is disabled instead of pretending it worked.
- Notes open automatically when Mission Control opens and stay visible during actions that keep it open. Clicking a card keeps notes available even if Mission Control exits; outside clicks dismiss retained notes afterward. Detection observes Dock window metadata and remains heuristic across macOS versions. Native window moving is not implemented.

## Desktop Notes

Open Mission Control to show Desktop Notes on every connected display. Notes stay visible while moving windows, rearranging Desktops, or performing other actions that leave Mission Control open. Clicking a notes card keeps the overlay open, including when that click exits Mission Control; double-click its name to rename it. An outside click during Mission Control waits to dismiss notes until Mission Control exits. Outside clicks after Mission Control has exited dismiss notes immediately. Close always dismisses notes, and they stay hidden until the next Mission Control session. Escape remains available to exit Mission Control or dismiss retained notes afterward.

Each notes card shows a large Desktop number to the left of its name and a **Go →** button. The button uses that Desktop’s configured shortcut, or the existing relative Space-switching fallback, and keeps the notes open. Switching requires Accessibility permission for the installed SpacesUltimate app; an unsuccessful request leaves notes visible and explains the problem.

Notes adapt separately to each display. If a single row would hide more than half of any Desktop name, and a second row can make the cards wider, the overlay uses two staggered rows. In this layout, a small square **Go** button sits inside the right edge of each card, keeping both rows compact: the default 64-pixel setting produces a 104-pixel overlay. Odd-numbered positions appear above the following even-numbered positions, with the lower row shifted to the right. Notes sit below the name; truncated notes show their full text on hover. Displays with enough room keep the original single-row layout. The height is capped to fit the display.

You can also open notes from the menu, the configurable notes shortcut, or by right-clicking (or Control-clicking) the menu bar badge. Manually opened notes support the same outside-click dismissal.

Opening SpacesUltimate Settings keeps visible notes open, and clicks in Settings or its menu leave them available. **Notes card opacity** and **Notes background opacity** have separate sliders and Default buttons; changes preview immediately without rebuilding the overlay. The background can be made completely transparent while keeping the cards and text visible.

Preferences has a sidebar for **Desktop Notes**, **HUD & Overview**, **Menu Bar**, **Startup**, **Screenshots**, **Permissions**, **Advanced**, and **Defaults & Reset**. Desktop Notes opens first, with its appearance controls and keyboard shortcut together. Category changes and reopening keep neutral keyboard focus until you select a text field.

In **HUD & Overview**, adjust **Fade in**, **Fully visible**, and **Fade out** independently. Fade out supports up to 10 seconds for a slow disappearance. HUD appearance controls include size, background opacity, five screen positions, and whether to show the Desktop number. **Test HUD for Current Desktop** previews the current Desktop on each display, using your selected settings even when automatic HUD notifications are off. It does not switch Desktops or take keyboard focus. Repeated previews replace the previous HUD cleanly. Existing fade timing is preserved until you change it; all new HUD preferences participate in saved defaults and factory reset.

In **Preferences → Defaults & Reset**, **Save Current as Default** saves a separate preset of your current preferences, including Launch at Login. **Restore Default** applies that preset; until you save one, it uses the factory settings. **Factory Reset** applies the original preferences and turns Launch at Login off while keeping your saved preset available. Desktop names, notes, assignments, macOS permissions, and onboarding history are preserved. **Show default values** compares your default with the factory values, and the slider labels show their default values. Saving a new default does not change the original factory values. Existing installations keep their current preferences until a restore button is used.

## Build

```sh
swift build
```

Or use the convenience targets:

```sh
make build
make launch
make smoke
make quit
```

Install a release build into `~/Applications`:

```sh
make install
```

Create a zipped release app:

```sh
make package
```

Run from source:

```sh
swift run SpacesUltimate
```

Build a development `.app` bundle:

```sh
./scripts/build_app.sh
```

Launch or quit the installed app:

```sh
./scripts/launch_app.sh
./scripts/quit_app.sh
./scripts/status_app.sh
./scripts/validate_menu_bar_status.sh
```

`./scripts/launch_app.sh` now defaults to `~/Applications/SpacesUltimate.app`. Set `SPACESULTIMATE_APP` to a different `.app` path when intentionally testing a development bundle.

Open the installed app directly into the Space Editor with the app hotkey disabled:

```sh
./scripts/open_editor.sh
```

SpacesUltimate runs as a menu bar app. Use the menu bar badge, `./scripts/open_editor.sh`, or the local API to reopen the editor after launch.

Quit the installed app and wait for the process to exit:

```sh
./scripts/quit_app.sh
```

Enable **Preferences → Advanced → Enable localhost control API** before using
the developer scripts or `make smoke`. Existing explicit API preferences are
preserved. The API accepts command-line requests on IPv4 loopback only; browser
requests are rejected. Other local programs can use it while enabled, so turn
it off when finished. See [Security](SECURITY.md).

The local test/control API listens on:

```sh
curl http://127.0.0.1:37655/status
curl http://127.0.0.1:37655/hud?space=1
curl http://127.0.0.1:37655/overview/show
curl http://127.0.0.1:37655/overlay/show
curl http://127.0.0.1:37655/overlay/hide
curl http://127.0.0.1:37655/labels/show
curl http://127.0.0.1:37655/labels/hide
curl http://127.0.0.1:37655/rules/suggestions
curl http://127.0.0.1:37655/previews/status
curl http://127.0.0.1:37655/previews/capture?space=1
curl http://127.0.0.1:37655/rules/assign-visible?space=1
curl http://127.0.0.1:37655/rules/resolve-duplicates
curl 'http://127.0.0.1:37655/apps/launch?space=1&switch=true'
curl 'http://127.0.0.1:37655/config/update?space=1&name=MATLAB&color=%232F80ED&icon=M&note=Analysis'
curl http://127.0.0.1:37655/config/backups
curl http://127.0.0.1:37655/config/invalid
curl http://127.0.0.1:37655/config/backup
curl http://127.0.0.1:37655/config/restore-latest
curl http://127.0.0.1:37655/config/name-bindings
curl http://127.0.0.1:37655/config/repair-names
curl http://127.0.0.1:37655/screenshot
curl http://127.0.0.1:37655/diagnostics/export
```

The menu bar validation script checks the installed app path, confirms the native status item is visible, verifies the `D#` badge/title, and asserts the expected dropdown commands are present in `/status`.

## Menu Bar Status Item Notes

SpacesUltimate uses a normal AppKit `NSStatusItem` with a retained `NSMenu`, not a custom overlay. Keep these details intact when changing the menu icon:

- The app bundle intentionally does not set `LSUIElement`; `AppDelegate` sets a regular activation policy at launch. This matches the known-working status-item behavior and avoids agent-app edge cases where the item can exist in Accessibility/API state but not render visibly.
- The bundle identifier is `local.spacesultimate.menubar`. macOS can preserve hidden or stale menu-bar placement state by bundle identifier, so changing away from the old identifier broke that stale state and made the item visible again.
- The status item does not use `autosaveName`; `MenuBarStatusItemDefaults.autosaveName` is `"none"` and reset code only clears legacy names. Reintroducing autosave can revive stale placement/visibility.
- The visible badge is text (`D#`, optionally with name) via `button.attributedTitle`, with `statusItem.length` sized from the attributed title. This proved more reliable than image-only variants during visual testing.
- On multi-display setups, the badge currently follows the macOS main monitor path via `SpaceDetector.mainDisplayStatus()`. That path prefers the Dock monitor record marked `Main` and falls back through visible-window matching when Dock has stale or duplicate monitor records.
- Verify visually with per-display screenshots when debugging. The item and dropdown may be on a different menu bar than the built-in display, so a single full/built-in capture can look like a false failure.

The `/status` and diagnostics export include the latest Space detection source, event, timestamp, active Space, detected Space count, confidence, Dock monitor/current-Space details, visible-window match candidates, and ambiguity notes.

Run the API smoke test after launching the app:

```sh
./scripts/smoke_test_api.sh
```

The smoke test avoids config changes by default. To include config update/reset checks:

```sh
SPACESULTIMATE_DESTRUCTIVE=1 ./scripts/smoke_test_api.sh
```

## Docs

- [Architecture](docs/ARCHITECTURE.md)
- [Roadmap](docs/ROADMAP.md)
- [Testing](docs/TESTING.md)
- [Changelog](docs/CHANGELOG.md)
- [Repo Hygiene](docs/REPO_HYGIENE.md)
- [Distribution](docs/DISTRIBUTION.md)
- [Privacy](docs/PRIVACY.md)
- [Contributing](CONTRIBUTING.md)
