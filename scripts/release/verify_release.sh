#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release/verify_release.sh --release-dir dist/release/v1.0.0

Options:
  --release-dir PATH
  --skip-stapler
  --skip-spctl
  --skip-dmg-layout
  --skip-update-settings
  --help
USAGE
}

RELEASE_DIR=""
SKIP_STAPLER=0
SKIP_SPCTL=0
SKIP_DMG_LAYOUT=0
SKIP_UPDATE_SETTINGS=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --release-dir)
      RELEASE_DIR="$2"
      shift 2
      ;;
    --skip-stapler)
      SKIP_STAPLER=1
      shift
      ;;
    --skip-spctl)
      SKIP_SPCTL=1
      shift
      ;;
    --skip-dmg-layout)
      SKIP_DMG_LAYOUT=1
      shift
      ;;
    --skip-update-settings)
      SKIP_UPDATE_SETTINGS=1
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

[ -n "$RELEASE_DIR" ] || die "missing --release-dir"

APP_PATH="$RELEASE_DIR/export/$APP_NAME.app"
MANIFEST_PATH="$RELEASE_DIR/release-manifest.json"
SHA256SUMS_PATH="$RELEASE_DIR/SHA256SUMS.txt"

[ -d "$APP_PATH" ] || die "app not found at $APP_PATH"
[ -f "$MANIFEST_PATH" ] || die "release-manifest.json not found in $RELEASE_DIR"
[ -f "$SHA256SUMS_PATH" ] || die "SHA256SUMS.txt not found in $RELEASE_DIR"
require_command python3

"$SCRIPT_DIR/verify_release_manifest.py" \
  --manifest "$MANIFEST_PATH" \
  --artifact-root "$RELEASE_DIR" \
  --expect-kind public-release \
  --expect-public-release true \
  --expect-notarized true \
  --require-relative-artifact-paths

if ! DMG_FILE="$(
  python3 - "$MANIFEST_PATH" <<'PY'
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
data = json.loads(manifest_path.read_text())
dmg = data.get("dmg")
if not isinstance(dmg, dict):
    raise SystemExit("manifest dmg object is missing")
path = dmg.get("path")
if not isinstance(path, str) or not path:
    raise SystemExit("manifest dmg.path is missing")
print(path)
PY
)"; then
  die "could not read DMG path from release-manifest.json"
fi
case "$DMG_FILE" in
  /*|*/*)
    die "manifest dmg.path must be an artifact filename: $DMG_FILE"
    ;;
esac
DMG_PATH="$RELEASE_DIR/$DMG_FILE"
[ -f "$DMG_PATH" ] || die "manifest DMG not found: $DMG_PATH"

if [ "$SKIP_DMG_LAYOUT" -eq 0 ]; then
  "$SCRIPT_DIR/verify_dmg_layout.sh" --dmg "$DMG_PATH"
fi

"$SCRIPT_DIR/verify_dmg_install.sh" --dmg "$DMG_PATH"

if [ "$SKIP_UPDATE_SETTINGS" -eq 0 ]; then
  "$SCRIPT_DIR/verify_app_update_settings.py" \
    --app "$APP_PATH" \
    --require-configured
fi

log "verifying app signature"
run_timed 300 codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [ "$SKIP_SPCTL" -eq 0 ]; then
  log "assessing app with Gatekeeper"
  run_timed 300 spctl --assess --type execute --verbose=4 "$APP_PATH"
fi

if [ "$SKIP_STAPLER" -eq 0 ]; then
  log "validating app staple"
  run_timed 300 xcrun stapler validate "$APP_PATH"

  log "verifying DMG signature"
  run_timed 300 codesign --verify --verbose=2 "$DMG_PATH"

  log "validating DMG staple"
  run_timed 300 xcrun stapler validate "$DMG_PATH"
fi

if [ "$SKIP_SPCTL" -eq 0 ]; then
  log "assessing DMG with Gatekeeper"
  run_timed 300 spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
fi

log "checking SHA-256 sums"
(
  cd "$RELEASE_DIR"
  shasum -a 256 -c "$(basename "$SHA256SUMS_PATH")"
)

log "release verification passed"
