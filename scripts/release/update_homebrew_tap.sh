#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

usage() {
  cat <<'USAGE'
Usage:
  scripts/release/update_homebrew_tap.sh --tap-dir /path/to/homebrew-tap \
    --version 1.0.0 --sha256 SHA --repository owner/repo

Options:
  --tap-dir PATH
  --version VERSION
  --sha256 SHA256
  --repository OWNER/REPO
  --tap-repository OWNER/HOMEBREW_REPO  Accepted for workflow compatibility.
  --tap-name OWNER/TAP                 Accepted for workflow compatibility.
  --homepage URL
  --minimum-macos HOMEBREW_VALUE       Example: ">= :tahoe"
  --audit                              Unsupported; audit after committing the tap.
  --brew PATH                          Defaults to BREW_BIN or brew.
  --tap-timeout SECONDS                Accepted for compatibility.
  --audit-timeout SECONDS              Defaults to 600.
  --help

The script updates Casks/holdtype.rb inside an existing tap checkout. It does
not clone, commit, push, or open a pull request.
USAGE
}

TAP_DIR=""
VERSION=""
SHA256=""
REPOSITORY="${GITHUB_REPOSITORY:-}"
TAP_REPOSITORY="${HOMEBREW_TAP_REPOSITORY:-}"
TAP_NAME=""
HOMEPAGE=""
MINIMUM_MACOS="${HOMEBREW_MINIMUM_MACOS:-}"
AUDIT=0
BREW_BIN="${BREW_BIN:-brew}"
TAP_TIMEOUT=300
AUDIT_TIMEOUT=600

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tap-dir)
      TAP_DIR="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --sha256)
      SHA256="$2"
      shift 2
      ;;
    --repository)
      REPOSITORY="$2"
      shift 2
      ;;
    --tap-repository)
      TAP_REPOSITORY="$2"
      shift 2
      ;;
    --tap-name)
      TAP_NAME="$2"
      shift 2
      ;;
    --homepage)
      HOMEPAGE="$2"
      shift 2
      ;;
    --minimum-macos)
      MINIMUM_MACOS="$2"
      shift 2
      ;;
    --audit)
      AUDIT=1
      shift
      ;;
    --brew)
      BREW_BIN="$2"
      shift 2
      ;;
    --tap-timeout)
      TAP_TIMEOUT="$2"
      shift 2
      ;;
    --audit-timeout)
      AUDIT_TIMEOUT="$2"
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

[ -n "$TAP_DIR" ] || die "missing --tap-dir"
[ -n "$VERSION" ] || die "missing --version"
[ -n "$SHA256" ] || die "missing --sha256"
[ -n "$REPOSITORY" ] || die "missing --repository"

validate_release_version "$VERSION"

case "$SHA256" in
  *[!0-9a-fA-F]*)
    die "sha256 must be a 64-character hex digest"
    ;;
esac
[ "${#SHA256}" -eq 64 ] || die "sha256 must be a 64-character hex digest"
SHA256="$(printf '%s' "$SHA256" | tr '[:upper:]' '[:lower:]')"

render_args=(
  --version "$VERSION"
  --sha256 "$SHA256"
  --repository "$REPOSITORY"
  --output "$TAP_DIR/Casks/holdtype.rb"
)

if [ -n "$HOMEPAGE" ]; then
  render_args+=(--homepage "$HOMEPAGE")
fi
if [ -n "$MINIMUM_MACOS" ]; then
  render_args+=(--minimum-macos "$MINIMUM_MACOS")
fi

"$SCRIPT_DIR/render_homebrew_cask.sh" "${render_args[@]}"

if [ "$AUDIT" -eq 1 ]; then
  die "--audit must run after committing the tap checkout; use brew tap <tap> <tap-dir> and brew audit --new --cask <tap>/holdtype"
fi

log "updated Homebrew tap cask: $TAP_DIR/Casks/holdtype.rb"
