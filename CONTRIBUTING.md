# Contributing

Bug reports, focused pull requests, and documentation improvements are welcome.
Contributions are provided under the project's [MIT license](LICENSE).

## Development

Use macOS 14 or newer and Xcode with Swift 6 or newer. There are no third-party
package dependencies.

```sh
git clone https://github.com/btessler92/SpacesUltimate.git
cd SpacesUltimate
make test
```

Keep changes focused and describe the behavior before and after your change.
Add regression coverage for bug fixes when practical. For UI changes, test with
multiple displays and Desktop counts, and include screenshots with private
content removed. Read [Testing](docs/TESTING.md) for manual checks.

The optional control API must be enabled in Preferences → Advanced before
running `make smoke`. It reads state without changing settings, opening windows,
or capturing screenshots. Use disposable data for manual mutation/recovery tests.

Do not commit configuration, diagnostic exports, screen captures, signing
certificates, or credentials. Preserve stable Space naming. Keep the existing
read-only live Spaces query isolated; explain and validate any new reliance on
undocumented macOS interfaces. Use a GitHub noreply author email if you want to keep your personal
email private. Explain any new permissions or data storage in the pull request.

## Bugs and feature requests

Use [GitHub Issues](https://github.com/btessler92/SpacesUltimate/issues).
Include the app version, macOS version, Mac architecture, monitor arrangement,
Desktop count, reproduction steps, expected result, and actual result.
Review diagnostics before attaching them: they can contain window titles,
Desktop names and notes, application names, and local file paths.

For security vulnerabilities, follow [SECURITY.md](SECURITY.md).
