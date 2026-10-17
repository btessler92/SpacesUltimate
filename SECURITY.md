# Security

SpacesUltimate is an early-stage macOS utility. Use the latest release; older
versions do not have a separate security maintenance branch.

Report vulnerabilities privately through the repository's
[security advisories](https://github.com/btessler92/SpacesUltimate/security/advisories/new).
Do not post credentials, sensitive diagnostics, or exploit details in public issues.

## Local developer API

The developer control API is disabled by default for new installations. Existing
explicit settings are preserved. If enabled in Preferences → Advanced, it binds
to `127.0.0.1:37655`, accepts local command-line requests, and rejects browser
Origin, Referer, Fetch Metadata, and non-local Host headers.

It is not an authenticated boundary against other programs on the same Mac.
Local processes can read app state, change settings, launch assigned apps, and
request screenshots using the app's granted permissions. Enable it only while
using trusted local tools. Never expose it through port forwarding or a proxy.

Accessibility and Screen Recording are optional macOS permissions. Grant them
only to the app copy you intend to use. See [Privacy](docs/PRIVACY.md) for storage
and diagnostic details.
