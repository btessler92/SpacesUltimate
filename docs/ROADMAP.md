# Roadmap

## Done

- Swift/AppKit menu bar app.
- Local JSON config.
- Space ID/order reconciliation from Dock preferences when available.
- Menu bar current Space label.
- Editor with Space name, color, icon, shortcut note, and app suggestions.
- Non-activating HUD.
- Custom overview cards.
- Debug panel.
- Localhost-only API test harness.
- Multi-display screenshot capture.
- Development `.app` bundle and scripts.
- Preferences window for HUD/API/global-hotkey toggles.
- Preferences for screenshot directory and menu bar display mode.
- First-launch onboarding for editor, permissions, keyboard shortcuts, and preferences.
- Launch-at-login preference and status API.
- Overview layout improvements for many Spaces.
- Real generated app icon and bundle icon wiring.
- Cached Space preview thumbnails in the custom overview.
- Unit tests for active Space detection resolver edge cases.
- App bundle verification and launch-at-login recovery diagnostics.
- Smoke-test validation for captured screenshot PNG files.
- One-click visible app rule assignment from the editor and API.
- Duplicate app rule cleanup from the editor and API.
- Explicit switch-and-launch behavior for assigned apps.
- Optional Space label overlay for Mission Control-style use.
- Custom shortcut playback for per-Space shortcut fields.
- Configurable global overview hotkey.
- Config backups and restore-latest recovery.
- Multi-display custom overview presentation.
- Optional automatic launch of assigned apps when a Space becomes active.
- Structured active Space detection diagnostics with confidence, Dock monitor/current-Space details, visible-window match candidates, and ambiguity notes.
- Custom overview live window mini-layouts for the current desktop, cached preview age badges, and visible switch-failure feedback.
- Per-Desktop editor controls for assigning visible apps and launching assigned apps, with routing summary counts for unassigned visible apps and duplicate rules.
- Delayed public-API settling refreshes after active-Space notifications for gesture, Mission Control, fullscreen, and multi-monitor transitions.
- Stable-ID Space metadata history and reconciliation tests for custom-name recovery across reorder, ID outage, removal, and malformed config cases.
- Name binding status in editor/debug/API/diagnostics plus conservative name repair for automatic order-fallback rows.
- Invalid config preservation on startup with Debug/API/diagnostics visibility.

## Next

- Add live manual validation for the full custom-name lifecycle: reboot, add/remove/reorder Desktops, temporary ID outage, import/export, backup/restore, and Repair Names.
- Add stronger active Space detection tests across:
  - trackpad gestures
  - fullscreen apps
  - multi-monitor Spaces
  - reboot/reorder cycles
- Use the new detection diagnostics to drive targeted manual reports for trackpad, fullscreen, and multi-monitor failures.
- Add UI tests or screenshot image comparisons.

## Later

- Experimental methods behind explicit flags only.
