# Distribution

AI Usage releases are built by [the macOS release workflow](.github/workflows/release.yml). Each release contains:

- `AIUsageMenu-X.Y.Z.zip` for the in-app updater and one-command installer.
- `AIUsageMenu.dmg` for a familiar drag-to-Applications install.
- `checksums.txt` with SHA-256 hashes for both downloads.
- `update.json` for clients using the optional JSON update feed.

The build is universal and supports both Apple silicon and Intel Macs running macOS 14 or later.

## Publish A Release

1. Update `VERSION` and `CHANGELOG.md`.
2. Merge the change to `main`.
3. Push a matching tag:

```sh
version="$(tr -d '[:space:]' < VERSION)"
git tag "v${version}"
git push origin "v${version}"
```

The workflow tests the Swift package, builds the app, verifies every artifact, and creates or updates the matching GitHub release. A manual GitHub Actions run produces development artifacts only; publishing requires a matching pushed tag.

## Developer ID Signing And Notarization

Public downloads should be signed with a Developer ID Application certificate and notarized by Apple. Configure all five repository secrets before publishing a public release:

| Secret | Value |
| --- | --- |
| `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64` | Base64-encoded Developer ID Application `.p12` export |
| `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD` | Password used when exporting the `.p12` |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_PRIVATE_KEY_BASE64` | Base64-encoded App Store Connect `.p8` private key |

Developer ID certificates must be created in the Apple Developer certificate portal and exported from Keychain Access. App Store Connect API keys are created under Users and Access, Integrations.

The workflow fails if only some secrets are present. With all five configured it:

1. Imports the Developer ID identity into an ephemeral keychain.
2. Signs the app with hardened runtime and a secure timestamp.
3. Uses `asc notarization submit --wait` for the ZIP and DMG.
4. Staples tickets to the app and DMG.
5. Runs `codesign`, Gatekeeper, stapler, ZIP, DMG, and checksum verification before publishing.

The in-app updater reads the matching ZIP checksum from `checksums.txt`. It verifies that checksum and the archive layout before extraction, then validates the app's bundle identifier, version, Happenings Developer ID team, code signature, and Gatekeeper trust. A dedicated helper atomically swaps the bundles and restores the prior app if relaunch fails.

Without these secrets, pull requests and manual development runs still produce downloadable ad-hoc signed workflow artifacts, but they never receive release credentials and never create or overwrite a GitHub release. Only a matching pushed tag with all signing secrets configured publishes a release. Do not use an ad-hoc build for a polished public download.

## Local Packaging

Create the app and all release artifacts locally:

```sh
scripts/package-release.sh
```

To sign locally, provide the exact identity shown by `security find-identity -v -p codesigning`:

```sh
AI_USAGE_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
  scripts/package-release.sh
```

Notarization is intentionally handled by CI so credentials and release evidence stay in one place.
