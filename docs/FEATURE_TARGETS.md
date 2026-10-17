# SpacesUltimate Feature Targets

This document captures the desired product direction for SpacesUltimate. Starred items are the core features explicitly called out as the main user-facing goals.

Difficulty: `1 = easy`, `10 = very hard`

Progress: `1 = barely started`, `10 = basically done`

Feasibility:

- `Not possible`
- `Possible, but a lot of rethinking involved`
- `Possible and relatively straightforward`

| # | Feature | Description | Difficulty | Progress | Feasibility |
|---:|---|---|---:|---:|---|
| 1 | ★ Custom names for every Desktop / Space | Rename Desktop 1, Desktop 2, etc. inside SpacesUltimate, and keep those names saved. Names should persist across quit/relaunch and stay matched to the right desktop as much as possible. | 3 | 10 | Possible and relatively straightforward |
| 2 | ★ Our own Mission Control | A custom SpacesUltimate overview, separate from Apple's native Mission Control. It uses native Spaces as the backend while showing SpacesUltimate's own named interface. | 5 | 6 | Possible and relatively straightforward |
| 3 | ★ Desktop thumbnails | Each desktop appears as a thumbnail/card with its custom name, color/icon, and number. The current desktop should be clearly highlighted. Eventually thumbnails should visually represent what is on each desktop. | 6 | 4 | Possible, but a lot of rethinking involved |
| 4 | ★ Current desktop window overview | The current desktop shows all open windows zoomed out, like a mini Mission Control view. This should make it possible to visually recognize what is open on the current desktop. | 6 | 4 | Possible and relatively straightforward |
| 5 | ★ Click a desktop to switch to it | Clicking a named desktop/thumbnail moves the user to that desktop. This must feel reliable. If Accessibility or macOS Mission Control shortcuts are required, the app should explain that clearly. | 5 | 6 | Possible and relatively straightforward |
| 6 | ★ Drag windows from the current desktop to another desktop | In the custom overview, drag a visible window preview onto another desktop to move that window there. This is one of the biggest real Mission Control replacement features, but macOS does not provide a clean public move-window-to-Space API. | 9 | 1 | Possible, but a lot of rethinking involved |
| 7 | Accurate active desktop detection | The app knows which desktop is currently active and updates the menu bar, overview, and HUD when the user switches desktops. It should work for keyboard switching and, as much as possible, trackpad/Mission Control switching. | 8 | 4 | Possible, but a lot of rethinking involved |
| 8 | Reliable desktop detection | The app detects how many desktops exist and handles adding, removing, or reordering desktops without scrambling custom names where possible. | 7 | 5 | Possible, but a lot of rethinking involved |
| 9 | Menu bar status | The menu bar shows the current custom desktop name and opens useful controls such as overview, editor, preferences, debug, refresh, and quit. | 3 | 7 | Possible and relatively straightforward |
| 10 | Desktop editor | Edit desktop name, color, icon, shortcut note, and app assignments. It should open quickly, save reliably, and remain usable alongside other app windows. | 4 | 7 | Possible and relatively straightforward |
| 11 | HUD when switching desktops | Optional pop-up showing the custom desktop name after switching. It should not steal focus. | 3 | 7 | Possible and relatively straightforward |
| 12 | Global hotkey | Keyboard shortcut to open the custom Mission Control/overview, with user control to enable or disable it. Eventually this should be customizable. | 5 | 4 | Possible and relatively straightforward |
| 13 | Switching beyond Desktop 9 | Support switching to Desktop 10 and above. The app now tries relative Control-left/right movement when it knows the current Desktop, but this still depends on macOS accepting keyboard automation. | 8 | 3 | Possible, but a lot of rethinking involved |
| 14 | Multi-monitor support | Work correctly across multiple displays, including setups where displays have separate Spaces. Detection and overview behavior need deeper testing and hardening here. | 8 | 3 | Possible, but a lot of rethinking involved |
| 15 | Permission/setup assistant | Clearly explain required macOS settings, including Accessibility permission, Screen Recording if needed, and Control-number desktop shortcuts. | 4 | 5 | Possible and relatively straightforward |
| 16 | Debug/diagnostics | Show active desktop, detected desktops, detection source, permission status, config path, last switch attempt, visible windows, and other information that explains failures. | 4 | 7 | Possible and relatively straightforward |
| 17 | Config safety | Names and settings should persist. Bad config should not crash the app. Reset/recovery options should be available. | 4 | 6 | Possible and relatively straightforward |
| 18 | Launch/login polish | App launches reliably, quits cleanly, behaves as a normal macOS app, and optionally launches at login. | 5 | 5 | Possible and relatively straightforward |
| 19 | Rename native Apple Mission Control labels | Apple's native Mission Control itself shows the custom names. This is likely unavailable through public APIs and would require fragile/private approaches if possible at all. | 10 | 0 | Not possible |
| 20 | Overlay names onto native Mission Control | Draw SpacesUltimate labels over Apple's native Mission Control rather than replacing it. This would require fragile timing/window-overlay behavior and careful experimentation. | 9 | 0 | Possible, but a lot of rethinking involved |
| 21 | ★ Inactive desktop window previews | Show recognizable windows/thumbnails for every desktop, not only the current one. Public macOS APIs do not expose clean window-to-Space mapping, so this is hard to do reliably. | 9 | 1 | Possible, but a lot of rethinking involved |
| 22 | Automatic app routing | Assign apps to desktops and automatically move or open them there. This depends on reliable switching/window movement and should come after the manual experience works. | 9 | 1 | Possible, but a lot of rethinking involved |
| 23 | True native Space switching API | Switch desktops directly without relying on Control+1 through Control+9. This likely requires private or experimental APIs and careful risk isolation. | 10 | 0 | Possible, but a lot of rethinking involved |
| 24 | Custom shortcut playback | Actually execute a shortcut configured per desktop, instead of storing the shortcut field as a note. | 5 | 1 | Possible and relatively straightforward |

## Core MVP

The shortest useful version is:

1. ★ Custom names for every Desktop / Space
2. ★ Our own Mission Control
3. ★ Desktop thumbnails
4. ★ Current desktop window overview
5. ★ Click a desktop to switch to it

In plain terms: the user can give each desktop a custom name, open a SpacesUltimate Mission Control-like overview, see those named desktops, see the current desktop's windows zoomed out, and click a desktop to switch to it.

## Main Stretch Feature

The biggest feature that turns this from a named Spaces viewer into a real Mission Control replacement is:

6. ★ Drag windows from the current desktop to another desktop

This is also one of the hardest features because macOS does not provide a clean public API for moving arbitrary windows between Spaces.
