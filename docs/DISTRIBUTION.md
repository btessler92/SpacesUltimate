# Distribution

SpacesUltimate is free, MIT-licensed software distributed through
[GitHub](https://github.com/btessler92/SpacesUltimate). The initial public release
provides source code. A signed, notarized downloadable app requires the
maintainer's Developer ID Application certificate and notarization credentials.
Do not describe an ad-hoc-signed development build as notarized.

## Local builds

Requirements: macOS 14+, Xcode, and Swift 6+. There are no third-party package
dependencies. `make install` builds for the current Mac and installs in
`~/Applications`. `make package` produces an ad-hoc-signed ZIP for local testing,
not a notarized public release.

To build a universal Apple silicon + Intel test archive:

```sh
SPACESULTIMATE_UNSIGNED=1 ./scripts/release_github.sh
```

The archive and SHA-256 checksum are written to `.build/artifacts/`. The script
verifies both architectures and the bundle signature. macOS Gatekeeper may
block downloaded unsigned builds; publish notarized builds for general users.

## Signed public downloads

1. Install a **Developer ID Application** certificate with its private key in
   the signing Mac's Keychain. Apple Development and Apple Distribution
   certificates are not substitutes for direct Developer ID distribution.
2. Store notarization credentials using `xcrun notarytool store-credentials
   SpacesUltimate-notary` and its interactive prompts. Do not commit secrets or
   put passwords in shell scripts.
3. Run tests, update the version/build in `Resources/Info.plist`, and build:

```sh
swift test
SPACESULTIMATE_CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
SPACESULTIMATE_NOTARY_PROFILE='SpacesUltimate-notary' \
./scripts/release_github.sh
```

The script builds both architectures, signs with hardened runtime and a secure
timestamp, submits to Apple, staples the ticket, validates it, runs Gatekeeper
assessment, and creates a ZIP and checksum. It stops on a failed step.

4. Test the downloaded archive on a clean Mac, including permissions, Desktop
   switching, multiple monitors, startup, and upgrades. CI does not grant
   Accessibility or Screen Recording permissions and cannot replace these checks.
5. Attach the notarized ZIP and checksum to a GitHub Release for the matching
   source commit. Confirm CI passed. The signing script does not publish.

Keep the bundle identifier stable for existing users: changing it can require
re-granting permissions and can affect login-item registration. The current
identifier is `local.spacesultimate.menubar`.

References: [Developer ID](https://developer.apple.com/developer-id/) and
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Mac App Store status

The current full-featured application is not prepared for Mac App Store
submission. Apple's [App Sandbox documentation](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)
lists cross-app preferences access and Accessibility use in assistive apps as
incompatible activities. This app reads `com.apple.spaces` in `SpaceDetector`
and `DiagnosticsService`, and uses Accessibility-gated input in `NativeBridge`.

An App Store edition would require a separate product scope and validation:
redesign Spaces detection and switching, adopt sandbox-compatible storage and
permissions, create an Xcode archive/signing setup, and prepare App Store
Connect metadata and privacy disclosures. Adding a sandbox entitlement alone
does not make the current functionality compatible. See [App Review Guidelines
2.4.5](https://developer.apple.com/app-store/review/guidelines/#hardware-compatibility).
