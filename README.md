# SpacesUltimate

Give your macOS Desktops names, colors, and notes. SpacesUltimate adds a menu bar
indicator, notes alongside Mission Control, a custom Desktop overview, and an
optional notification when you switch Desktops. Native macOS Spaces remain in charge.

Free and open source under the [MIT license](LICENSE). Requires **macOS 14 or
newer**; supports Apple silicon and Intel Macs.

## Install

Download the app ZIP from [GitHub Releases](https://github.com/btessler92/SpacesUltimate/releases),
unzip it, and move **SpacesUltimate.app** to your Applications folder. Version
0.1.3 includes a Developer ID signed and Apple-notarized universal download.
The app is distributed through GitHub; there is no Mac App Store edition.

Open the app, then use its menu bar item to open the Space Editor or Settings.
Grant **Accessibility** for Desktop switching and **Screen Recording** for
screenshot previews if you want those features. The Setup Guide explains the
required macOS keyboard shortcuts. The developer control API is optional and
disabled by default on new installations.

## Using it

- **Names and notes:** edit them in the Space Editor. Double-click a name on a
  Desktop Notes card to rename it.
- **Desktop Notes:** open Mission Control, use the menu command or configured
  shortcut, or right-click the menu bar badge. Clicking a card keeps notes open
  for editing after Mission Control exits. Close dismisses them immediately;
  outside clicks dismiss retained notes once Mission Control has exited. Cards fill
  each display's available width. Fullscreen apps appear as separate cards with
  their app names and do not consume Desktop numbers.
- **Overview:** browse named Desktop cards and click to switch. The current
  Desktop can show a window layout; other previews are cached snapshots.
- **Settings:** adjust notes, HUD, shortcuts, and menu bar display. Save Current
  as Default stores a personal preset. Restore Default and Factory Reset change
  preferences while preserving Desktop names and notes.
- **App assignments:** suggest or launch apps for a Desktop. These rules do not
  move existing windows between Desktops.

Names, notes, and settings are stored locally in
`~/Library/Application Support/SpacesUltimate/spaces-config.json`.
Use the editor's backup and import/export controls before experiments with data.
See [Privacy](docs/PRIVACY.md) for screenshots and diagnostic exports.

## If the menu bar item is missing

Open SpacesUltimate from Applications, then use **SpacesUltimate → Settings…**
or **⌘,**. The editor also has a Preferences button.

Check the app's menu bar display setting, macOS's **Allow in the Menu Bar**
controls where available, and any menu bar manager such as Ice. A crowded menu
bar can also hide items. A diagnostic value of `isVisible: true` means the app
requested visibility; it does not prove the item is on screen.

## Limitations

Desktop names belong to SpacesUltimate; they do not replace Apple's native
Mission Control labels. Space detection uses a guarded, read-only live macOS query,
with saved preferences and window metadata as a fallback. These interfaces can
change across OS versions. If stable Space IDs
are unavailable, labels fall back to Desktop order. Fullscreen, empty Desktops,
and multiple monitors need particular care. Switching relies on keyboard
shortcuts and Accessibility permission for the installed copy of the app.

## Build and contribute

Install Xcode with Swift 6 or newer. There are no third-party package dependencies.

```sh
git clone https://github.com/btessler92/SpacesUltimate.git
cd SpacesUltimate
make test
make install
```

Open `~/Applications/SpacesUltimate.app` in Finder. Local builds are not notarized
public releases; see [Distribution](docs/DISTRIBUTION.md) for release packaging.

[Contributing](CONTRIBUTING.md) · [Testing and developer commands](docs/TESTING.md) ·
[Architecture](docs/ARCHITECTURE.md) · [Roadmap](docs/ROADMAP.md) ·
[Changelog](docs/CHANGELOG.md) · [Report a bug](https://github.com/btessler92/SpacesUltimate/issues) ·
[Security](SECURITY.md)
