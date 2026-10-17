# Privacy

SpacesUltimate stores its data on your Mac. The app contains no analytics,
advertising SDK, account system, or automatic upload service.

## Data and permissions

- Desktop names, notes, colors, assignments, settings, backups, and recovery data
  live under `~/Library/Application Support/SpacesUltimate/` by default.
- Accessibility permission enables keyboard-based Desktop switching.
- Screen Recording permission enables screenshots and preview thumbnails. When
  granted, the app can automatically cache a preview as the active Desktop
  changes. Images can contain anything visible on that display.
- Screenshots, cached previews, and exported diagnostic reports are local files
  under the app's support directory unless a custom screenshot folder is chosen.
- Diagnostics and logs can contain Desktop names and notes, window titles,
  application names, local paths, and display information. Some log messages
  are also written to the macOS unified log.
- Launch at Login is controlled through the app's preferences and macOS.
- The optional developer API exposes local controls to other programs on the
  same Mac. It is off by default for new installations. See [Security](../SECURITY.md).

The app does not automatically send these files to the developer. If you submit
an issue or share diagnostics, review and redact the files first. GitHub handles
information you submit there under its own privacy policy.

## Removing data

Quit SpacesUltimate and remove its Application Support directory to remove
stored preferences, backups, previews, and reports. Remove screenshots from any
custom destination separately. Revoke permissions in System Settings → Privacy
& Security and disable Launch at Login before uninstalling if it is enabled.
macOS manages retention of its unified logs separately.
