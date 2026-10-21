# Build And Release Guide

This repository contains the active Swift/XcodeGen **clip'M** project (scheme/target names remain `ClipMenu` for history; the product displays as clip'M).

## Current Stack

- Language: Swift 5.9+
- Platform: macOS 14+
- Build system: XcodeGen (`project.yml`)
- App type: menu bar app (`LSUIElement`)
- Dependencies: [`KeyboardShortcuts`](https://github.com/sindresorhus/KeyboardShortcuts); direct builds also link [Sparkle](https://sparkle-project.org/) for updates

## Prerequisites

```sh
xcode-select -p
brew install xcodegen
```

## Generate Project

Run whenever `project.yml` changes:

```sh
xcodegen generate
```

Keep separate derived-data folders for the two channels. Both targets produce `clipM.app`; reusing the same products folder can leave Sparkle from a direct build inside a later App Store build. Archive from a clean output folder for distribution.

## Build (Debug, direct / GitHub)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Debug -derivedDataPath .build/DirectDerivedData build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Build (Debug, App Store channel)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenuAppStore -configuration Debug -derivedDataPath .build/AppStoreDerivedData build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Build (Release)

```sh
xcodebuild -project ClipMenu.xcodeproj -scheme ClipMenu -configuration Release -derivedDataPath .build/DirectDerivedData build \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Run From Xcode

1. Open `ClipMenu.xcodeproj`.
2. Select a scheme:
   - `ClipMenu` — direct / GitHub download (Sparkle in-app updates)
   - `ClipMenuAppStore` — Mac App Store build (`APP_STORE` flag, no Sparkle)
3. Run with `Debug` configuration.

clip'M is a menu bar app (`LSUIElement = YES`), so it does not appear in the Dock while running.

## Testing

UI smoke scripts for previews and `/` filter (plus the in-process filter self-test) are documented in [`doc/testing.md`](doc/testing.md).

## Distribution Channels

| Scheme | Updates | About tab |
|---|---|---|
| `ClipMenu` | Sparkle checks the GitHub Releases appcast | Auto-check toggle + “Check for Updates…” |
| `ClipMenuAppStore` | iTunes Lookup API; “Update in App Store” opens the Mac App Store | Check button only (no self-updater) |

Both builds share the same About copy (GitHub + [United Visions](https://unitedvisions.org)). Linking to the GitHub repo from an App Store build is fine for source/docs; do not use it as an alternate download storefront inside the App Store binary.

Direct downloads are published via **GitHub Releases** (DMG + Sparkle `appcast.xml`), not files under `dist/` on `master`.

### Sparkle setup (direct builds)

The direct target generates `Resources/DirectDistributionInfo.plist` from `project.yml`. Its public EdDSA key and feed are embedded explicitly (custom `INFOPLIST_KEY_SU*` settings are not sufficient):

```yaml
SUPublicEDKey: k+dUStN0vPsQtPhR3HzzGG2AvWgN3cofmk23IkSFE8g=
SUFeedURL: https://github.com/Frazer/clipM/releases/latest/download/appcast.xml
```

Private key lives in the login keychain (`generate_keys --account clipmenu`) and was exported to `secrets/sparkle_eddsa_private.key` (gitignored). Add the same string as GitHub Actions secret `SPARKLE_PRIVATE_KEY`. See `secrets/README.md`.

### Ship a direct-download DMG

1. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates).
2. Set notarization env vars (`APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID=97988GNC59`) or App Store Connect API key vars.
3. Bump `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `project.yml` if needed.
4. Run:

```sh
chmod +x scripts/release-dmg.sh
./scripts/release-dmg.sh --publish
```

This builds the `ClipMenu` scheme (Release), notarizes, creates `release/clipM-<version>.dmg`, generates Sparkle `appcast.xml`, and uploads both to a GitHub Release. The app displays as **clip'M**. Publishing also updates the [Homebrew cask](https://github.com/Frazer/homebrew-clipm) so `brew install --cask frazer/clipm/clipm` stays on that version.

Local packaging without notarization (will not pass Gatekeeper for other Macs):

```sh
./scripts/release-dmg.sh --skip-notarize
```

### GitHub Actions

Workflow: `.github/workflows/release-dmg.yml`

- Does not run on a tag push. Start it by hand from the Actions tab if the signing secrets in `secrets/README.md` are set.
- Normal releases use `scripts/release-dmg.sh --publish` on a developer Mac.

### App Store product ID

When the listing is live, set `AppDistribution.appStoreProductID` in `Sources/Infrastructure/AppDistribution.swift` so “Update in App Store” deep-links to your product page.

## Accessibility Note

Paste simulation uses CGEvent and requires Accessibility permission:

- System Settings -> Privacy & Security -> Accessibility

Direct (`ClipMenu`) and App Store (`ClipMenuAppStore`) builds share bundle ID `org.unitedvisions.ClipM`, but different entitlements/signatures. After switching channels, reset Accessibility and re-grant it for the build you just launched:

```sh
tccutil reset Accessibility org.unitedvisions.ClipM
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

## App Sandbox (App Store scheme)

`ClipMenuAppStore` uses `ClipMenuAppStore.entitlements` with App Sandbox + network client. Development Team: `97988GNC59`.

Clipboard history polling via `NSPasteboard.general` is allowed in sandbox. Auto-paste still needs Accessibility granted to that signed binary.

Before the first signed App Store build:

1. Xcode → Settings → Accounts → add your Apple ID (team `97988GNC59`).
2. Select scheme `ClipMenuAppStore`, enable Automatically manage signing.
3. Build once so Xcode creates a Mac Development certificate.


## Release Direction

- **Direct (GitHub):** `scripts/release-dmg.sh --publish` on a developer Mac → notarized Developer ID `.dmg` + Sparkle `appcast.xml` on GitHub Releases.
- **App Store:** archive the `ClipMenuAppStore` scheme and upload via Organizer / Transporter.

## Troubleshooting

`xcodegen: command not found`

```sh
brew install xcodegen
```

Code signing errors in local/CI builds

- Use `CODE_SIGN_IDENTITY=""`
- Use `CODE_SIGNING_REQUIRED=NO`
- Use `CODE_SIGNING_ALLOWED=NO`

## Security validation before publication

Read [the audit and remaining limits](doc/security-audit.md) and run the [security regression checks](doc/testing.md#security-regression-checks). The release script requires notarization and successful Gatekeeper assessment for public artifacts. `--skip-notarize` creates a local test DMG under `release/local-test/`, with no update feed, and cannot be combined with `--publish`. The dependency versions are pinned; update the pins and packaging verification together after reviewing advisories.

Saved history and snippets are encrypted with CryptoKit AES-GCM. Both builds keep the keys in the login Keychain on this Mac only and do not sync them. The App Store copy stores its database in its sandbox container, separate from the direct download. Clear History retires the history key and cleans the live database and clipboard; it cannot remove backups or copies held by other applications.
