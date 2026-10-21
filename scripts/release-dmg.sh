#!/usr/bin/env bash
# Build a Sparkle-ready clipM.dmg + appcast.xml for GitHub Releases (displays as clip'M).
#
# Usage:
#   ./scripts/release-dmg.sh                 # build + notarize + DMG + signed appcast
#   ./scripts/release-dmg.sh --skip-notarize # local packaging without notarization
#   ./scripts/release-dmg.sh --publish       # also create/upload a GitHub release (requires gh)
#
# Expected secrets / env (for notarize + CI):
#   SPARKLE_PRIVATE_KEY   EdDSA private key string (or file at secrets/sparkle_eddsa_private.key)
#   APPLE_ID / APPLE_APP_SPECIFIC_PASSWORD / APPLE_TEAM_ID  for notarytool
#   Or APPLE_API_KEY / APPLE_API_ISSUER / APPLE_API_KEY_PATH
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SKIP_NOTARIZE=0
PUBLISH=0
for arg in "$@"; do
  case "$arg" in
    --skip-notarize) SKIP_NOTARIZE=1 ;;
    --publish) PUBLISH=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ "$PUBLISH" -eq 1 && "$SKIP_NOTARIZE" -eq 1 ]]; then
  echo "ERROR: --publish cannot be combined with --skip-notarize." >&2
  exit 1
fi

# Build tools do not need the update signing key or notarization password.
# Keep these as shell-local values rather than passing them to every child.
release_sparkle_key="${SPARKLE_PRIVATE_KEY:-}"
release_notary_password="${APPLE_APP_SPECIFIC_PASSWORD:-}"
export -n release_sparkle_key release_notary_password
unset SPARKLE_PRIVATE_KEY APPLE_APP_SPECIFIC_PASSWORD

TEAM_ID="${APPLE_TEAM_ID:-97988GNC59}"
BUNDLE_ID="org.unitedvisions.ClipM"
SCHEME="ClipMenu"
CONFIG="Release"
REPO="${GITHUB_REPOSITORY:-Frazer/clipM}"

OUT="$ROOT/release"
if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  OUT="$OUT/local-test"
fi
STAGE="$OUT/stage"
DMG_ROOT="$OUT/dmg-root"
INBOX="$OUT/sparkle-inbox"
mkdir -p "$OUT" "$STAGE" "$DMG_ROOT" "$INBOX"

# Prefer MARKETING_VERSION / CURRENT_PROJECT_VERSION from project.yml via xcodebuild later.
MARKETING_VERSION="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("project.yml").read_text()
# First direct-distribution target marketing version
m = re.search(r"PRODUCT_NAME: clipM\n.*?MARKETING_VERSION: \"([^\"]+)\"", text, re.S)
print(m.group(1) if m else "1.0.0")
PY
)"
BUILD_NUMBER="$(python3 - <<'PY'
import re
from pathlib import Path
text = Path("project.yml").read_text()
m = re.search(r"PRODUCT_NAME: clipM\n.*?CURRENT_PROJECT_VERSION: \"([^\"]+)\"", text, re.S)
print(m.group(1) if m else "1")
PY
)"

