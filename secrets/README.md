# Local secrets (gitignored)

## Sparkle private key

Generated with Sparkle’s `generate_keys --account clipmenu`.

- **File (local):** `secrets/sparkle_eddsa_private.key` (already exported on the machine that ran generate_keys)
- **GitHub Actions secret name:** `SPARKLE_PRIVATE_KEY`
- **Value:** exact contents of `sparkle_eddsa_private.key` (single line, no extra newline if possible)

Public key (safe to commit) is embedded in the app as `SUPublicEDKey` via `project.yml`.

## Developer ID + notarization (for public DMGs)

1. Xcode → Settings → Accounts → Manage Certificates → **+ → Developer ID Application**
2. Export the cert as `.p12` from Keychain Access
3. GitHub secrets:
   - `BUILD_CERTIFICATE_BASE64` — `base64 -i YourCert.p12 | pbcopy`
   - `P12_PASSWORD`
   - `KEYCHAIN_PASSWORD` — any random string
   - `APPLE_ID`
   - `APPLE_APP_SPECIFIC_PASSWORD` — from https://appleid.apple.com
   - `APPLE_TEAM_ID` — `97988GNC59`
