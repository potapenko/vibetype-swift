#!/usr/bin/env python3
"""Verify release workflow wiring for build, publish, Sparkle, and Homebrew steps."""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path


EXPECTED_STEP_ORDER = (
    "Checkout",
    "Resolve release inputs",
    "Show Xcode version",
    "Validate release inputs",
    "Release preflight",
    "Validate clean source diff",
    "Run tests",
    "Import Developer ID certificate",
    "Write notarization and Sparkle keys",
    "Build notarized release artifacts",
    "Write release notes",
    "Fetch existing appcast",
    "Generate Sparkle appcast",
    "Verify release artifacts",
    "Verify install channel metadata",
    "Prune unexpected GitHub Release assets",
    "Publish GitHub Release assets",
    "Prepare Pages artifact",
    "Configure Pages",
    "Upload Pages artifact",
    "Deploy appcast to Pages",
    "Verify published release",
    "Prepare official Homebrew cask submission bundle",
    "Upload official Homebrew cask submission bundle",
    "Update Homebrew tap",
    "Open official Homebrew Cask bump PR",
)

REQUIRED_FRAGMENTS = {
    "trigger:tag": 'tags:\n      - "v*"',
    "trigger:manual": "workflow_dispatch:",
    "permission:contents": "contents: write",
    "permission:pages": "pages: write",
    "permission:id-token": "id-token: write",
    "environment:github-pages": "name: github-pages",
    "runner:macos-26": "runs-on: macos-26",
    "release-inputs:version": 'version="${{ inputs.version }}"',
    "release-inputs:tag": 'tag="v${version}"',
    "release-inputs:download-url-prefix": "download_url_prefix=https://github.com/${GITHUB_REPOSITORY}/releases/download/$tag/",
    "script:validate-release-inputs": "scripts/release/validate_release_inputs.py",
    "script:preflight": "scripts/release/preflight.py --require-secrets --require-homebrew-tap --json",
    "script:timeout-tests": "scripts/release/with_timeout.py 2400",
    "script:build-release": "scripts/release/build_release.sh",
    "script:write-release-notes": "scripts/release/write_release_notes.sh",
    "script:verify-release-notes": "scripts/release/verify_release_notes.py",
    "script:fetch-existing-appcast": "scripts/release/fetch_existing_appcast.py",
    "script:generate-appcast": "scripts/release/generate_appcast.sh",
    "script:verify-release": "scripts/release/verify_release.sh",
    "script:verify-install-channels": "scripts/release/verify_install_channels.py",
    "install-channels:minimum-macos": "--minimum-macos \"$HOMEBREW_MINIMUM_MACOS\"",
    "script:prune-github-release-assets": "scripts/release/prune_github_release_assets.py",
    "prune-github-release-assets:apply": "--apply",
    "prune-github-release-assets:timeout": "--timeout 300",
    "script:verify-published-release": "scripts/release/verify_published_release.py",
    "published-release:download-dmg": "--download-dmg",
    "published-release:verify-downloaded-dmg-install": "--verify-downloaded-dmg-install",
    "publish:gh-release-view-timeout": "scripts/release/with_timeout.py 300 gh release view",
    "publish:gh-release-upload-timeout": "scripts/release/with_timeout.py 900 gh release upload",
    "publish:gh-release-edit-timeout": "scripts/release/with_timeout.py 300 gh release edit",
    "publish:gh-release-edit-draft-false": "--draft=false",
    "publish:gh-release-edit-prerelease-false": "--prerelease=false",
    "publish:gh-release-create-timeout": "scripts/release/with_timeout.py 900 gh \"${release_create_args[@]}\"",
    "pages:configure": "actions/configure-pages@v5",
    "pages:upload": "actions/upload-pages-artifact@v4",
    "pages:deploy": "actions/deploy-pages@v4",
    "homebrew:minimum-macos-variable": "HOMEBREW_MINIMUM_MACOS: ${{ vars.HOMEBREW_MINIMUM_MACOS }}",
    "homebrew:tap-repository-variable": "HOMEBREW_TAP_REPOSITORY: ${{ vars.HOMEBREW_TAP_REPOSITORY }}",
    "homebrew:expected-tap-variable": "HOMEBREW_EXPECTED_TAP: ${{ vars.HOMEBREW_EXPECTED_TAP }}",
    "homebrew:official-bump-enabled-variable": "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED: ${{ vars.HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED }}",
    "homebrew:official-bump-fork-org-variable": "HOMEBREW_OFFICIAL_CASK_FORK_ORG: ${{ vars.HOMEBREW_OFFICIAL_CASK_FORK_ORG }}",
    "homebrew:official-bump-token-secret": "HOMEBREW_GITHUB_API_TOKEN: ${{ secrets.HOMEBREW_GITHUB_API_TOKEN }}",
    "script:homebrew-cask-submission": "scripts/release/write_homebrew_cask_submission.py",
    "homebrew:official-artifact-upload": "actions/upload-artifact@v4",
    "homebrew:official-artifact-name": "holdtype-official-homebrew-cask-${{ steps.release-inputs.outputs.version }}",
    "script:update-homebrew-tap": "scripts/release/update_homebrew_tap.sh",
    "homebrew:tap-if-requires-minimum-macos": "env.HOMEBREW_TAP_REPOSITORY != '' && env.HOMEBREW_TAP_TOKEN != '' && env.HOMEBREW_MINIMUM_MACOS != ''",
    "homebrew:tap-minimum-macos-argument": "--minimum-macos \"$HOMEBREW_MINIMUM_MACOS\"",
    "homebrew:tap-clone-timeout": "scripts/release/with_timeout.py 300 \\\n            git clone",
    "homebrew:tap-default-branch-timeout": "scripts/release/with_timeout.py 300 gh repo view \"$HOMEBREW_TAP_REPOSITORY\"",
    "homebrew:tap-pr-base-default-branch": "--base \"$tap_default_branch\"",
    "homebrew:tap-push-timeout": "scripts/release/with_timeout.py 300 \\\n            git -C \"$tap_dir\" push",
    "homebrew:tap-pr-list-timeout": "scripts/release/with_timeout.py 300 gh pr list",
    "homebrew:tap-pr-create-timeout": "scripts/release/with_timeout.py 300 gh pr create",
    "homebrew:audit-tap-timeout": "scripts/release/with_timeout.py 300 \\\n            brew tap",
    "homebrew:audit-command-timeout": "scripts/release/with_timeout.py 600 \\\n            brew audit --cask \"$HOMEBREW_EXPECTED_TAP/holdtype\"",
    "homebrew:reuse-pr": "Homebrew tap pull request already exists",
    "homebrew:official-bump-if": "env.HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED == 'true' && env.HOMEBREW_GITHUB_API_TOKEN != ''",
    "script:bump-official-homebrew-cask": "scripts/release/bump_official_homebrew_cask_pr.sh",
    "homebrew:official-bump-timeout": "--timeout 900",
}