TAG="${RELEASE_TAG:-v${MARKETING_VERSION}}"
if [[ ! "$MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ || "$TAG" != "v${MARKETING_VERSION}" ]]; then
  echo "ERROR: Release tag must match project version (v${MARKETING_VERSION}); versions must be numeric." >&2
  exit 1
fi
if [[ ! "$REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: Invalid GitHub repository." >&2
  exit 1
fi
DMG_NAME="clipM-${MARKETING_VERSION}.dmg"
DMG_PATH="$OUT/$DMG_NAME"

echo "==> Version ${MARKETING_VERSION} (${BUILD_NUMBER})  tag=${TAG}"

if ! command -v xcodegen >/dev/null; then
  echo "xcodegen is required (brew install xcodegen)" >&2
  exit 1
fi
xcodegen generate

IDENTITY=""
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' -v team="($TEAM_ID)" '/Developer ID Application/ && index($2, team) {print $2; exit}')"
if [[ -n "$IDENTITY" ]]; then
  echo "==> Using signing identity: $IDENTITY"
else
  echo "ERROR: No 'Developer ID Application' certificate found." >&2
  echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
  echo "Then re-run this script. (Apple Development certs are not enough for public DMG distribution.)" >&2
  exit 1
fi

echo "==> Building ${SCHEME} ${CONFIG}…"
DERIVED="$OUT/DerivedData"
rm -rf "$DERIVED"
xcodebuild \
  -project ClipMenu.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -derivedDataPath "$DERIVED" \
  -onlyUsePackageVersionsFromResolvedFile \
  -destination 'platform=macOS,arch=arm64' \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  build

# Use the checksum-verified Sparkle artifact resolved for this exact build.
# Never execute tools from unrelated DerivedData or an unchecked download.
SPARKLE_BIN_DIR="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
if [[ ! -x "$SPARKLE_BIN_DIR/generate_appcast" || ! -x "$SPARKLE_BIN_DIR/sign_update" ]]; then
  echo "ERROR: Sparkle tools missing from this build's resolved artifact." >&2
  exit 1
fi

APP_SRC="$(find "$DERIVED/Build/Products/$CONFIG" -maxdepth 1 -name 'clipM.app' -print -quit)"
if [[ -z "$APP_SRC" || ! -d "$APP_SRC" ]]; then
  echo "clipM.app not found in build products" >&2
  exit 1
fi

# Verify Sparkle public key made it into Info.plist
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP_SRC/Contents/Info.plist" >/dev/null
SPARKLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_SRC/Contents/Frameworks/Sparkle.framework/Resources/Info.plist")"
if [[ "$SPARKLE_VERSION" != "2.10.0" ]]; then
  echo "ERROR: Expected audited Sparkle 2.10.0, found $SPARKLE_VERSION." >&2
  exit 1
fi

rm -rf "$STAGE/clipM.app"
ditto "$APP_SRC" "$STAGE/clipM.app"

echo "==> Re-signing Sparkle helpers with Developer ID…"
SPARKLE="$STAGE/clipM.app/Contents/Frameworks/Sparkle.framework/Versions/B"
sign_developer_id() {
  codesign --force --sign "$IDENTITY" --options runtime --timestamp --preserve-metadata=entitlements "$1"
}
sign_developer_id "$SPARKLE/XPCServices/Downloader.xpc"
sign_developer_id "$SPARKLE/XPCServices/Installer.xpc"
sign_developer_id "$SPARKLE/Autoupdate"
sign_developer_id "$SPARKLE/Updater.app"
sign_developer_id "$STAGE/clipM.app/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --options runtime --timestamp \
  --entitlements "$ROOT/ClipMenu.entitlements" \
  "$STAGE/clipM.app"

echo "==> codesign verify…"
codesign --verify --deep --strict --verbose=2 "$STAGE/clipM.app"
codesign -dv --verbose=2 "$STAGE/clipM.app" 2>&1 | grep -E 'Authority|TeamIdentifier|Identifier' || true

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "==> Notarizing app (zip)…"
  APP_ZIP="$OUT/clipM-app.zip"
  ditto -c -k --keepParent "$STAGE/clipM.app" "$APP_ZIP"
  if [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_ISSUER:-}" && -n "${APPLE_API_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$APP_ZIP" \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY" \
      --issuer "$APPLE_API_ISSUER" \
      --wait
  elif [[ -n "${APPLE_ID:-}" && -n "$release_notary_password" ]]; then
    xcrun notarytool submit "$APP_ZIP" \
      --apple-id "$APPLE_ID" \
      --password "$release_notary_password" \
      --team-id "$TEAM_ID" \
      --wait
  else
    echo "ERROR: Notarization credentials missing. Pass --skip-notarize for a local unpackaged test," >&2
    echo "or set APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD (+ APPLE_TEAM_ID), or App Store Connect API key env vars." >&2
    exit 1
  fi
  xcrun stapler staple "$STAGE/clipM.app"
  xcrun stapler validate "$STAGE/clipM.app"
  # Gatekeeper can take a few seconds to observe a newly stapled ticket.
  assessed=0
  for _ in 1 2 3 4 5; do
    if spctl --assess --type execute -vv "$STAGE/clipM.app"; then
      assessed=1
      break
    fi
    sleep 2
  done
  if [[ "$assessed" -eq 0 ]]; then
    echo "ERROR: Gatekeeper assessment failed; refusing to package a public release." >&2
    exit 1
  fi
else
  echo "==> Skipping notarization (--skip-notarize)"
fi

echo "==> Creating DMG ${DMG_NAME}…"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$STAGE/clipM.app" "$DMG_ROOT/clipM.app"
ln -sf /Applications "$DMG_ROOT/Applications"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "clipM" \
  -srcfolder "$DMG_ROOT" \
  -ov -format UDZO \
  "$DMG_PATH"

# Sign the DMG with Developer ID as well (Gatekeeper)
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "==> Notarizing DMG…"
  if [[ -n "${APPLE_API_KEY:-}" && -n "${APPLE_API_ISSUER:-}" && -n "${APPLE_API_KEY_PATH:-}" ]]; then
    xcrun notarytool submit "$DMG_PATH" \
      --key "$APPLE_API_KEY_PATH" \
      --key-id "$APPLE_API_KEY" \
      --issuer "$APPLE_API_ISSUER" \
      --wait
  else
    xcrun notarytool submit "$DMG_PATH" \
      --apple-id "$APPLE_ID" \
      --password "$release_notary_password" \
      --team-id "$TEAM_ID" \
      --wait
  fi
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
fi
unset release_notary_password

if [[ "$SKIP_NOTARIZE" -eq 1 ]]; then
  echo "Local test DMG: $DMG_PATH (not notarized; no update feed generated)."
  exit 0
fi

echo "==> Generating Sparkle appcast…"
rm -rf "$INBOX"
mkdir -p "$INBOX"
cp "$DMG_PATH" "$INBOX/"

KEY_FILE=""
if [[ -n "$release_sparkle_key" ]]; then
  KEY_FILE="$(mktemp)"
  trap 'rm -f "$KEY_FILE"' EXIT
  chmod 600 "$KEY_FILE"
  printf '%s' "$release_sparkle_key" > "$KEY_FILE"
elif [[ -f "$ROOT/secrets/sparkle_eddsa_private.key" ]]; then
  KEY_FILE="$ROOT/secrets/sparkle_eddsa_private.key"
else
  echo "ERROR: Sparkle private key not found." >&2
  echo "Expected secrets/sparkle_eddsa_private.key or SPARKLE_PRIVATE_KEY env." >&2
  exit 1
fi
unset release_sparkle_key

DOWNLOAD_PREFIX="https://github.com/${REPO}/releases/download/${TAG}/"
"$SPARKLE_BIN_DIR/generate_appcast" \
  --account clipmenu \
  --ed-key-file "$KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --link "https://github.com/${REPO}" \
  --maximum-deltas 0 \
  "$INBOX"

cp "$INBOX/appcast.xml" "$OUT/appcast.xml"
"$SPARKLE_BIN_DIR/sign_update" --ed-key-file "$KEY_FILE" "$OUT/appcast.xml"
"$SPARKLE_BIN_DIR/sign_update" --verify --ed-key-file "$KEY_FILE" "$OUT/appcast.xml"
xcrun swift "$ROOT/scripts/verify-release.swift" \
  "$STAGE/clipM.app/Contents/Info.plist" "$DMG_PATH" "$OUT/appcast.xml" \
  "${DOWNLOAD_PREFIX}${DMG_NAME}"
ls -la "$OUT"

echo
echo "Artifacts:"
echo "  $DMG_PATH"
echo "  $OUT/appcast.xml"
echo
echo "Upload both as GitHub Release assets for tag ${TAG}."
echo "Sparkle feed URL: https://github.com/${REPO}/releases/latest/download/appcast.xml"

if [[ "$PUBLISH" -eq 1 ]]; then
  if ! command -v gh >/dev/null; then
    echo "gh CLI required for --publish" >&2
    exit 1
  fi
  echo "==> Publishing GitHub release ${TAG}…"
  if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG" "$DMG_PATH" "$OUT/appcast.xml" --repo "$REPO"
  else
    gh release create "$TAG" "$DMG_PATH" "$OUT/appcast.xml" \
      --repo "$REPO" --verify-tag \
      --title "clip'M ${MARKETING_VERSION}" \
      --notes "clip'M ${MARKETING_VERSION} (build ${BUILD_NUMBER}).

Full featured copy paste manager for M chip Macs.

Direct-download build with Sparkle updates. Open the DMG and drag clip'M to Applications."
  fi
  echo "Published: https://github.com/${REPO}/releases/tag/${TAG}"
fi

update_homebrew_cask() {
  local owner tap_dir sha
  owner="${REPO%%/*}"
  sha="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
  tap_dir="$(mktemp -d)"
  echo "==> Updating Homebrew cask ${owner}/clipm ${MARKETING_VERSION}…"
  gh repo clone "${owner}/homebrew-clipm" "$tap_dir" -- --depth 1
  python3 - "$tap_dir/Casks/clipm.rb" "$MARKETING_VERSION" "$sha" <<'PY'
import re, sys
from pathlib import Path
path, version, sha = sys.argv[1:]
file = Path(path)
file.write_text(re.sub(
    r'version "[^"]+"',
    f'version "{version}"',
    re.sub(r'sha256 "[^"]+"', f'sha256 "{sha}"', file.read_text(), count=1),
    count=1,
))
PY
  if git -C "$tap_dir" diff --quiet; then
    echo "Homebrew cask already matches ${MARKETING_VERSION}."
    return
  fi
  git -C "$tap_dir" add Casks/clipm.rb
  git -C "$tap_dir" commit -m "clipm ${MARKETING_VERSION}"
  git -C "$tap_dir" push origin HEAD
  echo "Homebrew cask updated: https://github.com/${owner}/homebrew-clipm"
}

if [[ "$PUBLISH" -eq 1 ]]; then
  update_homebrew_cask
fi
