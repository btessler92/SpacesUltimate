# Testing

## Build

```sh
swift build
```

## Unit Tests

```sh
swift test
make unit-test
```

The unit suite includes Space naming/reconciliation coverage for stable-ID reorder, temporary stable-ID outage, removed Space reappearance, automatic placeholder renumbering, and malformed config normalization.
It also covers name binding summaries and conservative repair of automatic order-fallback names from stable-ID history.
Invalid startup config preservation is covered too: corrupt JSON is copied into `InvalidConfigs` before defaults are written.

## Package

```sh
./scripts/build_app.sh
SPACESULTIMATE_CONFIGURATION=release ./scripts/build_app.sh
make verify
```

## Install Locally

```sh
./scripts/install_app.sh
```

The default install location is `~/Applications/SpacesUltimate.app`.
Override it with `SPACESULTIMATE_INSTALL_DIR=/path/to/dir`.

## Launch

```sh
./scripts/launch_app.sh
```

The launcher defaults to `~/Applications/SpacesUltimate.app` so manual tests use the same installed copy that appears in Launchpad/Finder. To intentionally run a development bundle, pass `SPACESULTIMATE_APP=/path/to/SpacesUltimate.app`.

To launch the installed app and open the editor with SpacesUltimate's global hotkey disabled:

```sh
./scripts/open_editor.sh
```

## Smoke Test

Enable the localhost control API in Preferences → Advanced first. New installations
leave it disabled. Use `SPACESULTIMATE_WAIT_FOR_API=1 ./scripts/launch_app.sh`
when a script needs to wait for the API after launch.

```sh
./scripts/smoke_test_api.sh
```

The default smoke test is non-destructive. It checks status, refresh, display-only rule suggestions, HUD, overview show/hide, screenshot capture, and diagnostics export.
It also round-trips app settings while keeping the API enabled.
It reads launch-at-login status but does not modify login items.
When Screen Recording permission is granted, it also verifies screenshot files exist, are non-empty, and have a PNG signature.
Set `SPACESULTIMATE_SKIP_SCREENSHOTS=1` to skip explicit screenshot/preview capture during a smoke run. Previously granted permissions can still allow the app's normal automatic preview caching.
The `/status` payload includes a `detection` object with the latest source, event, timestamp, active Space, detected Space count, and detailed diagnostics. The nested `details` object reports confidence, Dock Space/monitor counts, Dock Current Space IDs, visible-window match candidates, ignored shared window IDs, and notes for ambiguous or fallback detection.

To include config update/reset:

```sh
SPACESULTIMATE_DESTRUCTIVE=1 ./scripts/smoke_test_api.sh
```

## Manual Daily-Driver Checklist

- Launch app with `./scripts/launch_app.sh`.
- Confirm menu bar item shows current Space name.
- Confirm `/status` reports `appIdentity.bundlePath` as `~/Applications/SpacesUltimate.app` when testing the installed copy.
- Run `./scripts/validate_menu_bar_status.sh` and confirm the native status item reports visible, a `D#` badge, current Desktop title, and the expected menu commands.
- On a multi-display setup, confirm `/status.menuBar.activeScreenName` follows the macOS main monitor and that `resolutionSource` is a main-display or Dock monitor source, not a built-in display fallback.
- Click the menu bar item and confirm it opens the native dropdown.
- Choose `SpacesUltimate Settings...` and confirm Preferences opens.
- Reopen the menu, choose the current Desktop row, and confirm Preferences opens.
- Reopen the menu and confirm editor, overview, labels, debug, refresh, and quit actions are present.
- If more than one display is connected, repeat the menu click from each macOS menu bar that shows third-party status items; if macOS does not show status items on a display, record that as system behavior rather than a SpacesUltimate overlay gap.
- Use Backup Config, make a small config change, Restore Backup, and confirm the previous labels/settings return.
- Confirm each editor row shows an `ID` badge when stable IDs are available or `Order` when running on order fallback.
- Use `/config/name-bindings` and confirm it matches the editor's name binding badges.
- Use `/config/invalid` after a corrupt-config recovery scenario and confirm preserved invalid config files are listed.
- If a row is in order fallback with an automatic `Desktop N` name and a remembered custom name, use Repair Names and confirm the custom name returns after a backup is created.
- Use Assign Visible Apps in the editor and confirm currently visible unassigned app names are appended to the active Space rules.
- Use Assign Visible on a non-active Desktop row and confirm visible unassigned app names are appended to that Desktop's rules.
- Use Launch Apps on a Desktop row with assigned apps and confirm those apps are launched/activated without switching first.
- Add the same app rule to two Spaces, use Resolve Duplicates, and confirm the earliest Space keeps it while later duplicates are removed.
- Use Switch + Launch on a Space with assigned apps and confirm it switches first, then launches/activates the configured apps.
- Enable auto-launch assigned apps, switch to a Space with assigned apps, and confirm those apps are launched/activated.
- Enter a shortcut such as `Control+Option+1` in a Space shortcut field, click Switch, and confirm the configured shortcut is sent instead of the default Space-switch fallback.
- Use Show Labels from the editor/menu and confirm a non-activating label strip appears on each display, then disappears automatically.
- With Screen Recording granted, use Capture Preview and confirm the overview card shows a desktop thumbnail.
- Open Preferences and confirm HUD/API/hotkey settings persist.
- Change the overview hotkey in Preferences, enable it, and confirm the new shortcut opens the overview.
- Confirm menu bar display mode changes update the menu bar item immediately.
- Choose a custom screenshot directory, run screenshot capture, and confirm PNGs are written there; reset to the default afterward.
- Confirm opening the editor does not beachball while Debug and Preferences are closed.
- Compare the Preferences permission target with the checked Accessibility entry if macOS reports permission as not granted.
- Toggle Launch at Login manually if testing a bundled app from a stable location.
- Use Setup Guide from the menu and confirm Done dismisses future first-launch prompts.
- Switch Spaces with keyboard shortcuts and trackpad gestures.
- After trackpad/Mission Control/fullscreen Space changes, confirm Debug or `/status` shows an immediate detection event followed by settled 250ms/900ms refresh events when visible.
- Confirm HUD appears and does not steal focus.
- Open overview through menu/API/debug button.
- Confirm the active Desktop card shows a live mini-layout of visible windows.
- With cached previews present, confirm inactive Desktop thumbnails show their last-captured age.
- Temporarily remove Accessibility permission and click another Desktop in the overview; confirm the overview stays open and shows the switching failure reason.
- On a multi-display setup, confirm the custom overview appears on every display and closes everywhere after selecting a Space.
- Confirm Space cards show visible rule matches when assigned app rules match current visible apps.
- Use overview Space buttons only after `/status` reports `accessibilityTrusted: true`. If it remains false, remove any old SpacesUltimate entry from System Settings > Privacy & Security > Accessibility, add `~/Applications/SpacesUltimate.app`, then quit and relaunch the app.
- Open Debug panel and verify:
  - active Space
  - last detection source/event/time
  - detection confidence and notes
  - Dock monitor/current-Space details
  - visible-window match candidates or ambiguity notes
  - known Spaces
  - Accessibility status
  - permission target bundle identifier/path
  - rule suggestions and duplicate assignments
  - visible windows
  - last switching attempt
