#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release/build_release.sh --version 1.0.0 --build 100

Required environment:
  APPLE_TEAM_ID
  HOLDTYPE_UPDATE_FEED_URL
  HOLDTYPE_UPDATE_PUBLIC_ED_KEY

Notarization environment, unless --skip-notarization is used:
  NOTARY_KEYCHAIN_PROFILE
    or
  APP_STORE_CONNECT_API_KEY_PATH
  APP_STORE_CONNECT_KEY_ID
  APP_STORE_CONNECT_ISSUER_ID

Options:
  --version VERSION          Marketing version without leading v
  --build BUILD             CFBundleVersion / Sparkle build number
  --release-dir PATH        Output directory, default dist/release/vVERSION
  --skip-notarization       Build verification artifacts without submitting to Apple.
                            The manifest is marked notarization-skipped-release
                            and is not a public release artifact.
  --help
USAGE
}

VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-}}"
RELEASE_DIR=""
SKIP_NOTARIZATION=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --build)
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --release-dir)
      RELEASE_DIR="$2"
      shift 2
      ;;
    --skip-notarization)
      SKIP_NOTARIZATION=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

if [ -z "$VERSION" ] && [ -n "${GITHUB_REF_NAME:-}" ]; then
  VERSION="$(release_version_from_tag "$GITHUB_REF_NAME")"
fi

[ -n "$VERSION" ] || die "missing --version"
[ -n "$BUILD_NUMBER" ] || die "missing --build"
validate_release_version "$VERSION"
validate_build_number "$BUILD_NUMBER"

RELEASE_TAG="$(release_tag_for_version "$VERSION")"
RELEASE_DIR="${RELEASE_DIR:-$RELEASE_ROOT/$RELEASE_TAG}"
DERIVED_DATA_DIR="${DERIVED_DATA_DIR:-$RELEASE_DIR/DerivedData}"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$RELEASE_DIR/export"
APP_PATH="$EXPORT_PATH/$APP_NAME.app"
APP_NOTARY_ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION-notary.zip"
APP_ZIP_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.zip"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"
APP_ZIP_FILE="$(basename "$APP_ZIP_PATH")"
DMG_FILE="$(basename "$DMG_PATH")"
STAGING_DIR="$RELEASE_DIR/dmg-staging"
MANIFEST_PATH="$RELEASE_DIR/release-manifest.json"
SHA256SUMS_PATH="$RELEASE_DIR/SHA256SUMS.txt"
SHA256SUMS_FILE="$(basename "$SHA256SUMS_PATH")"

XCODEBUILD_TIMEOUT_SECONDS="${XCODEBUILD_TIMEOUT_SECONDS:-2400}"
NOTARY_TIMEOUT_SECONDS="${NOTARY_TIMEOUT_SECONDS:-2400}"
DISK_IMAGE_TIMEOUT_SECONDS="${DISK_IMAGE_TIMEOUT_SECONDS:-600}"

require_command xcodebuild
require_command xcrun
require_command codesign
require_command spctl
require_command hdiutil
require_command ditto
require_command shasum

require_env APPLE_TEAM_ID
require_env HOLDTYPE_UPDATE_FEED_URL
require_env HOLDTYPE_UPDATE_PUBLIC_ED_KEY

RELEASE_CODE_SIGN_IDENTITY="${HOLDTYPE_CODE_SIGN_IDENTITY:-Developer ID Application}"
RELEASE_CODE_SIGN_STYLE="${HOLDTYPE_CODE_SIGN_STYLE:-Manual}"

if [ "$SKIP_NOTARIZATION" -eq 0 ]; then
  NOTARY_ARGS=()
  while IFS= read -r notary_arg; do
    NOTARY_ARGS+=("$notary_arg")
  done < <(notary_credentials_args)
else
  NOTARY_ARGS=()
fi

safe_rm_generated_dir "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

log "resolving Swift packages"
run_timed "$XCODEBUILD_TIMEOUT_SECONDS" \
  xcodebuild \
  -project "$REPO_ROOT/$XCODE_PROJECT" \
  -scheme "$XCODE_SCHEME" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  -resolvePackageDependencies

