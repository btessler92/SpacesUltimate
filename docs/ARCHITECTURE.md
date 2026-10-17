# Architecture

SpacesUltimate is a stability-first UI layer over native macOS Spaces. It does not replace Dock, Mission Control, or the window manager.

## Stable Core

- `SpaceStore` owns persisted Space metadata and reconciles it with detected Space order/IDs.
- `SpaceDetector` polls safe public sources, records the latest detection snapshot, and emits active Space changes.
- `MenuBarController` shows the current Space label and exposes app actions.
- `HUDController` shows non-activating multi-display Space labels.
- `OverviewController` renders the custom overview without taking over native Spaces, including display-only rule matches on Space cards.
- `WindowScanner` uses public window-list APIs and is explicit about current-space limits.
- `NativeBridge` isolates switching and other fragile platform behaviors.
- `RuleEngine` evaluates display-only app-to-Space suggestions and duplicate assignments, using forgiving app-name matching such as `Chrome` for `Google Chrome`.
- `AppControlAPI` exposes localhost-only test/control endpoints.
- `PreferencesWindowController` exposes persisted app-level settings for HUD, API, hotkey behavior, screenshots, and menu bar label placement.
- `OnboardingWindowController` gives first-launch setup guidance without changing native Spaces.
- `LoginItemController` wraps ServiceManagement launch-at-login registration and status.
- `DiagnosticsService` exports a single JSON snapshot for bug reports and API/debug smoke tests.

Debug and Preferences windows are created lazily and only refreshed while visible, so polling and config changes do not do expensive hidden UI work.

## Stability Rules

- Native Spaces remain the backend.
- Private APIs stay out of the main path.
- Window moving between Spaces is not part of the MVP.
- If Space IDs are unavailable, names follow order and the app should keep working.
- Permission prompts are user-initiated, not surprise launch-time prompts.

## Current Test API

The app listens on `127.0.0.1:37655`.

- `GET /status`
- `GET /refresh`
- `GET /hud?space=1`
- `GET /overview/show`
- `GET /overview/hide`
- `GET /overview/toggle`
- `GET /editor/show`
- `GET /preferences/show`
- `GET /debug/show`
- `GET /settings/update?hudEnabled=true&hudDuration=1.5&apiEnabled=true&globalHotkeyEnabled=false&menuBarLabelPosition=rightOfCenter`
- HUD settings also accept `hudFadeInSeconds`, `hudHoldSeconds`, `hudScale`, `hudBackgroundOpacity`, `hudPosition` (`right`, `center`, `left`, `top`, `bottom`), and `hudShowsDesktopNumber`. The existing `hudDuration` parameter and `hudDurationSeconds` response field continue to mean fade-out time. `/status` and `/settings/defaults` include all HUD settings.
- `GET /onboarding/reset`
- `GET /onboarding/complete`
- `GET /login-item/status`
- `GET /login-item/update?enabled=true`
- `GET /rules/suggestions`
- `GET /config/update?space=1&name=Focus&color=%232F80ED&icon=F&apps=Codex,Terminal`
- `GET /config/reset`
- `GET /permissions/accessibility`
- `GET /switch?space=1`
- `GET /screenshot`
- `GET /diagnostics/export`
- `GET /app/quit`
