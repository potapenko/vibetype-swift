#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release/write_release_notes.sh --version 1.0.0 --output /tmp/release-notes.md

Options:
  --version VERSION       Release version without leading v.
  --output PATH
  --source PATH           Optional curated Markdown notes to copy.
  --help

The generated notes are shared by Sparkle appcast generation and the GitHub
Release body so users see the same release summary in both update channels.
USAGE
}

VERSION=""
OUTPUT_PATH=""
SOURCE_PATH=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    --source)
      SOURCE_PATH="$2"
      shift 2
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

[ -n "$VERSION" ] || die "missing --version"
[ -n "$OUTPUT_PATH" ] || die "missing --output"
validate_release_version "$VERSION"

mkdir -p "$(dirname "$OUTPUT_PATH")"

if [ -z "$SOURCE_PATH" ]; then
  CURATED_SOURCE="$REPO_ROOT/docs/release/notes/$VERSION.md"
  if [ -f "$CURATED_SOURCE" ]; then
    SOURCE_PATH="$CURATED_SOURCE"
  fi
fi

if [ -n "$SOURCE_PATH" ]; then
  [ -f "$SOURCE_PATH" ] || die "release notes source not found: $SOURCE_PATH"
  cp "$SOURCE_PATH" "$OUTPUT_PATH"
else
  cat > "$OUTPUT_PATH" <<EOF
# HoldType $VERSION

This release includes the signed and notarized macOS disk image, Sparkle
appcast metadata, and checksum manifest.
EOF
fi

"$SCRIPT_DIR/verify_release_notes.py" \
  --notes-file "$OUTPUT_PATH" \
  --version "$VERSION" \
  --quiet

log "release notes ready: $OUTPUT_PATH"
