# Roadmap

The goal is a dependable companion to native Spaces: named Desktops, editable
notes, a useful overview, and reliable switching. See the [README](../README.md)
for current features and [Changelog](CHANGELOG.md) for released changes.

## Priorities

- Validate name and note preservation through reboot, add/remove/reorder,
  temporary ID loss, import/export, backup/restore, and Repair Names.
- Improve active Desktop detection for empty Desktops, gestures, fullscreen apps,
  and multiple monitors using reproducible diagnostic reports.
- Validate menu bar visibility across macOS versions, crowded bars, and menu bar
  managers; keep Settings reachable independently of the status item.
- Extend UI regression coverage for the overview, notes editing, and permissions.

## Exploratory work

- Better inactive-Desktop previews beyond cached screenshots.
- Dragging windows between Desktops and more automatic app routing. These need
  a separate feasibility investigation; the app currently launches assigned apps
  but does not move arbitrary windows.
- Switching without keyboard shortcuts, only if a maintainable approach exists.

Native Mission Control label replacement and an App Store edition are not current
commitments. Any experimental platform methods should remain isolated and opt-in.
