# Architecture

SpacesUltimate is a Swift/AppKit UI layer over native macOS Spaces. There are no
third-party package dependencies. `AppDelegate` wires the services and windows
together; native Dock and Mission Control remain responsible for Spaces.

## Data and detection

- `SpaceStore` persists JSON config, backups, and invalid-config recovery files.
  It reconciles Space metadata by stable ID when available, falls back to order,
  and retains stable-ID history to recover names after ID outages or removal.
- `SpaceDetector` reads `com.apple.spaces` preferences and visible-window metadata.
  `LiveSpaceReader` queries current UUIDs and ordered, typed Spaces per display from
  WindowServer. `LiveSpaceInventory` accepts only complete, unambiguous records and
  numbers regular Desktops across displays, retaining fullscreen Spaces as separate
  transient cards. Names and notes follow stable IDs through reordering; the first
  numbering correction gets a config backup, and removed metadata stays in history.
  Live identity takes precedence even on empty Desktops. The same resolution feeds
  global, menu bar, and notes state.
  `SpaceDetectionResolver` handles conflicting evidence and display matching.
  Polling and delayed refreshes after active-Space notifications allow transitions
  to settle. The preference schema is undocumented even though its access APIs
  are public; detection is heuristic, not a supported native Spaces API.
- `WindowScanner` describes visible windows. `NativeBridge` isolates switching
  through Accessibility-gated keyboard input: configured shortcuts, relative
  Control-arrow movement, or Control-number fallback for Desktops 1–9.
- `RuleEngine` supplies app-assignment suggestions and duplicate-rule detection;
  `AppLaunchService` launches assigned apps. Neither moves arbitrary windows.

## Presentation

`MenuBarController`, the editor, `OverviewController`, and `HUDController` present
store state. Debug and Preferences windows are created lazily and refreshed only
while visible. `LoginItemController` wraps ServiceManagement registration.

`MissionControlMonitor` observes Dock window metadata. `LabelOverlayController`
coordinates Desktop Notes; separate layout and mouse-tracking helpers keep its
geometry and dismissal rules testable. The mouse fallback samples Quartz counters
while notes are visible and uses counter-based hit testing during Mission Control,
where Dock may consume normal AppKit events. The Dock window signature is an
OS-dependent heuristic, so real Mission Control testing is still necessary.

## Diagnostics and developer API

`DiagnosticsService` exports JSON snapshots. `AppSettings.diagnosticPayload`
provides the same settings fields to exports and `AppControlAPI`, including saved
presets. `DiagnosticsPayload` shares their Space, name-binding, detection-detail,
app-rule, and login-item representations. The optional API binds to
`127.0.0.1:37655` and is off by default for new
installs. See [Testing](TESTING.md#control-api) and [Security](../SECURITY.md).

## Detection pitfalls to preserve in regression coverage

The live reader dynamically loads the undocumented `SLSCopyManagedDisplaySpaces`
query, also used by [Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/libspaces.m).
It only reads state; it does not create, move, or switch Spaces/windows. Missing
symbols use the existing detection fallback. After a valid live inventory, transient
malformed/partial reads retain the last valid inventory rather than renumbering from
stale preferences. An
unrecognized live UUID stays unresolved instead of selecting a stale Desktop.
`SPACESULTIMATE_DISABLE_LIVE_SPACES=1` disables the reader for fallback testing.
This isolated private-interface dependency needs revalidation after macOS updates.
No SIP changes, injected code, or new permissions are required by the reader.

Earlier switch sampling found a Dock `Main` monitor record stuck on one Desktop
while visible windows moved between Desktops. An exact display UUID match is
stronger evidence than the `Main` alias or array order. Visible-window matching
can corroborate changes but cannot identify empty Desktops reliably, and windows
seen mid-transition can be misleading. A saved last-known Desktop is fallback
state, not independent confirmation. These observations explain the resolver's
cross-checks; none of these sources is unconditional ground truth.

Keep persisted config migrations and API aliases compatible. In particular,
the old top-level `overviewShortcut` and `riskyMethodsEnabled` config fields are
retained for import/export compatibility; they do not control runtime behavior.
`hudDuration` (request) and `hudDurationSeconds` (response/config) mean HUD fade-out
time; fade-in and hold have separate fields. `/labels/*` and `/overlay/*` address
the same notes overlay. Do not change bundle identity as a troubleshooting shortcut:
it affects permissions, menu bar attribution, and login items.