- Use Export Diagnostics and confirm the copied JSON path exists under Application Support.
- Run screenshot capture and verify both displays are captured.

## HUD

- In Preferences → HUD & Overview, test fade-in, fully visible time, and fade-out independently. Test HUD for Current Desktop must use the current Desktop on each screen without switching Spaces, activating another app, or focusing a text field. It should work with automatic HUD disabled. Test repeated clicks and quick Desktop changes during a long fade; an earlier animation must not dismiss the latest HUD.
- Verify HUD size, background opacity, position, and Desktop-number visibility in light and dark appearances. Save and restore defaults, including the per-slider Default buttons. Legacy configs must retain the previous fade time and appearance. Automated HUD tests use a controlled clock and offscreen panels; they do not switch Desktops or show test windows.

For offscreen HUD and Preferences screenshots, run:

```sh
SPACESULTIMATE_HUD_PREVIEW_DIR="$PWD/.spacesultimate/previews/hud" SPACESULTIMATE_PREFERENCES_PREVIEW_DIR="$PWD/.spacesultimate/previews/hud-preferences" swift test
```

## Mission Control Notes

- Navigate all Preferences sidebar categories. Desktop Notes should open first, each category should show only its own controls, and Defaults & Reset should retain its full behavior. Category changes must not modify settings or focus a shortcut field; background refresh should preserve the selected category.
- In Preferences, confirm the default source and whether current values match it. Save a personal default, change values, and restore it. Each slider's Default button should restore only that slider to the saved value. Show default values to compare the saved and original values. Factory Reset should apply original preferences and disable Launch at Login while keeping the saved preset and all Desktop metadata; Restore Default should still recover the saved preferences afterward. Use temporary test data for these checks, not a user's live preferences.
- Open Preferences and confirm neither hotkey field has a caret or selected text. Typing without selecting a field must leave both shortcuts unchanged. Click a hotkey field, close Preferences, and reopen it to confirm the previous editing focus is cleared too.
- With notes visible, open SpacesUltimate Settings from the menu bar and click/drag its controls. Notes must remain visible, including when opening Settings exits Mission Control. Repeat by opening `/preferences/show`. Settings alone must not open hidden notes, and clicking another app must still dismiss notes after Mission Control exits.
- Change **Notes card opacity** and **Notes background opacity** separately. Each slider should update only its own fill immediately, keep text readable, and preserve panel/card frames. Set background opacity to 0% to hide the whole backdrop, then use each Default button independently. Relaunch to verify both values persist. Scroll Settings to reach the lower controls.
- Open native Mission Control using the keyboard, trackpad gesture, or hot corner. Notes should appear on every display within one polling interval (about 250 ms).
- Click a notes card, then double-click its name: the overlay should remain available for editing even if macOS exits Mission Control when the panel takes focus. Confirm `/overlay/status.keepsOpenAfterMissionControl` is true.
- Repeat with a quick mouse click during native Mission Control. `/overlay/status.lastMouseObservation` should identify the card, including clicks received through the Quartz activity-counter fallback when Dock does not dispatch an AppKit event.
- Confirm the large Desktop number to the left of each name is readable for both single- and double-digit Desktops in light and dark mode.
- With many Desktops, compare a narrow and wide display. A display switches to two staggered rows only when less than half of at least one name would fit in one row and wider text areas are possible after allowing space for the compact buttons. The lower row contains every other Desktop, shifted right by half a card plus half the gap. At the default height setting, the compact panel is 104 pixels tall with the same top edge. Check card clicks, rename, and the 24-pixel square Go buttons inside the right edge of cards on both rows; Go must not dismiss the overlay, and gaps must still count as outside clicks. Single-row Go buttons keep their original position.
- At the minimum height setting, compact cards must show the complete Desktop number and name line, plus a note line when present. Hover truncated notes to see their full text; taller cards can show two note lines. Check the minimum-height-notes and taller-notes previews in both appearances.
- Press **Go →** on a different card. With Accessibility granted, verify the selected Space becomes active and notes remain open. Without permission, verify the explanation offers Accessibility Settings and that cancelling it keeps the notes visible.
- A Go button click consumed by Mission Control should be retained until Mission Control exits and the mouse is released, then run once. Dragging away from the button before release should cancel that pending action.
- Click a gap between cards or the overlay background while Mission Control remains open: notes should stay visible. Repeat after Mission Control exits: notes should close.
- Move a window between Desktops or perform another native action that keeps Mission Control open: notes should stay visible throughout, including while the mouse is held down.
- Click a native Mission Control window or Desktop thumbnail: the original click should still select it. Notes should close when that action exits Mission Control and remain visible if it keeps Mission Control open.
- Press Close while Mission Control stays open: notes must hide immediately and stay hidden until Mission Control exits and reopens, including when Dock consumes the click.
- Exit Mission Control without interacting with a notes card: notes should close. Repeat opening and closing several times. After retaining notes with a card click, verify an outside click, Close, or Escape closes them after Mission Control has exited.
- Open notes manually, then click another app or another display: all panels should close.
- Right-click the menu bar badge twice: notes should open on the first click and remain closed after the second. Repeat with Control-click; a normal left-click should still open the menu.
- Leave the dropdown open through several detection polls, then select a command; background refresh must not replace the menu while it tracks the mouse.
- Double-click a name with another app active, type a temporary name, and press Return. Confirm the saved name appears, notes remain open, and repeating the rename restores the original name.
- `/overlay/status` reports `missionControl`, `outsideClickMonitoring`, and the visible panel/card frames for diagnostics. Each panel includes `rowCount` and `minimumSingleRowNameFraction` for its adaptive layout decision.