@dataclass(frozen=True)
class Check:
    name: str
    status: str
    message: str

    def to_json(self) -> dict[str, str]:
        return {"name": self.name, "status": self.status, "message": self.message}


def pass_check(name: str, message: str) -> Check:
    return Check(name=name, status="pass", message=message)


def fail_check(name: str, message: str) -> Check:
    return Check(name=name, status="fail", message=message)


def normalize_step_name(raw_name: str) -> str:
    return raw_name.strip().strip("\"'")


def workflow_step_positions(text: str) -> dict[str, int]:
    positions: dict[str, int] = {}
    for index, line in enumerate(text.splitlines(), start=1):
        match = re.match(r"\s*-\s+name:\s*(.+?)\s*$", line)
        if not match:
            continue
        positions[normalize_step_name(match.group(1))] = index
    return positions


def check_workflow_path(path: Path) -> tuple[str | None, list[Check]]:
    if not path.exists():
        return None, [fail_check("workflow:file", f"missing {path}")]
    return path.read_text(), [pass_check("workflow:file", str(path))]


def check_step_order(text: str) -> list[Check]:
    positions = workflow_step_positions(text)
    checks: list[Check] = []
    previous_line = 0
    for step in EXPECTED_STEP_ORDER:
        line = positions.get(step)
        if line is None:
            checks.append(fail_check(f"workflow-step:{step}", "missing"))
            continue
        if line <= previous_line:
            checks.append(
                fail_check(
                    f"workflow-step:{step}",
                    f"out of order at line {line}; expected after line {previous_line}",
                )
            )
        else:
            checks.append(pass_check(f"workflow-step:{step}", f"line {line}"))
            previous_line = line
    return checks


def check_fragments(text: str) -> list[Check]:
    checks: list[Check] = []
    for name, fragment in REQUIRED_FRAGMENTS.items():
        if fragment in text:
            checks.append(pass_check(f"workflow:{name}", "present"))
        else:
            checks.append(fail_check(f"workflow:{name}", f"missing {fragment!r}"))
    return checks


def collect_checks(workflow_path: Path) -> list[Check]:
    text, checks = check_workflow_path(workflow_path)
    if text is None:
        return checks
    checks.extend(check_step_order(text))
    checks.extend(check_fragments(text))
    return checks


def print_text(checks: list[Check]) -> None:
    for check in checks:
        print(f"[{check.status}] {check.name}: {check.message}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workflow", default=".github/workflows/release.yml")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    checks = collect_checks(Path(args.workflow))
    if args.json:
        print(json.dumps({"checks": [check.to_json() for check in checks]}, indent=2))
    else:
        print_text(checks)

    return 1 if any(check.status == "fail" for check in checks) else 0


if __name__ == "__main__":
    raise SystemExit(main())