log "archiving $APP_NAME $VERSION ($BUILD_NUMBER)"
run_timed "$XCODEBUILD_TIMEOUT_SECONDS" \
  xcodebuild archive \
  -project "$REPO_ROOT/$XCODE_PROJECT" \
  -scheme "$XCODE_SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  HOLDTYPE_DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  HOLDTYPE_CODE_SIGN_IDENTITY="$RELEASE_CODE_SIGN_IDENTITY" \
  HOLDTYPE_CODE_SIGN_STYLE="$RELEASE_CODE_SIGN_STYLE" \
  HOLDTYPE_UPDATE_FEED_URL="$HOLDTYPE_UPDATE_FEED_URL" \
  HOLDTYPE_UPDATE_PUBLIC_ED_KEY="$HOLDTYPE_UPDATE_PUBLIC_ED_KEY"

log "exporting Developer ID app"
run_timed "$XCODEBUILD_TIMEOUT_SECONDS" \
  xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$REPO_ROOT/Config/ExportOptions.DeveloperID.plist"

[ -d "$APP_PATH" ] || die "exported app not found at $APP_PATH"

log "verifying release update settings"
"$SCRIPT_DIR/verify_app_update_settings.py" \
  --app "$APP_PATH" \
  --expected-feed-url "$HOLDTYPE_UPDATE_FEED_URL" \
  --expected-public-ed-key "$HOLDTYPE_UPDATE_PUBLIC_ED_KEY"

log "verifying app signature"
run_timed 300 codesign --verify --deep --strict --verbose=2 "$APP_PATH"

log "creating app archive"
ditto -c -k --keepParent "$APP_PATH" "$APP_NOTARY_ZIP_PATH"

if [ "$SKIP_NOTARIZATION" -eq 0 ]; then
  log "notarizing app archive"
  run_timed "$NOTARY_TIMEOUT_SECONDS" \
    xcrun notarytool submit "$APP_NOTARY_ZIP_PATH" --wait "${NOTARY_ARGS[@]}"

  log "stapling app"
  run_timed 300 xcrun stapler staple "$APP_PATH"
else
  log "skipping notarization"
fi

log "creating release zip"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP_PATH"

log "creating DMG"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
run_timed "$DISK_IMAGE_TIMEOUT_SECONDS" \
  hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

log "signing DMG"
run_timed 300 \
  codesign \
  --force \
  --timestamp \
  --sign "$RELEASE_CODE_SIGN_IDENTITY" \
  "$DMG_PATH"

if [ "$SKIP_NOTARIZATION" -eq 0 ]; then
  log "notarizing DMG"
  run_timed "$NOTARY_TIMEOUT_SECONDS" \
    xcrun notarytool submit "$DMG_PATH" --wait "${NOTARY_ARGS[@]}"

  log "stapling DMG"
  run_timed 300 xcrun stapler staple "$DMG_PATH"
fi

log "writing checksums"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$DMG_FILE" "$APP_ZIP_FILE" > "$SHA256SUMS_FILE"
)

DMG_SHA256="$(sha256_for_file "$DMG_PATH")"
ZIP_SHA256="$(sha256_for_file "$APP_ZIP_PATH")"

if [ "$SKIP_NOTARIZATION" -eq 0 ]; then
  ARTIFACT_KIND="public-release"
  NOTARIZED_JSON=true
  PUBLIC_RELEASE_JSON=true
else
  ARTIFACT_KIND="notarization-skipped-release"
  NOTARIZED_JSON=false
  PUBLIC_RELEASE_JSON=false
fi

cat > "$MANIFEST_PATH" <<EOF
{
  "app": "$APP_NAME",
  "kind": "$ARTIFACT_KIND",
  "version": "$VERSION",
  "build": "$BUILD_NUMBER",
  "tag": "$RELEASE_TAG",
  "notarized": $NOTARIZED_JSON,
  "public_release": $PUBLIC_RELEASE_JSON,
  "dmg": {
    "path": "$DMG_FILE",
    "sha256": "$DMG_SHA256"
  },
  "zip": {
    "path": "$APP_ZIP_FILE",
    "sha256": "$ZIP_SHA256"
  }
}
EOF

"$SCRIPT_DIR/verify_release_manifest.py" \
  --manifest "$MANIFEST_PATH" \
  --artifact-root "$RELEASE_DIR" \
  --expect-kind "$ARTIFACT_KIND" \
  --expect-public-release "$PUBLIC_RELEASE_JSON" \
  --expect-notarized "$NOTARIZED_JSON" \
  --require-relative-artifact-paths

log "release artifacts ready: $RELEASE_DIR"