Render screenshots of the production AppKit notes view at laptop, compact, and wide display widths, plus a four-Desktop layout, in both appearances:

```sh
./scripts/render_notes_layout_previews.sh
# Optional output directory and saved config to preview the current names/settings:
./scripts/render_notes_layout_previews.sh .spacesultimate/previews/current "$HOME/Library/Application Support/SpacesUltimate/spaces-config.json"
```

The previews render offscreen and do not change the saved config. Layout tests cover display width, short names, icons, odd/even card counts, capped height, and the screen-coordinate hit regions for both rows.

Preference-default tests use a temporary config and cover legacy migration, saved-preset persistence/replacement, restoration without changing Desktop metadata, factory reset with preset recovery, and individual slider resets. Render the production Preferences controls with the comparison collapsed and expanded without opening a window:

```sh
SPACESULTIMATE_PREFERENCES_PREVIEW_DIR="$PWD/.spacesultimate/previews/preferences" swift test --filter PreferenceDefaultsTests
```

The preview command also writes `category-0.png` through `category-7.png` for the eight Preferences pages in sidebar order. The read-only `/settings/defaults` endpoint reports the current default source, preset values, factory values, saved time, and whether current preferences match the default. It is also included as `preferenceDefaults` in `/status`.

The supplementary mouse watcher samples public Quartz click counters and button state at 60 Hz while notes are visible, using counter-based hit testing only during Mission Control. Normal editing uses AppKit event coordinates, avoiding duplicate classification after the cursor moves. The fallback detects complete press/release pairs between samples and initializes its baseline when opening notes so the opening click is not mistaken for an outside dismissal. It does not request event-tap or input-monitoring access.

The Mission Control detector uses public window metadata to recognize Dock's full-display layer-18 window, verified on macOS 26.6.2 without Accessibility or Screen Recording permission. This Dock signature is an OS-dependent heuristic; verify it again after major macOS updates. Other Exposé modes may share the same Dock signature.

## Known Manual Risks

- Active Space detection remains heuristic.
- Inactive Space window lists are not reliable through public APIs.
- Global overview hotkey requires Accessibility trust.
- Click-to-switch requires Accessibility trust for the exact installed app. It prefers macOS `Control+Left/Right` movement when the current Desktop is known and falls back to `Control+number` for Desktop 1 through 9.
