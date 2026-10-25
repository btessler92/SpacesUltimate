# Changelog

## 0.1.3 — 2026-10-25

- Expand Desktop Notes cards across each display, including both staggered rows.
- Use the validated live display inventory for Desktop order and monitor placement;
  ignore stale saved monitor records and keep Desktop metadata attached to stable IDs.
- Show fullscreen apps as separate, unnumbered cards with app names and their own
  highlight. Fullscreen Spaces no longer shift Desktop numbering. Relative navigation
  still counts their physical positions between Desktops.
- Back up config before the initial numbering correction and retain removed metadata
  in stable-ID history. Do not copy another Desktop's notes onto newly discovered IDs.

## 0.1.2 — local build

- Prefer live per-display Space identity over stale Dock/window assignments, fixing
  wrong Desktop labels and notes highlights after moving windows or on empty Desktops.
  Keep the prior detection path as a fallback when the read-only live query is unavailable.
- Consolidated documentation and removed stale feature scores and duplicated guides.
- Made API smoke checks read-only and removed the destructive reset mode. `make test`
  now runs unit tests, isolated script tests, and bundle verification without a live app.
- Made launch reuse the running app. The editor helper now only opens the editor
  through an already-enabled API; it no longer restarts the app or changes preferences.
- Unified settings diagnostics so exports include all HUD controls reported by the API.
- Shared the API/export formatters for Spaces, name bindings, detection details,
  app rules, and login items while preserving their existing JSON fields.
- Clarified that menu bar configuration checks do not prove on-screen visibility.

## 0.1.1

- Added an application Settings menu and Command-comma shortcut, independent of the status item.
- Removed restoration of the legacy named menu bar slot. macOS and menu bar managers
  can still hide the item; this change does not bypass their controls.
- Published a Developer ID signed, notarized universal app download.

## 0.1.0 — initial public source release

- Published the Swift/AppKit app under MIT with contribution, privacy, security,
  CI, and universal signing/notarization tooling.
- Included Desktop names and notes, the Mission Control notes overlay, menu bar
  indicator, editor, overview, HUD, configurable shortcuts, and app assignments.
- Included stable-ID reconciliation and name recovery, backups, invalid-config
  preservation, preference presets, launch at login, and diagnostics.
- Disabled the developer API by default for new installations; preserved existing
  explicit preferences. Bound it to loopback and rejected browser/non-local requests.

Detailed pre-release development history remains in Git.
