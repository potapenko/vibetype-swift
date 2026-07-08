#!/usr/bin/env python3
"""Tests for release automation helpers."""

from __future__ import annotations

import base64
import importlib.util
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT_PATH = ROOT / "scripts" / "release" / "preflight.py"
BUMP_OFFICIAL_CASK_PR_SCRIPT = (
    ROOT / "scripts" / "release" / "bump_official_homebrew_cask_pr.sh"
)
BUILD_RELEASE_SCRIPT = ROOT / "scripts" / "release" / "build_release.sh"
RENDER_CASK_SCRIPT = ROOT / "scripts" / "release" / "render_homebrew_cask.sh"
PREVIEW_DMG_SCRIPT = ROOT / "scripts" / "release" / "build_preview_dmg.sh"
CREATE_OFFICIAL_CASK_PR_SCRIPT = (
    ROOT / "scripts" / "release" / "create_official_homebrew_cask_pr.sh"
)
FETCH_EXISTING_APPCAST_SCRIPT = ROOT / "scripts" / "release" / "fetch_existing_appcast.py"
GENERATE_APPCAST_SCRIPT = ROOT / "scripts" / "release" / "generate_appcast.sh"
OPEN_OFFICIAL_CASK_FROM_BUNDLE_SCRIPT = (
    ROOT / "scripts" / "release" / "open_official_homebrew_cask_pr_from_bundle.sh"
)
PREPARE_OFFICIAL_CASK_SCRIPT = ROOT / "scripts" / "release" / "prepare_official_homebrew_cask.sh"
PRUNE_GITHUB_RELEASE_ASSETS_SCRIPT = ROOT / "scripts" / "release" / "prune_github_release_assets.py"
UPDATE_TAP_SCRIPT = ROOT / "scripts" / "release" / "update_homebrew_tap.sh"
VALIDATE_RELEASE_INPUTS_SCRIPT = ROOT / "scripts" / "release" / "validate_release_inputs.py"
VERIFY_UPDATE_SETTINGS_SCRIPT = ROOT / "scripts" / "release" / "verify_app_update_settings.py"
VERIFY_DMG_INSTALL_SCRIPT = ROOT / "scripts" / "release" / "verify_dmg_install.sh"
VERIFY_DMG_LAYOUT_SCRIPT = ROOT / "scripts" / "release" / "verify_dmg_layout.sh"
VERIFY_GITHUB_SETUP_SCRIPT = ROOT / "scripts" / "release" / "verify_github_release_setup.py"
VERIFY_HOMEBREW_CASK_SCRIPT = ROOT / "scripts" / "release" / "verify_homebrew_cask.py"
VERIFY_HOMEBREW_TAP_RELEASE_SCRIPT = (
    ROOT / "scripts" / "release" / "verify_homebrew_tap_release.py"
)
VERIFY_CHANNELS_SCRIPT = ROOT / "scripts" / "release" / "verify_install_channels.py"
VERIFY_PUBLISHED_RELEASE_SCRIPT = ROOT / "scripts" / "release" / "verify_published_release.py"
VERIFY_RELEASE_MANIFEST_SCRIPT = ROOT / "scripts" / "release" / "verify_release_manifest.py"
VERIFY_RELEASE_NOTES_SCRIPT = ROOT / "scripts" / "release" / "verify_release_notes.py"
VERIFY_RELEASE_WORKFLOW_SCRIPT = ROOT / "scripts" / "release" / "verify_release_workflow.py"
TIMEOUT_SCRIPT = ROOT / "scripts" / "release" / "with_timeout.py"
WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT = (
    ROOT / "scripts" / "release" / "write_homebrew_cask_submission.py"
)
WRITE_RELEASE_NOTES_SCRIPT = ROOT / "scripts" / "release" / "write_release_notes.sh"
RELEASE_WORKFLOW = ROOT / ".github" / "workflows" / "release.yml"


def load_preflight_module():
    spec = importlib.util.spec_from_file_location("release_preflight", PREFLIGHT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load release preflight module")
    module = importlib.util.module_from_spec(spec)
    sys.modules["release_preflight"] = module
    spec.loader.exec_module(module)
    return module


def load_published_release_module():
    spec = importlib.util.spec_from_file_location(
        "verify_published_release",
        VERIFY_PUBLISHED_RELEASE_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load verify_published_release module")
    module = importlib.util.module_from_spec(spec)
    sys.modules["verify_published_release"] = module
    spec.loader.exec_module(module)
    return module


def load_github_setup_module():
    spec = importlib.util.spec_from_file_location(
        "verify_github_release_setup",
        VERIFY_GITHUB_SETUP_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load verify_github_release_setup module")
    module = importlib.util.module_from_spec(spec)
    sys.modules["verify_github_release_setup"] = module
    spec.loader.exec_module(module)
    return module


def load_homebrew_tap_release_module():
    spec = importlib.util.spec_from_file_location(
        "verify_homebrew_tap_release",
        VERIFY_HOMEBREW_TAP_RELEASE_SCRIPT,
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load verify_homebrew_tap_release module")
    module = importlib.util.module_from_spec(spec)
    sys.modules["verify_homebrew_tap_release"] = module
    spec.loader.exec_module(module)
    return module


def rendered_official_cask_text(
    *,
    version: str = "1.2.3",
    sha256: str = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    repository: str = "holdtype/holdtype-swift",
) -> str:
    return f"""cask "holdtype" do
  version "{version}"
  sha256 "{sha256}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/HoldType-#{{version}}.dmg",
      verified: "github.com/{repository}/"
  name "HoldType"
  desc "Native macOS menu bar dictation utility"
  homepage "https://github.com/{repository}"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true

  app "HoldType.app"

  uninstall quit: "app.holdtype.HoldType"

  zap trash: [
    "~/Library/Caches/HoldType",
    "~/Library/Preferences/app.holdtype.HoldType.plist",
    "~/Library/Saved Application State/app.holdtype.HoldType.savedState",
  ]
end
"""


class ReleaseScriptsTests(unittest.TestCase):
    def test_repo_api_url_omits_empty_suffix_trailing_slash(self) -> None:
        github_setup = load_github_setup_module()
        homebrew_tap_release = load_homebrew_tap_release_module()

        for module in (github_setup, homebrew_tap_release):
            self.assertEqual(
                module.repo_api_url(
                    "https://api.github.com/",
                    "holdtype-swift/homebrew-tap",
                    "",
                ),
                "https://api.github.com/repos/holdtype-swift/homebrew-tap",
            )
            self.assertEqual(
                module.repo_api_url(
                    "https://api.github.com/",
                    "holdtype/holdtype-swift",
                    "/pages",
                ),
                "https://api.github.com/repos/holdtype/holdtype-swift/pages",
            )

    def test_parse_xcode_build_settings_reads_release_values(self) -> None:
        module = load_preflight_module()

        settings = module.parse_xcode_build_settings(
            """
                ENABLE_HARDENED_RUNTIME = YES
                MACOSX_DEPLOYMENT_TARGET = 26.5
            """
        )

        self.assertEqual(settings["ENABLE_HARDENED_RUNTIME"], "YES")
        self.assertEqual(settings["MACOSX_DEPLOYMENT_TARGET"], "26.5")

    def test_secret_preflight_fails_only_when_required(self) -> None:
        module = load_preflight_module()

        optional_checks = module.check_secret_environment(
            require_secrets=False,
            environment={},
        )
        required_checks = module.check_secret_environment(
            require_secrets=True,
            environment={},
        )

        self.assertTrue(all(check.status == "warn" for check in optional_checks))
        self.assertTrue(all(check.status == "fail" for check in required_checks))

    def test_homebrew_tap_preflight_warns_when_absent_and_fails_when_partial(self) -> None:
        module = load_preflight_module()

        absent_checks = module.check_homebrew_tap_environment({})
        required_absent_checks = module.check_homebrew_tap_environment(
            {},
            require_homebrew_tap=True,
        )
        partial_checks = module.check_homebrew_tap_environment(
            {"HOMEBREW_TAP_REPOSITORY": "holdtype/homebrew-tap"}
        )
        wrong_expected_tap_checks = module.check_homebrew_tap_environment(
            {
                "HOMEBREW_TAP_REPOSITORY": "potapenko/homebrew-tap",
                "HOMEBREW_EXPECTED_TAP": "holdtype/tap",
                "HOMEBREW_TAP_TOKEN": "token",
                "HOMEBREW_MINIMUM_MACOS": ">= :tahoe",
            }
        )
        invalid_minimum_checks = module.check_homebrew_tap_environment(
            {
                "HOMEBREW_TAP_REPOSITORY": "holdtype/homebrew-tap",
                "HOMEBREW_EXPECTED_TAP": "holdtype/tap",
                "HOMEBREW_TAP_TOKEN": "token",
                "HOMEBREW_MINIMUM_MACOS": "tahoe",
            }
        )
        invalid_repository_name_checks = module.check_homebrew_tap_environment(
            {
                "HOMEBREW_TAP_REPOSITORY": "holdtype/tap",
                "HOMEBREW_EXPECTED_TAP": "holdtype/tap",
                "HOMEBREW_TAP_TOKEN": "token",
                "HOMEBREW_MINIMUM_MACOS": ">= :tahoe",
            }
        )
        configured_checks = module.check_homebrew_tap_environment(
            {
                "HOMEBREW_TAP_REPOSITORY": "holdtype/homebrew-tap",
                "HOMEBREW_EXPECTED_TAP": "holdtype/tap",
                "HOMEBREW_TAP_TOKEN": "token",
                "HOMEBREW_MINIMUM_MACOS": ">= :tahoe",
            }
        )

        self.assertEqual(len(absent_checks), 1)
        self.assertEqual(absent_checks[0].status, "warn")
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_TAP_REPOSITORY" and check.status == "fail"
                for check in required_absent_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "secret:HOMEBREW_TAP_TOKEN" and check.status == "fail"
                for check in required_absent_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "secret:HOMEBREW_TAP_TOKEN" and check.status == "fail"
                for check in partial_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_TAP_REPOSITORY" and check.status == "pass"
                for check in partial_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_EXPECTED_TAP" and check.status == "fail"
                for check in partial_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "homebrew:minimum-macos" and check.status == "fail"
                for check in partial_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_EXPECTED_TAP"
                and check.status == "fail"
                and "potapenko/homebrew-tap installs as potapenko/tap" in check.message
                for check in wrong_expected_tap_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "homebrew:minimum-macos" and check.status == "fail"
                for check in invalid_minimum_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_TAP_REPOSITORY:repository-name"
                and check.status == "fail"
                for check in invalid_repository_name_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_TAP_REPOSITORY:tap-name"
                and check.status == "pass"
                and check.message == "holdtype/tap"
                for check in configured_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_EXPECTED_TAP"
                and check.status == "pass"
                and check.message == "holdtype/tap"
                for check in configured_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "homebrew:minimum-macos" and check.status == "pass"
                for check in configured_checks
            )
        )

    def test_homebrew_template_preflight_requires_full_zap_metadata(self) -> None:
        module = load_preflight_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            template_path = root / "homebrew" / "Casks" / "holdtype.rb.template"
            template_path.parent.mkdir(parents=True)
            template_path.write_text(
                """
cask "holdtype" do
  version "{{VERSION}}"
  sha256 "{{SHA256}}"
  url "https://github.com/{{REPOSITORY}}/releases/download/v#{version}/HoldType-#{version}.dmg"
  auto_updates true
  app "HoldType.app"
  uninstall quit: "app.holdtype.HoldType"
  zap trash: [
    "~/Library/Caches/HoldType",
    "~/Library/Preferences/app.holdtype.HoldType.plist",
  ]
end
"""
            )

            checks = module.check_homebrew_template(root)

            self.assertTrue(
                any(
                    check.status == "fail"
                    and "Saved Application State" in check.message
                    for check in checks
                )
            )

    def test_official_homebrew_cask_bump_preflight_is_opt_in(self) -> None:
        module = load_preflight_module()
        original_which = module.shutil.which

        def fake_which(command: str) -> str | None:
            if command == "brew":
                return "/opt/homebrew/bin/brew"
            return original_which(command)

        module.shutil.which = fake_which
        try:
            absent_checks = module.check_official_homebrew_cask_bump_environment({})
            invalid_checks = module.check_official_homebrew_cask_bump_environment(
                {"HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED": "later"}
            )
            missing_token_checks = module.check_official_homebrew_cask_bump_environment(
                {"HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED": "true"}
            )
            configured_checks = module.check_official_homebrew_cask_bump_environment(
                {
                    "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED": "true",
                    "HOMEBREW_GITHUB_API_TOKEN": "token",
                    "HOMEBREW_OFFICIAL_CASK_FORK_ORG": "holdtype",
                }
            )
        finally:
            module.shutil.which = original_which

        self.assertEqual(absent_checks[0].status, "warn")
        self.assertTrue(
            any(
                check.name == "config:HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED"
                and check.status == "fail"
                for check in invalid_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "secret:HOMEBREW_GITHUB_API_TOKEN" and check.status == "fail"
                for check in missing_token_checks
            )
        )
        self.assertTrue(
            any(
                check.name == "secret:HOMEBREW_GITHUB_API_TOKEN" and check.status == "pass"
                for check in configured_checks
            )
        )

    def test_release_workflow_reuses_existing_homebrew_tap_pr(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("gh pr list", workflow)
        self.assertIn("scripts/release/preflight.py --require-secrets --require-homebrew-tap --json", workflow)
        self.assertIn("HOMEBREW_TAP_REPOSITORY: ${{ vars.HOMEBREW_TAP_REPOSITORY }}", workflow)
        self.assertIn("HOMEBREW_EXPECTED_TAP: ${{ vars.HOMEBREW_EXPECTED_TAP }}", workflow)
        self.assertIn("HOMEBREW_MINIMUM_MACOS: ${{ vars.HOMEBREW_MINIMUM_MACOS }}", workflow)
        self.assertIn("env.HOMEBREW_MINIMUM_MACOS != ''", workflow)
        self.assertIn("--minimum-macos \"$HOMEBREW_MINIMUM_MACOS\"", workflow)
        self.assertIn('tap_default_branch="$(', workflow)
        self.assertIn("--base \"$tap_default_branch\"", workflow)
        self.assertNotIn("--base main", workflow)
        self.assertIn("Homebrew tap pull request already exists", workflow)
        self.assertIn("gh pr create", workflow)

    def test_release_workflow_wraps_publish_and_tap_network_commands_with_timeouts(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        required_fragments = [
            "scripts/release/with_timeout.py 300 gh release view",
            "scripts/release/with_timeout.py 900 gh release upload",
            "scripts/release/with_timeout.py 300 gh release edit",
            "scripts/release/with_timeout.py 900 gh \"${release_create_args[@]}\"",
            "scripts/release/prune_github_release_assets.py",
            "--timeout 300",
            "scripts/release/with_timeout.py 300 \\\n            git clone",
            "scripts/release/with_timeout.py 300 gh repo view",
            "scripts/release/with_timeout.py 300 \\\n            git -C \"$tap_dir\" push",
            "scripts/release/with_timeout.py 300 gh pr list",
            "scripts/release/with_timeout.py 300 gh pr create",
        ]
        for fragment in required_fragments:
            self.assertIn(fragment, workflow)

    def test_release_workflow_validates_release_inputs(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Validate release inputs", workflow)
        self.assertIn("scripts/release/validate_release_inputs.py", workflow)
        self.assertIn('--version "${{ steps.release-inputs.outputs.version }}"', workflow)
        self.assertIn('--build "${{ steps.release-inputs.outputs.build }}"', workflow)
        self.assertIn('--tag "${{ steps.release-inputs.outputs.tag }}"', workflow)
        self.assertIn(
            '--download-url-prefix "${{ steps.release-inputs.outputs.download_url_prefix }}"',
            workflow,
        )

    def test_release_workflow_verifies_install_channels_with_minimum_macos(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Verify install channel metadata", workflow)
        self.assertIn("scripts/release/verify_install_channels.py", workflow)
        self.assertIn('--minimum-macos "$HOMEBREW_MINIMUM_MACOS"', workflow)

    def test_release_workflow_prunes_unexpected_release_assets_before_publish(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Prune unexpected GitHub Release assets", workflow)
        self.assertIn("GITHUB_TOKEN: ${{ github.token }}", workflow)
        self.assertIn("scripts/release/prune_github_release_assets.py", workflow)
        self.assertIn('--tag "${{ steps.release-inputs.outputs.tag }}"', workflow)
        self.assertIn("--apply", workflow)
        self.assertLess(
            workflow.index("Prune unexpected GitHub Release assets"),
            workflow.index("Publish GitHub Release assets"),
        )

    def test_release_workflow_verifies_published_release(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Verify published release", workflow)
        self.assertIn("scripts/release/verify_published_release.py", workflow)
        self.assertIn("--appcast-url \"$HOLDTYPE_UPDATE_FEED_URL\"", workflow)
        self.assertIn("--download-dmg", workflow)
        self.assertIn("--verify-downloaded-dmg-install", workflow)

    def test_release_workflow_uploads_official_homebrew_cask_submission_bundle(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Prepare official Homebrew cask submission bundle", workflow)
        self.assertIn("scripts/release/write_homebrew_cask_submission.py", workflow)
        self.assertIn("Upload official Homebrew cask submission bundle", workflow)
        self.assertIn("actions/upload-artifact@v4", workflow)
        self.assertIn(
            "holdtype-official-homebrew-cask-${{ steps.release-inputs.outputs.version }}",
            workflow,
        )

    def test_release_workflow_can_open_official_homebrew_cask_bump_pr_when_enabled(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Open official Homebrew Cask bump PR", workflow)
        self.assertIn(
            "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED: ${{ vars.HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED }}",
            workflow,
        )
        self.assertIn("HOMEBREW_GITHUB_API_TOKEN: ${{ secrets.HOMEBREW_GITHUB_API_TOKEN }}", workflow)
        self.assertIn("env.HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED == 'true'", workflow)
        self.assertIn("scripts/release/bump_official_homebrew_cask_pr.sh", workflow)
        self.assertIn("--timeout 900", workflow)

    def test_release_workflow_reuses_notes_for_appcast_and_github_release(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Write release notes", workflow)
        self.assertIn("scripts/release/write_release_notes.sh", workflow)
        self.assertIn("scripts/release/verify_release_notes.py", workflow)
        self.assertIn("--release-notes-file \"${{ steps.release-notes.outputs.path }}\"", workflow)
        self.assertIn("notes=\"${{ steps.release-notes.outputs.path }}\"", workflow)
        self.assertIn("gh release edit \"$TAG\"", workflow)
        self.assertIn("--draft=false", workflow)
        self.assertIn("--prerelease=false", workflow)

    def test_release_workflow_reuses_existing_appcast(self) -> None:
        workflow = RELEASE_WORKFLOW.read_text()

        self.assertIn("Fetch existing appcast", workflow)
        self.assertIn("scripts/release/fetch_existing_appcast.py", workflow)
        self.assertIn("--url \"$HOLDTYPE_UPDATE_FEED_URL\"", workflow)
        self.assertIn("--existing-appcast \"$EXISTING_APPCAST_PATH\"", workflow)

    def test_verify_release_workflow_accepts_current_workflow(self) -> None:
        result = subprocess.run(
            [str(VERIFY_RELEASE_WORKFLOW_SCRIPT), "--workflow", str(RELEASE_WORKFLOW)],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        self.assertIn("[pass] workflow-step:Validate release inputs", result.stdout)
        self.assertIn("[pass] workflow-step:Prune unexpected GitHub Release assets", result.stdout)
        self.assertIn("[pass] workflow-step:Verify published release", result.stdout)
        self.assertIn("[pass] workflow:script:prune-github-release-assets", result.stdout)
        self.assertIn("[pass] workflow:published-release:verify-downloaded-dmg-install", result.stdout)
        self.assertIn("[pass] workflow:script:update-homebrew-tap", result.stdout)
        self.assertIn("[pass] workflow-step:Open official Homebrew Cask bump PR", result.stdout)

    def test_verify_release_workflow_rejects_missing_and_reordered_steps(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            workflow_path = Path(temp_dir) / "release.yml"
            workflow_path.write_text(
                """
name: Release
on:
  push:
    tags:
      - "v*"
  workflow_dispatch:
permissions:
  contents: write
  pages: write
  id-token: write
jobs:
  release:
    runs-on: macos-26
    environment:
      name: github-pages
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Verify published release
        run: scripts/release/verify_published_release.py --download-dmg
      - name: Validate release inputs
        run: scripts/release/validate_release_inputs.py
"""
            )

            result = subprocess.run(
                [str(VERIFY_RELEASE_WORKFLOW_SCRIPT), "--workflow", str(workflow_path)],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] workflow-step:Resolve release inputs", result.stdout)
            self.assertIn("[fail] workflow-step:Verify published release", result.stdout)
            self.assertIn("[fail] workflow:script:preflight", result.stdout)

    def test_validate_release_inputs_accepts_workflow_values(self) -> None:
        result = subprocess.run(
            [
                str(VALIDATE_RELEASE_INPUTS_SCRIPT),
                "--version",
                "1.2.3",
                "--build",
                "100",
                "--tag",
                "v1.2.3",
                "--release-dir",
                "dist/release/v1.2.3",
                "--download-url-prefix",
                "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        self.assertIn("[pass] version: 1.2.3", result.stdout)
        self.assertIn("[pass] build: 100", result.stdout)
        self.assertIn("[pass] tag: v1.2.3", result.stdout)
        self.assertIn("[pass] download-url-prefix:path", result.stdout)

    def test_validate_release_inputs_rejects_mismatched_tag_and_bad_build(self) -> None:
        result = subprocess.run(
            [
                str(VALIDATE_RELEASE_INPUTS_SCRIPT),
                "--version",
                "v1.2.3",
                "--build",
                "abc",
                "--tag",
                "v1.2.4",
                "--release-dir",
                "dist/release/v1.2.4",
                "--download-url-prefix",
                "http://example.com/releases/download/v1.2.4",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] version: must not include a leading v", result.stdout)
        self.assertIn("[fail] build: must be a positive integer string", result.stdout)
        self.assertIn("[fail] tag: expected v1.2.3", result.stdout)
        self.assertIn("[fail] download-url-prefix:scheme", result.stdout)
        self.assertIn("[fail] download-url-prefix:trailing-slash", result.stdout)

    def test_write_release_notes_generates_default_notes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "release-notes.md"
            result = subprocess.run(
                [
                    str(WRITE_RELEASE_NOTES_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("release notes ready", result.stdout)
            text = output_path.read_text()
            self.assertIn("# HoldType 1.2.3", text)
            self.assertIn("signed and notarized macOS disk image", text)
            verify_result = subprocess.run(
                [
                    str(VERIFY_RELEASE_NOTES_SCRIPT),
                    "--notes-file",
                    str(output_path),
                    "--version",
                    "1.2.3",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            self.assertIn("[pass] release-notes:heading", verify_result.stdout)

    def test_write_release_notes_copies_curated_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            source_path = temp_path / "source.md"
            output_path = temp_path / "release-notes.md"
            source_path.write_text("# HoldType 1.2.3\n\n- Fixed release metadata.\n")

            subprocess.run(
                [
                    str(WRITE_RELEASE_NOTES_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--source",
                    str(source_path),
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertEqual(output_path.read_text(), source_path.read_text())

    def test_write_release_notes_rejects_placeholder_source(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            source_path = temp_path / "source.md"
            output_path = temp_path / "release-notes.md"
            source_path.write_text("# HoldType 1.2.3\n\nTODO: fill this in.\n")

            result = subprocess.run(
                [
                    str(WRITE_RELEASE_NOTES_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--source",
                    str(source_path),
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] release-notes:placeholders", result.stdout)

    def test_fetch_existing_appcast_downloads_when_available(self) -> None:
        appcast_bytes = b"<?xml version='1.0'?><rss />\n"

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                if self.path != "/appcast.xml":
                    self.send_response(404)
                    self.end_headers()
                    return
                self.send_response(200)
                self.send_header("Content-Type", "application/xml")
                self.send_header("Content-Length", str(len(appcast_bytes)))
                self.end_headers()
                self.wfile.write(appcast_bytes)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                output_path = Path(temp_dir) / "existing-appcast.xml"
                result = subprocess.run(
                    [
                        str(FETCH_EXISTING_APPCAST_SCRIPT),
                        "--url",
                        f"http://127.0.0.1:{server.server_port}/appcast.xml",
                        "--output",
                        str(output_path),
                        "--timeout",
                        "5",
                    ],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=True,
                )
                self.assertIn("existing appcast ready", result.stdout)
                self.assertEqual(output_path.read_bytes(), appcast_bytes)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_fetch_existing_appcast_treats_missing_as_nonfatal(self) -> None:
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                self.send_response(404)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                output_path = Path(temp_dir) / "existing-appcast.xml"
                result = subprocess.run(
                    [
                        str(FETCH_EXISTING_APPCAST_SCRIPT),
                        "--url",
                        f"http://127.0.0.1:{server.server_port}/missing.xml",
                        "--output",
                        str(output_path),
                        "--timeout",
                        "5",
                    ],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=True,
                )
                self.assertIn("existing appcast not found", result.stderr)
                self.assertFalse(output_path.exists())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_fetch_existing_appcast_fails_on_server_error(self) -> None:
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                self.send_response(500)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                output_path = Path(temp_dir) / "existing-appcast.xml"
                result = subprocess.run(
                    [
                        str(FETCH_EXISTING_APPCAST_SCRIPT),
                        "--url",
                        f"http://127.0.0.1:{server.server_port}/appcast.xml",
                        "--output",
                        str(output_path),
                        "--timeout",
                        "5",
                    ],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=False,
                )
                self.assertEqual(result.returncode, 1)
                self.assertIn("could not fetch existing appcast: HTTP 500", result.stderr)
                self.assertFalse(output_path.exists())
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

    def test_generate_appcast_uses_manifest_dmg_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            release_root = temp_path / "release"
            release_dir = release_root / "v1.2.3"
            release_dir.mkdir(parents=True)
            (release_dir / "HoldType-1.2.3.dmg").write_bytes(b"current dmg")
            (release_dir / "HoldType-9.9.9.dmg").write_bytes(b"stale dmg")
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {
                            "path": "HoldType-1.2.3.dmg",
                            "sha256": "0" * 64,
                        },
                    }
                )
            )
            ed_key_path = temp_path / "sparkle_ed25519_key"
            ed_key_path.write_text("fake-key")
            record_path = temp_path / "archives.txt"
            fake_generate_appcast = temp_path / "generate_appcast"
            fake_generate_appcast.write_text(
                """#!/usr/bin/env bash
set -euo pipefail
out=""
archive_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o)
      out="$2"
      shift 2
      ;;
    --ed-key-file|--download-url-prefix)
      shift 2
      ;;
    *)
      archive_dir="$1"
      shift
      ;;
  esac
done
find "$archive_dir" -maxdepth 1 -type f -exec basename {} \\; | sort > "$RECORD_PATH"
printf '<rss />\\n' > "$out"
"""
            )
            fake_generate_appcast.chmod(0o755)

            result = subprocess.run(
                [
                    str(GENERATE_APPCAST_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--download-url-prefix",
                    "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/",
                    "--ed-key-file",
                    str(ed_key_path),
                ],
                cwd=ROOT,
                env={
                    **os.environ,
                    "RELEASE_ROOT": str(release_root),
                    "SPARKLE_GENERATE_APPCAST_PATH": str(fake_generate_appcast),
                    "RECORD_PATH": str(record_path),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("appcast ready", result.stdout)
            self.assertEqual((release_dir / "appcast.xml").read_text(), "<rss />\n")
            archived_names = record_path.read_text().splitlines()
            self.assertIn("HoldType-1.2.3.dmg", archived_names)
            self.assertNotIn("HoldType-9.9.9.dmg", archived_names)

    def test_render_homebrew_cask_template(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            result = subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("rendered Homebrew cask", result.stdout)
            rendered = output_path.read_text()
            self.assertIn('version "1.2.3"', rendered)
            self.assertIn(
                'sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"',
                rendered,
            )
            self.assertIn(
                "https://github.com/holdtype/holdtype-swift/releases/download/v#{version}/HoldType-#{version}.dmg",
                rendered,
            )
            self.assertIn('depends_on macos: ">= :tahoe"', rendered)
            self.assertIn('app "HoldType.app"', rendered)
            self.assertIn('uninstall quit: "app.holdtype.HoldType"', rendered)
            self.assertIn('"~/Library/Caches/HoldType"', rendered)
            self.assertIn('"~/Library/Preferences/app.holdtype.HoldType.plist"', rendered)
            self.assertIn('"~/Library/Saved Application State/app.holdtype.HoldType.savedState"', rendered)

    def test_render_homebrew_cask_rejects_invalid_minimum_macos(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            result = subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    "tahoe",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("minimum macOS must be a Homebrew comparison expression", result.stderr)

    def test_render_homebrew_cask_rejects_malformed_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            result = subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "--repository",
                    "potapenko/holdtype/swift",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("--repository must be OWNER/REPO", result.stderr)
            self.assertFalse(output_path.exists())

    def test_render_homebrew_cask_rejects_malformed_version(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            result = subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1/2/3",
                    "--sha256",
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("version must be a numeric public version", result.stderr)
            self.assertFalse(output_path.exists())

    def test_verify_homebrew_cask_accepts_rendered_official_candidate(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "h" / "holdtype.rb"
            sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
            subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    sha256,
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(VERIFY_HOMEBREW_CASK_SCRIPT),
                    "--cask-path",
                    str(output_path),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    sha256,
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--official-layout",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("[pass] homebrew-cask:official-layout", result.stdout)
            self.assertIn("[pass] homebrew-cask:url", result.stdout)
            self.assertIn("[pass] homebrew-cask:livecheck-strategy", result.stdout)
            self.assertIn("[pass] homebrew-cask:minimum-macos", result.stdout)
            self.assertIn("[pass] homebrew-cask:uninstall-quit", result.stdout)
            self.assertIn("[pass] homebrew-cask:zap-caches", result.stdout)

    def test_verify_homebrew_tap_release_accepts_published_cask(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        sha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    sha256,
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output",
                    str(output_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            cask_text = output_path.read_text()

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/homebrew-tap"] = (
                json.dumps(
                    {
                        "full_name": "holdtype/homebrew-tap",
                        "private": False,
                        "archived": False,
                        "default_branch": "main",
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/homebrew-tap/contents/Casks/holdtype.rb?ref=main"] = (
                json.dumps(
                    {
                        "path": "Casks/holdtype.rb",
                        "type": "file",
                        "encoding": "base64",
                        "content": base64.b64encode(cask_text.encode("utf-8")).decode("ascii"),
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_HOMEBREW_TAP_RELEASE_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--tap-repository",
                    "holdtype/homebrew-tap",
                    "--expected-homebrew-tap",
                    "holdtype/tap",
                    "--version",
                    "1.2.3",
                    "--sha256",
                    sha256,
                    "--minimum-macos",
                    ">= :tahoe",
                    "--github-api-url",
                    base_url,
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertIn("[pass] homebrew-tap:expected-prefix: holdtype/tap", result.stdout)
        self.assertIn(
            "[pass] homebrew-tap:install-command: brew install --cask holdtype/tap/holdtype",
            result.stdout,
        )
        self.assertIn("[pass] github-tap-repository:visibility", result.stdout)
        self.assertIn("[pass] github-tap-cask:content", result.stdout)
        self.assertIn("[pass] homebrew-cask:version", result.stdout)
        self.assertIn("[pass] homebrew-cask:sha256", result.stdout)
        self.assertIn("[pass] homebrew-cask:minimum-macos", result.stdout)

    def test_verify_homebrew_tap_release_rejects_unexpected_tap_prefix_before_api(self) -> None:
        result = subprocess.run(
            [
                str(VERIFY_HOMEBREW_TAP_RELEASE_SCRIPT),
                "--repository",
                "holdtype/holdtype-swift",
                "--tap-repository",
                "potapenko/homebrew-tap",
                "--expected-homebrew-tap",
                "holdtype/tap",
                "--version",
                "1.2.3",
                "--sha256",
                "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                "--minimum-macos",
                ">= :tahoe",
                "--github-api-url",
                "http://127.0.0.1:9",
                "--timeout",
                "1",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] homebrew-tap:expected-prefix", result.stdout)
        self.assertIn("potapenko/homebrew-tap installs as potapenko/tap", result.stdout)
        self.assertNotIn("github-api", result.stdout)

    def test_verify_homebrew_cask_rejects_malformed_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            output_path.parent.mkdir(parents=True)
            output_path.write_text(
                """
cask "holdtype" do
  version "1.2.3"
  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  url "https://github.com/holdtype/holdtype-swift/releases/download/v#{version}/HoldType-#{version}.dmg"
  app "HoldType.app"
end
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_HOMEBREW_CASK_SCRIPT),
                    "--cask-path",
                    str(output_path),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "--repository",
                    "potapenko/holdtype/swift",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] repository", result.stdout)
            self.assertIn("expected OWNER/REPO", result.stdout)

    def test_verify_homebrew_cask_rejects_wrong_layout_and_latest_cask(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            output_path = Path(temp_dir) / "Casks" / "holdtype.rb"
            output_path.parent.mkdir(parents=True)
            output_path.write_text(
                """
cask "holdtype" do
  version :latest
  sha256 :no_check
  url "https://example.com/HoldType.dmg"
  app "HoldType.app"
end
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_HOMEBREW_CASK_SCRIPT),
                    "--cask-path",
                    str(output_path),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--official-layout",
                    "--require-minimum-macos",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] homebrew-cask:official-layout", result.stdout)
            self.assertIn("[fail] homebrew-cask:version", result.stdout)
            self.assertIn("[fail] homebrew-cask:forbid-latest", result.stdout)
            self.assertIn("[fail] homebrew-cask:forbid-no-check", result.stdout)
            self.assertIn("[fail] homebrew-cask:minimum-macos", result.stdout)

    def test_update_homebrew_tap_renders_cask_in_tap_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            tap_dir = Path(temp_dir) / "homebrew-tap"
            tap_dir.mkdir()
            result = subprocess.run(
                [
                    str(UPDATE_TAP_SCRIPT),
                    "--tap-dir",
                    str(tap_dir),
                    "--version",
                    "2.0.0",
                    "--sha256",
                    "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--tap-repository",
                    "holdtype/homebrew-tap",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            output_path = tap_dir / "Casks" / "holdtype.rb"
            self.assertIn("updated Homebrew tap cask", result.stdout)
            rendered = output_path.read_text()
            self.assertIn('version "2.0.0"', rendered)
            self.assertIn(
                'sha256 "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"',
                rendered,
            )
            self.assertIn(
                "https://github.com/holdtype/holdtype-swift/releases/download/v#{version}/HoldType-#{version}.dmg",
                rendered,
            )
            self.assertIn('depends_on macos: ">= :tahoe"', rendered)
            self.assertIn('uninstall quit: "app.holdtype.HoldType"', rendered)
            self.assertIn('"~/Library/Caches/HoldType"', rendered)

    def test_update_homebrew_tap_requires_homebrew_prefixed_tap_repository_for_audit(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            tap_dir = Path(temp_dir) / "homebrew-tap"
            tap_dir.mkdir()
            fake_brew = Path(temp_dir) / "brew"
            fake_brew.write_text("#!/usr/bin/env bash\nexit 0\n")
            fake_brew.chmod(0o755)

            result = subprocess.run(
                [
                    str(UPDATE_TAP_SCRIPT),
                    "--tap-dir",
                    str(tap_dir),
                    "--version",
                    "2.0.0",
                    "--sha256",
                    "ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--tap-repository",
                    "holdtype/tap",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--audit",
                    "--brew",
                    str(fake_brew),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("tap repository name must start with homebrew-", result.stderr)
            self.assertNotIn("auditing Homebrew cask through tap", result.stdout)

    def test_prepare_official_homebrew_cask_uses_official_cask_layout(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            homebrew_cask_dir = Path(temp_dir) / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            result = subprocess.run(
                [
                    str(PREPARE_OFFICIAL_CASK_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "3.0.0",
                    "--sha256",
                    "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            output_path = homebrew_cask_dir / "Casks" / "h" / "holdtype.rb"
            self.assertIn("official Homebrew Cask candidate ready", result.stdout)
            rendered = output_path.read_text()
            self.assertIn('cask "holdtype" do', rendered)
            self.assertIn('version "3.0.0"', rendered)
            self.assertIn(
                'sha256 "fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"',
                rendered,
            )
            self.assertIn('depends_on macos: ">= :tahoe"', rendered)
            self.assertIn('uninstall quit: "app.holdtype.HoldType"', rendered)
            self.assertIn('"~/Library/Preferences/app.holdtype.HoldType.plist"', rendered)

    def test_prepare_official_homebrew_cask_requires_minimum_macos(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            homebrew_cask_dir = Path(temp_dir) / "homebrew-cask"
            homebrew_cask_dir.mkdir()

            missing = subprocess.run(
                [
                    str(PREPARE_OFFICIAL_CASK_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "3.0.0",
                    "--sha256",
                    "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210",
                    "--repository",
                    "holdtype/holdtype-swift",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            invalid = subprocess.run(
                [
                    str(PREPARE_OFFICIAL_CASK_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "3.0.0",
                    "--sha256",
                    "FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    "tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(missing.returncode, 1)
            self.assertIn("missing --minimum-macos", missing.stderr)
            self.assertEqual(invalid.returncode, 1)
            self.assertIn("minimum macOS must be a Homebrew comparison expression", invalid.stderr)

    def test_write_homebrew_cask_submission_bundle_uses_public_release_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "dist" / "release" / "v1.2.3"
            release_dir.mkdir(parents=True)
            output_dir = Path(temp_dir) / "homebrew-official-cask"
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"release dmg bytes")
            zip_path.write_bytes(b"release zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": dmg_path.name, "sha256": dmg_sha},
                        "zip": {"path": zip_path.name, "sha256": zip_sha},
                    }
                )
            )

            result = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            cask_path = output_dir / "Casks" / "h" / "holdtype.rb"
            metadata = json.loads((output_dir / "metadata.json").read_text())
            submission = (output_dir / "SUBMISSION.md").read_text()
            rendered = cask_path.read_text()

            self.assertIn("[pass] homebrew-cask-submission:bundle", result.stdout)
            self.assertIn('version "1.2.3"', rendered)
            self.assertIn(f'sha256 "{dmg_sha}"', rendered)
            self.assertIn('depends_on macos: ">= :tahoe"', rendered)
            self.assertIn('uninstall quit: "app.holdtype.HoldType"', rendered)
            self.assertIn('"~/Library/Saved Application State/app.holdtype.HoldType.savedState"', rendered)
            self.assertEqual(metadata["cask_path"], "Casks/h/holdtype.rb")
            self.assertEqual(metadata["dmg_sha256"], dmg_sha)
            self.assertIn("brew install --cask holdtype", submission)
            self.assertIn("brew uninstall --cask holdtype", submission)
            self.assertIn("scripts/release/open_official_homebrew_cask_pr_from_bundle.sh", submission)
            self.assertIn("--bundle-dir /path/to/holdtype-official-homebrew-cask-1.2.3", submission)
            self.assertIn("brew style --fix holdtype", submission)
            self.assertIn("brew audit --new --cask holdtype", submission)
            self.assertIn("export HOMEBREW_NO_INSTALL_FROM_API=1", submission)
            self.assertNotIn("brew lgtm --online", submission)
            self.assertIn("--minimum-macos \">= :tahoe\"", submission)

    def test_write_homebrew_cask_submission_rejects_malformed_repository(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            result = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(Path(temp_dir) / "dist" / "release" / "v1.2.3"),
                    "--repository",
                    "potapenko/holdtype/swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output-dir",
                    str(Path(temp_dir) / "homebrew-official-cask"),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("--repository must be OWNER/REPO", result.stderr)

    def test_write_homebrew_cask_submission_bundle_rejects_nonportable_manifest_path(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "dist" / "release" / "v1.2.3"
            release_dir.mkdir(parents=True)
            output_dir = Path(temp_dir) / "homebrew-official-cask"
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"release dmg bytes")
            zip_path.write_bytes(b"release zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": str(dmg_path), "sha256": dmg_sha},
                        "zip": {"path": zip_path.name, "sha256": zip_sha},
                    }
                )
            )

            result = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("manifest dmg.path must be artifact filename", result.stderr)

    def test_write_homebrew_cask_submission_bundle_requires_public_release_and_minimum_macos(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "dist" / "preview" / "v1.2.3"
            release_dir.mkdir(parents=True)
            output_dir = Path(temp_dir) / "homebrew-official-cask"
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            dmg_path.write_bytes(b"preview dmg bytes")
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "local-preview",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": False,
                        "public_release": False,
                        "dmg": {
                            "path": str(dmg_path),
                            "sha256": hashlib.sha256(dmg_path.read_bytes()).hexdigest(),
                        },
                    }
                )
            )

            missing_minimum = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            preview_manifest = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            invalid_minimum = subprocess.run(
                [
                    str(WRITE_HOMEBREW_CASK_SUBMISSION_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    "tahoe",
                    "--output-dir",
                    str(output_dir),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(missing_minimum.returncode, 1)
            self.assertIn("missing --minimum-macos", missing_minimum.stderr)
            self.assertEqual(invalid_minimum.returncode, 1)
            self.assertIn("minimum macOS must be a Homebrew comparison expression", invalid_minimum.stderr)
            self.assertEqual(preview_manifest.returncode, 1)
            self.assertIn("manifest kind must be public-release", preview_manifest.stderr)

    def test_open_official_homebrew_cask_pr_from_bundle_uses_metadata_and_taps_checkout(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            bundle_dir = temp_path / "holdtype-official-homebrew-cask-1.2.3"
            bundle_cask = bundle_dir / "Casks" / "h" / "holdtype.rb"
            bundle_cask.parent.mkdir(parents=True)
            dmg_sha = "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD"
            subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    dmg_sha,
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output",
                    str(bundle_cask),
                ],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
            )
            (bundle_dir / "metadata.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "cask_path": "Casks/h/holdtype.rb",
                        "cask_token": "holdtype",
                        "dmg_sha256": dmg_sha,
                        "dmg_url": "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/HoldType-1.2.3.dmg",
                        "minimum_macos": ">= :tahoe",
                        "repository": "holdtype/holdtype-swift",
                        "tag": "v1.2.3",
                        "version": "1.2.3",
                    }
                )
            )

            homebrew_cask_dir = temp_path / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            subprocess.run(
                ["git", "init"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "HoldType Test"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.email", "holdtype@example.invalid"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            (homebrew_cask_dir / "README.md").write_text("homebrew-cask test\n")
            subprocess.run(["git", "add", "README.md"], cwd=homebrew_cask_dir, check=True)
            subprocess.run(
                ["git", "commit", "-m", "Initial homebrew-cask checkout"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            brew_log = temp_path / "brew.log"
            fake_brew = temp_path / "brew"
            fake_brew.write_text(
                "#!/usr/bin/env bash\n"
                "printf '%s\\n' \"$*\" >> \"$BREW_LOG\"\n"
                "if [ \"$1\" = \"tap\" ] && [ \"$2\" = \"--force\" ] && [ \"$3\" = \"homebrew/cask\" ]; then\n"
                "  exit 0\n"
                "fi\n"
                "if [ \"$1\" = \"--repository\" ] && [ \"$2\" = \"homebrew/cask\" ]; then\n"
                "  printf '%s\\n' \"$HOMEBREW_CASK_DIR_FOR_TEST\"\n"
                "  exit 0\n"
                "fi\n"
                "exit 2\n"
            )
            fake_brew.chmod(0o755)

            result = subprocess.run(
                [
                    str(OPEN_OFFICIAL_CASK_FROM_BUNDLE_SCRIPT),
                    "--bundle-dir",
                    str(bundle_dir),
                    "--brew",
                    str(fake_brew),
                    "--branch",
                    "holdtype-1.2.3-test",
                ],
                cwd=ROOT,
                env={
                    **os.environ,
                    "BREW_LOG": str(brew_log),
                    "HOMEBREW_CASK_DIR_FOR_TEST": str(homebrew_cask_dir),
                },
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()
            subject = subprocess.check_output(
                ["git", "log", "-1", "--pretty=%s"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()
            rendered = (homebrew_cask_dir / "Casks" / "h" / "holdtype.rb").read_text()

            self.assertIn("ensuring official Homebrew Cask tap checkout", result.stdout)
            self.assertIn("official Homebrew Cask PR branch ready", result.stdout)
            self.assertEqual(branch, "holdtype-1.2.3-test")
            self.assertEqual(subject, "holdtype 1.2.3 (new cask)")
            self.assertIn('version "1.2.3"', rendered)
            self.assertIn(
                'sha256 "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd"',
                rendered,
            )
            self.assertIn('depends_on macos: ">= :tahoe"', rendered)
            self.assertIn("tap --force homebrew/cask", brew_log.read_text())
            self.assertIn("--repository homebrew/cask", brew_log.read_text())

    def test_open_official_homebrew_cask_pr_from_bundle_rejects_stale_metadata_before_brew(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            bundle_dir = temp_path / "holdtype-official-homebrew-cask-1.2.3"
            bundle_cask = bundle_dir / "Casks" / "h" / "holdtype.rb"
            bundle_cask.parent.mkdir(parents=True)
            subprocess.run(
                [
                    str(RENDER_CASK_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--sha256",
                    "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--output",
                    str(bundle_cask),
                ],
                cwd=ROOT,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                check=True,
            )
            (bundle_dir / "metadata.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "cask_path": "Casks/h/holdtype.rb",
                        "cask_token": "holdtype",
                        "dmg_sha256": "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
                        "dmg_url": "https://github.com/example/wrong/releases/download/v1.2.3/HoldType-1.2.3.dmg",
                        "minimum_macos": ">= :tahoe",
                        "repository": "holdtype/holdtype-swift",
                        "tag": "v1.2.3",
                        "version": "1.2.3",
                    }
                )
            )
            brew_log = temp_path / "brew.log"
            fake_brew = temp_path / "brew"
            fake_brew.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$BREW_LOG\"\n")
            fake_brew.chmod(0o755)

            result = subprocess.run(
                [
                    str(OPEN_OFFICIAL_CASK_FROM_BUNDLE_SCRIPT),
                    "--bundle-dir",
                    str(bundle_dir),
                    "--brew",
                    str(fake_brew),
                ],
                cwd=ROOT,
                env={**os.environ, "BREW_LOG": str(brew_log)},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("metadata.dmg_url must be", result.stderr)
            self.assertFalse(brew_log.exists())

    def test_open_official_homebrew_cask_pr_from_bundle_rejects_stale_bundle_cask_before_brew(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            bundle_dir = temp_path / "holdtype-official-homebrew-cask-1.2.3"
            bundle_cask = bundle_dir / "Casks" / "h" / "holdtype.rb"
            bundle_cask.parent.mkdir(parents=True)
            bundle_cask.write_text('cask "other-app" do\nend\n')
            (bundle_dir / "metadata.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "cask_path": "Casks/h/holdtype.rb",
                        "cask_token": "holdtype",
                        "dmg_sha256": "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
                        "dmg_url": "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/HoldType-1.2.3.dmg",
                        "minimum_macos": ">= :tahoe",
                        "repository": "holdtype/holdtype-swift",
                        "tag": "v1.2.3",
                        "version": "1.2.3",
                    }
                )
            )
            brew_log = temp_path / "brew.log"
            fake_brew = temp_path / "brew"
            fake_brew.write_text("#!/usr/bin/env bash\nprintf '%s\\n' \"$*\" >> \"$BREW_LOG\"\n")
            fake_brew.chmod(0o755)

            result = subprocess.run(
                [
                    str(OPEN_OFFICIAL_CASK_FROM_BUNDLE_SCRIPT),
                    "--bundle-dir",
                    str(bundle_dir),
                    "--brew",
                    str(fake_brew),
                ],
                cwd=ROOT,
                env={**os.environ, "BREW_LOG": str(brew_log)},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] homebrew-cask:token", result.stderr)
            self.assertFalse(brew_log.exists())

    def test_create_official_homebrew_cask_pr_creates_branch_and_commit(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            homebrew_cask_dir = Path(temp_dir) / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            subprocess.run(
                ["git", "init"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "HoldType Test"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.email", "holdtype@example.invalid"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            (homebrew_cask_dir / "README.md").write_text("homebrew-cask test\n")
            subprocess.run(["git", "add", "README.md"], cwd=homebrew_cask_dir, check=True)
            subprocess.run(
                ["git", "commit", "-m", "Initial homebrew-cask checkout"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(CREATE_OFFICIAL_CASK_PR_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "4.0.0",
                    "--sha256",
                    "1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--branch",
                    "holdtype-4.0.0-test",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()
            subject = subprocess.check_output(
                ["git", "log", "-1", "--pretty=%s"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()
            status = subprocess.check_output(
                ["git", "status", "--porcelain"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()

            self.assertEqual(branch, "holdtype-4.0.0-test")
            self.assertEqual(subject, "holdtype 4.0.0 (new cask)")
            self.assertEqual(status, "")
            self.assertIn("official Homebrew Cask PR branch ready", result.stdout)
            rendered = (homebrew_cask_dir / "Casks" / "h" / "holdtype.rb").read_text()
            self.assertIn('version "4.0.0"', rendered)
            self.assertIn(
                'sha256 "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef"',
                rendered,
            )

    def test_create_official_homebrew_cask_pr_requires_minimum_macos_before_checkout_changes(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            homebrew_cask_dir = Path(temp_dir) / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            subprocess.run(
                ["git", "init"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(CREATE_OFFICIAL_CASK_PR_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "4.0.0",
                    "--sha256",
                    "1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--branch",
                    "holdtype-4.0.0-test",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("missing --minimum-macos", result.stderr)
            self.assertFalse((homebrew_cask_dir / "Casks").exists())

    def test_create_official_homebrew_cask_pr_rejects_existing_official_cask_on_base(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            homebrew_cask_dir = Path(temp_dir) / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            subprocess.run(
                ["git", "init", "-b", "main"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "HoldType Test"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.email", "holdtype@example.invalid"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            existing_cask = homebrew_cask_dir / "Casks" / "h" / "holdtype.rb"
            existing_cask.parent.mkdir(parents=True)
            existing_cask.write_text('cask "holdtype" do\nend\n')
            subprocess.run(["git", "add", "Casks/h/holdtype.rb"], cwd=homebrew_cask_dir, check=True)
            subprocess.run(
                ["git", "commit", "-m", "Add existing holdtype cask"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(CREATE_OFFICIAL_CASK_PR_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "4.0.0",
                    "--sha256",
                    "1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--branch",
                    "holdtype-4.0.0-test",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()

            self.assertEqual(result.returncode, 1)
            self.assertIn("official Homebrew Cask already exists on main", result.stderr)
            self.assertIn("use bump_official_homebrew_cask_pr.sh", result.stderr)
            self.assertEqual(branch, "main")

    def test_create_official_homebrew_cask_pr_reverifies_after_style(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            homebrew_cask_dir = temp_path / "homebrew-cask"
            homebrew_cask_dir.mkdir()
            fake_brew = temp_path / "brew"
            fake_brew.write_text(
                "#!/usr/bin/env bash\n"
                "if [ \"$1\" = \"style\" ]; then\n"
                "  python3 - <<'PY'\n"
                "from pathlib import Path\n"
                "path = Path('Casks/h/holdtype.rb')\n"
                "text = path.read_text()\n"
                "text = text.replace('  uninstall quit: \"app.holdtype.HoldType\"\\n\\n', '')\n"
                "path.write_text(text)\n"
                "PY\n"
                "fi\n"
            )
            fake_brew.chmod(0o755)
            subprocess.run(
                ["git", "init"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "HoldType Test"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            subprocess.run(
                ["git", "config", "user.email", "holdtype@example.invalid"],
                cwd=homebrew_cask_dir,
                check=True,
            )
            (homebrew_cask_dir / "README.md").write_text("homebrew-cask test\n")
            subprocess.run(["git", "add", "README.md"], cwd=homebrew_cask_dir, check=True)
            subprocess.run(
                ["git", "commit", "-m", "Initial homebrew-cask checkout"],
                cwd=homebrew_cask_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(CREATE_OFFICIAL_CASK_PR_SCRIPT),
                    "--homebrew-cask-dir",
                    str(homebrew_cask_dir),
                    "--version",
                    "4.0.0",
                    "--sha256",
                    "1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                    "--branch",
                    "holdtype-4.0.0-test",
                    "--style",
                    "--brew",
                    str(fake_brew),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            subject = subprocess.check_output(
                ["git", "log", "-1", "--pretty=%s"],
                cwd=homebrew_cask_dir,
                text=True,
            ).strip()

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] homebrew-cask:uninstall-quit", result.stderr)
            self.assertEqual(subject, "Initial homebrew-cask checkout")

    def test_bump_official_homebrew_cask_pr_delegates_to_brew_bump_cask_pr(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            args_path = temp_path / "brew-args.txt"
            fake_brew = temp_path / "brew"
            fake_brew.write_text(
                "#!/usr/bin/env bash\n"
                "printf '__call__\\n' >> \"$BREW_ARGS_PATH\"\n"
                "printf '%s\\n' \"$@\" >> \"$BREW_ARGS_PATH\"\n"
            )
            fake_brew.chmod(0o755)

            result = subprocess.run(
                [
                    str(BUMP_OFFICIAL_CASK_PR_SCRIPT),
                    "--version",
                    "4.1.0",
                    "--sha256",
                    "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--dry-run",
                    "--no-audit",
                    "--no-style",
                    "--fork-org",
                    "potapenko",
                    "--brew",
                    str(fake_brew),
                    "--timeout",
                    "30",
                ],
                cwd=ROOT,
                env={**os.environ, "BREW_ARGS_PATH": str(args_path)},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            calls = [
                call.splitlines()
                for call in args_path.read_text().strip().split("__call__\n")
                if call.strip()
            ]
            tap_args = calls[0]
            args = calls[1]
            self.assertIn("opening official Homebrew Cask bump PR", result.stdout)
            self.assertEqual(tap_args, ["tap", "--force", "homebrew/cask"])
            self.assertEqual(args[0], "bump-cask-pr")
            self.assertIn("--version", args)
            self.assertIn("4.1.0", args)
            self.assertIn("--sha256", args)
            self.assertIn(
                "abcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcdefabcd",
                args,
            )
            self.assertIn(
                "https://github.com/holdtype/holdtype-swift/releases/download/v4.1.0/HoldType-4.1.0.dmg",
                args,
            )
            self.assertIn("--dry-run", args)
            self.assertIn("--no-audit", args)
            self.assertIn("--no-style", args)
            self.assertIn("--fork-org", args)
            self.assertIn("potapenko", args)
            self.assertEqual(args[-1], "holdtype")

    def test_bump_official_homebrew_cask_pr_rejects_invalid_url_before_brew(self) -> None:
        result = subprocess.run(
            [
                str(BUMP_OFFICIAL_CASK_PR_SCRIPT),
                "--version",
                "4.1.0",
                "--sha256",
                "ABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCDEFabcdefABCD",
                "--repository",
                "holdtype/holdtype-swift",
                "--url",
                "http://github.com/holdtype/holdtype-swift/releases/download/v4.1.0/HoldType-4.1.0.dmg",
                "--brew",
                "/missing/brew",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("--url must use https", result.stderr)
        self.assertNotIn("missing required command", result.stderr)

    def test_verify_release_manifest_accepts_public_release_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "dist" / "release" / "v1.2.3"
            release_dir.mkdir(parents=True)
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"release dmg bytes")
            zip_path.write_bytes(b"release zip bytes")
            manifest_path = release_dir / "release-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {
                            "path": dmg_path.name,
                            "sha256": hashlib.sha256(dmg_path.read_bytes()).hexdigest(),
                        },
                        "zip": {
                            "path": zip_path.name,
                            "sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
                        },
                    }
                )
            )

            result = subprocess.run(
                [
                    str(VERIFY_RELEASE_MANIFEST_SCRIPT),
                    "--manifest",
                    str(manifest_path),
                    "--artifact-root",
                    str(release_dir),
                    "--expect-kind",
                    "public-release",
                    "--expect-public-release",
                    "true",
                    "--expect-notarized",
                    "true",
                    "--require-relative-artifact-paths",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("[pass] manifest:kind: public-release", result.stdout)
            self.assertIn("[pass] manifest:public_release: true", result.stdout)
            self.assertIn("[pass] manifest:dmg.path: HoldType-1.2.3.dmg", result.stdout)
            self.assertIn("[pass] manifest:dmg.sha256", result.stdout)
            self.assertIn("[pass] manifest:zip.sha256", result.stdout)

    def test_verify_release_manifest_rejects_absolute_paths_when_required(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "dist" / "release" / "v1.2.3"
            release_dir.mkdir(parents=True)
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"release dmg bytes")
            zip_path.write_bytes(b"release zip bytes")
            manifest_path = release_dir / "release-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {
                            "path": str(dmg_path),
                            "sha256": hashlib.sha256(dmg_path.read_bytes()).hexdigest(),
                        },
                        "zip": {
                            "path": str(zip_path),
                            "sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
                        },
                    }
                )
            )

            result = subprocess.run(
                [
                    str(VERIFY_RELEASE_MANIFEST_SCRIPT),
                    "--manifest",
                    str(manifest_path),
                    "--artifact-root",
                    str(release_dir),
                    "--expect-kind",
                    "public-release",
                    "--expect-public-release",
                    "true",
                    "--expect-notarized",
                    "true",
                    "--require-relative-artifact-paths",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] manifest:dmg.path", result.stdout)
            self.assertIn("must be relative for portable release metadata", result.stdout)

    def test_build_artifact_manifests_use_relative_paths(self) -> None:
        release_script = BUILD_RELEASE_SCRIPT.read_text()
        preview_script = (ROOT / "scripts" / "release" / "build_preview_dmg.sh").read_text()
        verify_script = (ROOT / "scripts" / "release" / "verify_release.sh").read_text()

        for script in (release_script, preview_script):
            self.assertIn('shasum -a 256 "$DMG_FILE" "$APP_ZIP_FILE"', script)
            self.assertIn('"path": "$DMG_FILE"', script)
            self.assertIn('"path": "$APP_ZIP_FILE"', script)
            self.assertIn("--require-relative-artifact-paths", script)
            self.assertIn('validate_build_number "$BUILD_NUMBER"', script)
        self.assertIn("--require-relative-artifact-paths", verify_script)
        self.assertIn('DMG_PATH="$RELEASE_DIR/$DMG_FILE"', verify_script)
        self.assertNotIn('find "$RELEASE_DIR" -maxdepth 1 -name "$APP_NAME-*.dmg"', verify_script)
        self.assertIn('ARTIFACT_KIND="public-release"', release_script)
        self.assertIn('ARTIFACT_KIND="notarization-skipped-release"', release_script)
        self.assertIn('"kind": "$ARTIFACT_KIND"', release_script)
        self.assertIn('--expect-kind "$ARTIFACT_KIND"', release_script)
        self.assertIn('RELEASE_CODE_SIGN_IDENTITY="${HOLDTYPE_CODE_SIGN_IDENTITY:-Developer ID Application}"', release_script)
        self.assertIn('codesign \\', release_script)
        self.assertIn('--sign "$RELEASE_CODE_SIGN_IDENTITY"', release_script)
        self.assertIn('codesign --verify --verbose=2 "$DMG_PATH"', verify_script)
        self.assertIn('--context context:primary-signature', verify_script)

    def test_artifact_build_scripts_reject_invalid_build_number_before_external_work(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_result = subprocess.run(
                [
                    str(BUILD_RELEASE_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--build",
                    "abc",
                    "--release-dir",
                    str(Path(temp_dir) / "release"),
                    "--skip-notarization",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
            preview_result = subprocess.run(
                [
                    str(PREVIEW_DMG_SCRIPT),
                    "--version",
                    "1.2.3",
                    "--build",
                    "0",
                    "--preview-dir",
                    str(Path(temp_dir) / "preview"),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

        self.assertEqual(release_result.returncode, 1)
        self.assertIn("build must be a positive integer string", release_result.stderr)
        self.assertNotIn("missing required environment variable", release_result.stderr)
        self.assertEqual(preview_result.returncode, 1)
        self.assertIn("build must be a positive integer string", preview_result.stderr)
        self.assertNotIn("building local preview app", preview_result.stdout)

    def test_verify_release_manifest_rejects_bad_preview_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            preview_dir = Path(temp_dir) / "dist" / "preview" / "v1.2.3"
            preview_dir.mkdir(parents=True)
            dmg_path = preview_dir / "HoldType-1.2.3.dmg"
            zip_path = preview_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"preview dmg bytes")
            zip_path.write_bytes(b"preview zip bytes")
            manifest_path = preview_dir / "preview-manifest.json"
            manifest_path.write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "local-preview",
                        "version": "v1.2.3",
                        "build": "0",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": str(dmg_path), "sha256": "0" * 64},
                        "zip": {
                            "path": str(zip_path),
                            "sha256": hashlib.sha256(zip_path.read_bytes()).hexdigest(),
                        },
                    }
                )
            )

            result = subprocess.run(
                [
                    str(VERIFY_RELEASE_MANIFEST_SCRIPT),
                    "--manifest",
                    str(manifest_path),
                    "--artifact-root",
                    str(preview_dir),
                    "--expect-kind",
                    "local-preview",
                    "--expect-public-release",
                    "false",
                    "--expect-notarized",
                    "false",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] manifest:public_release", result.stdout)
            self.assertIn("[fail] manifest:notarized", result.stdout)
            self.assertIn("[fail] manifest:version", result.stdout)
            self.assertIn("[fail] manifest:build", result.stdout)
            self.assertIn("[fail] manifest:dmg.sha256", result.stdout)

    def test_verify_install_channels_checks_appcast_and_cask_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "v1.2.3"
            release_dir.mkdir()
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"fake dmg bytes")
            zip_path.write_bytes(b"fake zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": dmg_path.name, "sha256": dmg_sha},
                        "zip": {"path": zip_path.name, "sha256": zip_sha},
                    }
                )
            )
            (release_dir / "SHA256SUMS.txt").write_text(
                f"{dmg_sha}  {dmg_path.name}\n{zip_sha}  {zip_path.name}\n"
            )
            appcast_url = (
                "https://github.com/holdtype/holdtype-swift/releases/download/"
                "v1.2.3/HoldType-1.2.3.dmg"
            )
            (release_dir / "appcast.xml").write_text(
                f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{appcast_url}"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{dmg_path.stat().st_size}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_CHANNELS_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("[pass] appcast:enclosure-url", result.stdout)
            self.assertIn("[pass] appcast:edSignature", result.stdout)
            self.assertIn("[pass] appcast:version", result.stdout)
            self.assertIn("[pass] appcast:shortVersionString", result.stdout)
            self.assertIn("[pass] manifest:kind", result.stdout)
            self.assertIn("[pass] manifest:build", result.stdout)
            self.assertIn("[pass] manifest:public_release", result.stdout)
            self.assertIn("[pass] manifest:notarized", result.stdout)
            self.assertIn("[pass] zip:sha256", result.stdout)
            self.assertIn("[pass] homebrew-cask:sha256", result.stdout)
            self.assertIn("[pass] homebrew-cask:minimum-macos", result.stdout)
            self.assertIn("[pass] homebrew-cask:uninstall-quit", result.stdout)
            self.assertIn("[pass] homebrew-cask:zap-caches", result.stdout)
            self.assertIn("[pass] homebrew-cask:zap-preferences", result.stdout)
            self.assertIn("[pass] homebrew-cask:zap-saved-state", result.stdout)

    def test_verify_install_channels_rejects_appcast_version_mismatch(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "v1.2.3"
            release_dir.mkdir()
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"fake dmg bytes")
            zip_path.write_bytes(b"fake zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": dmg_path.name, "sha256": dmg_sha},
                        "zip": {"path": zip_path.name, "sha256": zip_sha},
                    }
                )
            )
            (release_dir / "SHA256SUMS.txt").write_text(
                f"{dmg_sha}  {dmg_path.name}\n{zip_sha}  {zip_path.name}\n"
            )
            appcast_url = (
                "https://github.com/holdtype/holdtype-swift/releases/download/"
                "v1.2.3/HoldType-1.2.3.dmg"
            )
            (release_dir / "appcast.xml").write_text(
                f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{appcast_url}"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="99"
                 sparkle:shortVersionString="1.2.2"
                 length="{dmg_path.stat().st_size}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_CHANNELS_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] appcast:version", result.stdout)
            self.assertIn("[fail] appcast:shortVersionString", result.stdout)

    def test_verify_install_channels_rejects_nonportable_artifact_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "v1.2.3"
            release_dir.mkdir()
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"fake dmg bytes")
            zip_path.write_bytes(b"fake zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "public-release",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": True,
                        "public_release": True,
                        "dmg": {"path": str(dmg_path), "sha256": dmg_sha},
                        "zip": {"path": str(zip_path), "sha256": zip_sha},
                    }
                )
            )
            (release_dir / "SHA256SUMS.txt").write_text(
                f"{dmg_sha}  {dmg_path}\n{zip_sha}  {zip_path}\n"
            )
            (release_dir / "appcast.xml").write_text(
                """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel />
</rss>
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_CHANNELS_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] manifest:dmg.path", result.stdout)
            self.assertIn("[fail] manifest:zip.path", result.stdout)
            self.assertIn("[fail] sha256s:path", result.stdout)

    def test_verify_install_channels_rejects_preview_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            release_dir = Path(temp_dir) / "v1.2.3"
            release_dir.mkdir()
            dmg_path = release_dir / "HoldType-1.2.3.dmg"
            zip_path = release_dir / "HoldType-1.2.3.zip"
            dmg_path.write_bytes(b"fake dmg bytes")
            zip_path.write_bytes(b"fake zip bytes")
            dmg_sha = hashlib.sha256(dmg_path.read_bytes()).hexdigest()
            zip_sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            (release_dir / "release-manifest.json").write_text(
                json.dumps(
                    {
                        "app": "HoldType",
                        "kind": "local-preview",
                        "version": "1.2.3",
                        "build": "100",
                        "tag": "v1.2.3",
                        "notarized": False,
                        "public_release": False,
                        "dmg": {"path": dmg_path.name, "sha256": dmg_sha},
                        "zip": {"path": zip_path.name, "sha256": zip_sha},
                    }
                )
            )
            (release_dir / "SHA256SUMS.txt").write_text(
                f"{dmg_sha}  {dmg_path.name}\n{zip_sha}  {zip_path.name}\n"
            )
            appcast_url = (
                "https://github.com/holdtype/holdtype-swift/releases/download/"
                "v1.2.3/HoldType-1.2.3.dmg"
            )
            (release_dir / "appcast.xml").write_text(
                f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{appcast_url}"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{dmg_path.stat().st_size}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            )

            result = subprocess.run(
                [
                    str(VERIFY_CHANNELS_SCRIPT),
                    "--release-dir",
                    str(release_dir),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--minimum-macos",
                    ">= :tahoe",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] manifest:kind", result.stdout)
            self.assertIn("[fail] manifest:public_release", result.stdout)
            self.assertIn("[fail] manifest:notarized", result.stdout)

    def test_verify_published_release_checks_github_assets_and_appcast(self) -> None:
        dmg_bytes = b"published dmg bytes"
        zip_bytes = b"published zip bytes"
        dmg_sha = hashlib.sha256(dmg_bytes).hexdigest()
        zip_sha = hashlib.sha256(zip_bytes).hexdigest()
        version = "1.2.3"
        tag = f"v{version}"
        notes_text = "# HoldType 1.2.3\n\nPublished release notes.\n"

        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            download_prefix = f"{base_url}/download/{tag}/"
            dmg_url = f"{download_prefix}HoldType-{version}.dmg"
            appcast_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{dmg_url}"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{len(dmg_bytes)}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            manifest = {
                "app": "HoldType",
                "kind": "public-release",
                "version": version,
                "build": "100",
                "tag": tag,
                "notarized": True,
                "public_release": True,
                "dmg": {"path": f"HoldType-{version}.dmg", "sha256": dmg_sha},
                "zip": {"path": f"HoldType-{version}.zip", "sha256": zip_sha},
            }
            release = {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": tag,
                "draft": False,
                "prerelease": False,
                "body": notes_text,
                "assets": [
                    {
                        "name": f"HoldType-{version}.dmg",
                        "state": "uploaded",
                        "size": len(dmg_bytes),
                        "browser_download_url": dmg_url,
                    },
                    {
                        "name": f"HoldType-{version}.zip",
                        "state": "uploaded",
                        "size": len(zip_bytes),
                        "browser_download_url": f"{download_prefix}HoldType-{version}.zip",
                    },
                    {
                        "name": "SHA256SUMS.txt",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}SHA256SUMS.txt",
                    },
                    {
                        "name": "release-manifest.json",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}release-manifest.json",
                    },
                    {
                        "name": "appcast.xml",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}appcast.xml",
                    },
                ],
            }
            routes[
                "/repos/holdtype/holdtype-swift/releases/tags/v1.2.3"
            ] = (json.dumps(release).encode("utf-8"), "application/json")
            routes[f"/download/{tag}/HoldType-{version}.dmg"] = (
                dmg_bytes,
                "application/octet-stream",
            )
            routes[f"/download/{tag}/HoldType-{version}.zip"] = (
                zip_bytes,
                "application/octet-stream",
            )
            routes[f"/download/{tag}/SHA256SUMS.txt"] = (
                (
                    f"{dmg_sha}  HoldType-{version}.dmg\n"
                    f"{zip_sha}  HoldType-{version}.zip\n"
                ).encode("utf-8"),
                "text/plain",
            )
            routes[f"/download/{tag}/release-manifest.json"] = (
                json.dumps(manifest).encode("utf-8"),
                "application/json",
            )
            routes[f"/download/{tag}/appcast.xml"] = (appcast_xml.encode("utf-8"), "application/xml")
            routes["/pages/appcast.xml"] = (appcast_xml.encode("utf-8"), "application/xml")

            with tempfile.TemporaryDirectory() as notes_temp_dir:
                notes_path = Path(notes_temp_dir) / "release-notes.md"
                notes_path.write_text(notes_text)
                result = subprocess.run(
                    [
                        str(VERIFY_PUBLISHED_RELEASE_SCRIPT),
                        "--repository",
                        "holdtype/holdtype-swift",
                        "--version",
                        version,
                        "--github-api-url",
                        base_url,
                        "--download-url-prefix",
                        download_prefix,
                        "--appcast-url",
                        f"{base_url}/pages/appcast.xml",
                        "--release-notes-file",
                        str(notes_path),
                        "--timeout",
                        "5",
                    ],
                    cwd=ROOT,
                    text=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    check=True,
                )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertIn("[pass] github-release:tag", result.stdout)
        self.assertIn("[pass] github-release:draft", result.stdout)
        self.assertIn("[pass] github-release:prerelease", result.stdout)
        self.assertIn("[pass] github-asset-state:HoldType-1.2.3.dmg", result.stdout)
        self.assertIn("[pass] github-asset-size:HoldType-1.2.3.dmg", result.stdout)
        self.assertIn("[pass] release-notes:quality", result.stdout)
        self.assertIn("[pass] github-release:body", result.stdout)
        self.assertIn("[pass] manifest:kind", result.stdout)
        self.assertIn("[pass] manifest:build", result.stdout)
        self.assertIn("[pass] manifest:public_release", result.stdout)
        self.assertIn("[pass] manifest:notarized", result.stdout)
        self.assertIn("[pass] manifest:dmg.sha256", result.stdout)
        self.assertIn("[pass] sha256s:HoldType-1.2.3.dmg", result.stdout)
        self.assertIn("[pass] release-appcast:enclosure-url", result.stdout)
        self.assertIn("[pass] release-appcast:version", result.stdout)
        self.assertIn("[pass] release-appcast:shortVersionString", result.stdout)
        self.assertIn("[pass] published-appcast:enclosure-url", result.stdout)
        self.assertIn("[pass] published-appcast:release-asset-match", result.stdout)
        self.assertIn("[pass] published-appcast:version", result.stdout)
        self.assertIn("[pass] published-appcast:shortVersionString", result.stdout)

    def test_verify_published_release_can_verify_downloaded_dmg_install_path(self) -> None:
        module = load_published_release_module()
        calls: list[list[str]] = []
        original_run = module.subprocess.run

        class FakeResult:
            returncode = 0
            stdout = "verification passed\n"
            stderr = ""

        def fake_run(command: list[str], **_: object) -> FakeResult:
            calls.append(command)
            return FakeResult()

        module.subprocess.run = fake_run
        try:
            checks = module.check_downloaded_dmg_install(
                dmg_path=Path("/tmp/HoldType-1.2.3.dmg"),
                timeout=12,
            )
        finally:
            module.subprocess.run = original_run

        self.assertEqual([check.status for check in checks], ["pass", "pass"])
        self.assertEqual([check.name for check in checks], ["published-dmg:layout", "published-dmg:install"])
        self.assertEqual(Path(calls[0][0]).name, "verify_dmg_layout.sh")
        self.assertEqual(Path(calls[1][0]).name, "verify_dmg_install.sh")
        self.assertIn("--timeout", calls[0])
        self.assertIn("12", calls[0])
        self.assertIn("--timeout", calls[1])
        self.assertIn("12", calls[1])

    def test_verify_published_release_rejects_malformed_repository_before_fetch(self) -> None:
        result = subprocess.run(
            [
                str(VERIFY_PUBLISHED_RELEASE_SCRIPT),
                "--repository",
                "potapenko/holdtype/swift",
                "--version",
                "1.2.3",
                "--github-api-url",
                "http://127.0.0.1:1",
                "--timeout",
                "1",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] repository", result.stdout)
        self.assertIn("expected OWNER/REPO", result.stdout)
        self.assertNotIn("github-release", result.stdout)

    def test_verify_published_release_rejects_mismatched_published_appcast(self) -> None:
        dmg_bytes = b"published dmg bytes"
        zip_bytes = b"published zip bytes"
        dmg_sha = hashlib.sha256(dmg_bytes).hexdigest()
        zip_sha = hashlib.sha256(zip_bytes).hexdigest()
        version = "1.2.3"
        tag = f"v{version}"

        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            download_prefix = f"{base_url}/download/{tag}/"
            dmg_url = f"{download_prefix}HoldType-{version}.dmg"
            release_appcast_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{dmg_url}"
                 sparkle:edSignature="release-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{len(dmg_bytes)}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            published_appcast_xml = release_appcast_xml.replace(
                "release-signature",
                "pages-signature",
            )
            manifest = {
                "app": "HoldType",
                "kind": "public-release",
                "version": version,
                "build": "100",
                "tag": tag,
                "notarized": True,
                "public_release": True,
                "dmg": {"path": f"HoldType-{version}.dmg", "sha256": dmg_sha},
                "zip": {"path": f"HoldType-{version}.zip", "sha256": zip_sha},
            }
            release = {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": tag,
                "draft": False,
                "prerelease": False,
                "body": "",
                "assets": [
                    {
                        "name": f"HoldType-{version}.dmg",
                        "state": "uploaded",
                        "size": len(dmg_bytes),
                        "browser_download_url": dmg_url,
                    },
                    {
                        "name": f"HoldType-{version}.zip",
                        "state": "uploaded",
                        "size": len(zip_bytes),
                        "browser_download_url": f"{download_prefix}HoldType-{version}.zip",
                    },
                    {
                        "name": "SHA256SUMS.txt",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}SHA256SUMS.txt",
                    },
                    {
                        "name": "release-manifest.json",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}release-manifest.json",
                    },
                    {
                        "name": "appcast.xml",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}appcast.xml",
                    },
                ],
            }
            routes[
                "/repos/holdtype/holdtype-swift/releases/tags/v1.2.3"
            ] = (json.dumps(release).encode("utf-8"), "application/json")
            routes[f"/download/{tag}/SHA256SUMS.txt"] = (
                (
                    f"{dmg_sha}  HoldType-{version}.dmg\n"
                    f"{zip_sha}  HoldType-{version}.zip\n"
                ).encode("utf-8"),
                "text/plain",
            )
            routes[f"/download/{tag}/release-manifest.json"] = (
                json.dumps(manifest).encode("utf-8"),
                "application/json",
            )
            routes[f"/download/{tag}/appcast.xml"] = (
                release_appcast_xml.encode("utf-8"),
                "application/xml",
            )
            routes["/pages/appcast.xml"] = (
                published_appcast_xml.encode("utf-8"),
                "application/xml",
            )

            result = subprocess.run(
                [
                    str(VERIFY_PUBLISHED_RELEASE_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--version",
                    version,
                    "--github-api-url",
                    base_url,
                    "--download-url-prefix",
                    download_prefix,
                    "--appcast-url",
                    f"{base_url}/pages/appcast.xml",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] published-appcast:release-asset-match", result.stdout)

    def test_verify_published_release_rejects_draft_or_prerelease(self) -> None:
        module = load_published_release_module()

        assets, checks = module.check_release_basics(
            {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": "v1.2.3",
                "draft": True,
                "prerelease": True,
                "assets": [],
            },
            download_url_prefix="https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/",
            tag="v1.2.3",
            version="1.2.3",
        )

        self.assertEqual(assets, {})
        statuses = {check.name: check.status for check in checks}
        self.assertEqual(statuses["github-release:draft"], "fail")
        self.assertEqual(statuses["github-release:prerelease"], "fail")

    def test_verify_published_release_rejects_incomplete_or_empty_assets(self) -> None:
        module = load_published_release_module()
        download_prefix = "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/"
        assets_payload = [
            {
                "name": "HoldType-1.2.3.dmg",
                "state": "starter",
                "size": 0,
                "browser_download_url": f"{download_prefix}HoldType-1.2.3.dmg",
            },
        ]
        for name in ("HoldType-1.2.3.zip", "SHA256SUMS.txt", "appcast.xml", "release-manifest.json"):
            assets_payload.append(
                {
                    "name": name,
                    "state": "uploaded",
                    "size": 1,
                    "browser_download_url": f"{download_prefix}{name}",
                }
            )

        _, checks = module.check_release_basics(
            {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": "v1.2.3",
                "draft": False,
                "prerelease": False,
                "assets": assets_payload,
            },
            download_url_prefix=download_prefix,
            tag="v1.2.3",
            version="1.2.3",
        )

        statuses = {check.name: check.status for check in checks}
        self.assertEqual(statuses["github-asset-state:HoldType-1.2.3.dmg"], "fail")
        self.assertEqual(statuses["github-asset-size:HoldType-1.2.3.dmg"], "fail")

    def test_verify_published_release_rejects_unexpected_assets(self) -> None:
        module = load_published_release_module()
        download_prefix = "https://github.com/holdtype/holdtype-swift/releases/download/v1.2.3/"
        assets_payload = []
        for name in (
            "HoldType-1.2.3.dmg",
            "HoldType-1.2.3.zip",
            "SHA256SUMS.txt",
            "appcast.xml",
            "release-manifest.json",
        ):
            assets_payload.append(
                {
                    "name": name,
                    "state": "uploaded",
                    "size": 1,
                    "browser_download_url": f"{download_prefix}{name}",
                }
            )
        assets_payload.append(
            {
                "name": "HoldType-1.2.3-notary.zip",
                "state": "uploaded",
                "size": 1,
                "browser_download_url": f"{download_prefix}HoldType-1.2.3-notary.zip",
            }
        )

        _, checks = module.check_release_basics(
            {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": "v1.2.3",
                "draft": False,
                "prerelease": False,
                "assets": assets_payload,
            },
            download_url_prefix=download_prefix,
            tag="v1.2.3",
            version="1.2.3",
        )

        statuses = {check.name: check.status for check in checks}
        messages = {check.name: check.message for check in checks}
        self.assertEqual(statuses["github-assets:unexpected"], "fail")
        self.assertIn("HoldType-1.2.3-notary.zip", messages["github-assets:unexpected"])

    def test_prune_github_release_assets_deletes_only_unexpected_assets_when_applied(self) -> None:
        delete_paths: list[str] = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                if self.path != "/repos/holdtype/holdtype-swift/releases/tags/v1.2.3":
                    self.send_response(404)
                    self.end_headers()
                    return
                body = json.dumps(
                    {
                        "tag_name": "v1.2.3",
                        "assets": [
                            {"id": 101, "name": "HoldType-1.2.3.dmg"},
                            {"id": 102, "name": "HoldType-1.2.3.zip"},
                            {"id": 201, "name": "HoldType-1.2.3-notary.zip"},
                        ],
                    }
                ).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def do_DELETE(self) -> None:  # noqa: N802 - stdlib callback
                delete_paths.append(self.path)
                self.send_response(204)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run(
                [
                    str(PRUNE_GITHUB_RELEASE_ASSETS_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--version",
                    "1.2.3",
                    "--github-api-url",
                    f"http://127.0.0.1:{server.server_port}",
                    "--timeout",
                    "5",
                    "--apply",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(
            delete_paths,
            ["/repos/holdtype/holdtype-swift/releases/assets/201"],
        )
        self.assertIn("[pass] github-assets:prune-unexpected", result.stdout)
        self.assertIn("[pass] github-asset-prune:HoldType-1.2.3-notary.zip", result.stdout)
        self.assertNotIn("github-asset-prune:HoldType-1.2.3.dmg", result.stdout)

    def test_prune_github_release_assets_treats_missing_release_as_noop(self) -> None:
        delete_paths: list[str] = []

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                self.send_response(404)
                self.end_headers()

            def do_DELETE(self) -> None:  # noqa: N802 - stdlib callback
                delete_paths.append(self.path)
                self.send_response(204)
                self.end_headers()

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = subprocess.run(
                [
                    str(PRUNE_GITHUB_RELEASE_ASSETS_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--version",
                    "1.2.3",
                    "--github-api-url",
                    f"http://127.0.0.1:{server.server_port}",
                    "--timeout",
                    "5",
                    "--apply",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(delete_paths, [])
        self.assertIn("release does not exist yet", result.stdout)

    def test_verify_published_release_rejects_nonportable_artifact_paths(self) -> None:
        dmg_bytes = b"published dmg bytes"
        zip_bytes = b"published zip bytes"
        dmg_sha = hashlib.sha256(dmg_bytes).hexdigest()
        zip_sha = hashlib.sha256(zip_bytes).hexdigest()
        version = "1.2.3"
        tag = f"v{version}"
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            download_prefix = f"{base_url}/download/{tag}/"
            dmg_url = f"{download_prefix}HoldType-{version}.dmg"
            appcast_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{dmg_url}"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{len(dmg_bytes)}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            release = {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": tag,
                "draft": False,
                "prerelease": False,
                "body": "",
                "assets": [
                    {
                        "name": f"HoldType-{version}.dmg",
                        "state": "uploaded",
                        "size": len(dmg_bytes),
                        "browser_download_url": dmg_url,
                    },
                    {
                        "name": f"HoldType-{version}.zip",
                        "state": "uploaded",
                        "size": len(zip_bytes),
                        "browser_download_url": f"{download_prefix}HoldType-{version}.zip",
                    },
                    {
                        "name": "SHA256SUMS.txt",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}SHA256SUMS.txt",
                    },
                    {
                        "name": "release-manifest.json",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}release-manifest.json",
                    },
                    {
                        "name": "appcast.xml",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}appcast.xml",
                    },
                ],
            }
            manifest = {
                "app": "HoldType",
                "kind": "public-release",
                "version": version,
                "build": "100",
                "tag": tag,
                "notarized": True,
                "public_release": True,
                "dmg": {"path": f"dist/release/{tag}/HoldType-{version}.dmg", "sha256": dmg_sha},
                "zip": {"path": f"dist/release/{tag}/HoldType-{version}.zip", "sha256": zip_sha},
            }
            routes[
                "/repos/holdtype/holdtype-swift/releases/tags/v1.2.3"
            ] = (json.dumps(release).encode("utf-8"), "application/json")
            routes[f"/download/{tag}/SHA256SUMS.txt"] = (
                (
                    f"{dmg_sha}  dist/release/{tag}/HoldType-{version}.dmg\n"
                    f"{zip_sha}  dist/release/{tag}/HoldType-{version}.zip\n"
                ).encode("utf-8"),
                "text/plain",
            )
            routes[f"/download/{tag}/release-manifest.json"] = (
                json.dumps(manifest).encode("utf-8"),
                "application/json",
            )
            routes[f"/download/{tag}/appcast.xml"] = (appcast_xml.encode("utf-8"), "application/xml")

            result = subprocess.run(
                [
                    str(VERIFY_PUBLISHED_RELEASE_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--version",
                    version,
                    "--github-api-url",
                    base_url,
                    "--download-url-prefix",
                    download_prefix,
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] manifest:dmg.path", result.stdout)
        self.assertIn("[fail] sha256s-path:HoldType-1.2.3.dmg", result.stdout)

    def test_verify_published_release_rejects_preview_manifest(self) -> None:
        dmg_bytes = b"published dmg bytes"
        zip_bytes = b"published zip bytes"
        dmg_sha = hashlib.sha256(dmg_bytes).hexdigest()
        zip_sha = hashlib.sha256(zip_bytes).hexdigest()
        version = "1.2.3"
        tag = f"v{version}"

        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            download_prefix = f"{base_url}/download/{tag}/"
            release = {
                "html_url": "https://github.com/holdtype/holdtype-swift/releases/tag/v1.2.3",
                "tag_name": tag,
                "draft": False,
                "prerelease": False,
                "body": "",
                "assets": [
                    {
                        "name": f"HoldType-{version}.dmg",
                        "state": "uploaded",
                        "size": len(dmg_bytes),
                        "browser_download_url": f"{download_prefix}HoldType-{version}.dmg",
                    },
                    {
                        "name": f"HoldType-{version}.zip",
                        "state": "uploaded",
                        "size": len(zip_bytes),
                        "browser_download_url": f"{download_prefix}HoldType-{version}.zip",
                    },
                    {
                        "name": "SHA256SUMS.txt",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}SHA256SUMS.txt",
                    },
                    {
                        "name": "release-manifest.json",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}release-manifest.json",
                    },
                    {
                        "name": "appcast.xml",
                        "state": "uploaded",
                        "size": 1,
                        "browser_download_url": f"{download_prefix}appcast.xml",
                    },
                ],
            }
            preview_manifest = {
                "app": "HoldType",
                "kind": "local-preview",
                "version": version,
                "build": "100",
                "tag": tag,
                "notarized": False,
                "public_release": False,
                "dmg": {"path": f"dist/preview/{tag}/HoldType-{version}.dmg", "sha256": dmg_sha},
                "zip": {"path": f"dist/preview/{tag}/HoldType-{version}.zip", "sha256": zip_sha},
            }
            appcast_xml = f"""<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <item>
      <enclosure url="{download_prefix}HoldType-{version}.dmg"
                 sparkle:edSignature="fake-signature"
                 sparkle:version="100"
                 sparkle:shortVersionString="1.2.3"
                 length="{len(dmg_bytes)}"
                 type="application/octet-stream" />
    </item>
  </channel>
</rss>
"""
            routes[
                "/repos/holdtype/holdtype-swift/releases/tags/v1.2.3"
            ] = (json.dumps(release).encode("utf-8"), "application/json")
            routes[f"/download/{tag}/SHA256SUMS.txt"] = (
                (
                    f"{dmg_sha}  dist/preview/{tag}/HoldType-{version}.dmg\n"
                    f"{zip_sha}  dist/preview/{tag}/HoldType-{version}.zip\n"
                ).encode("utf-8"),
                "text/plain",
            )
            routes[f"/download/{tag}/release-manifest.json"] = (
                json.dumps(preview_manifest).encode("utf-8"),
                "application/json",
            )
            routes[f"/download/{tag}/appcast.xml"] = (appcast_xml.encode("utf-8"), "application/xml")

            result = subprocess.run(
                [
                    str(VERIFY_PUBLISHED_RELEASE_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--version",
                    version,
                    "--github-api-url",
                    base_url,
                    "--download-url-prefix",
                    download_prefix,
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] manifest:kind", result.stdout)
        self.assertIn("[fail] manifest:public_release", result.stdout)
        self.assertIn("[fail] manifest:notarized", result.stdout)

    def test_verify_github_release_setup_checks_secrets_and_pages(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
        ]
        environment_secret_names = [
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_TAP_TOKEN",
            "HOMEBREW_GITHUB_API_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_TAP_REPOSITORY", "value": "holdtype/homebrew-tap"},
                            {"name": "HOMEBREW_EXPECTED_TAP", "value": "holdtype/tap"},
                            {"name": "HOMEBREW_MINIMUM_MACOS", "value": ">= :tahoe"},
                            {"name": "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED", "value": "true"},
                            {"name": "HOMEBREW_OFFICIAL_CASK_FORK_ORG", "value": "holdtype"},
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/homebrew-tap"] = (
                json.dumps(
                    {
                        "full_name": "holdtype/homebrew-tap",
                        "private": False,
                        "archived": False,
                        "default_branch": "main",
                    }
                ).encode("utf-8"),
                "application/json",
            )
            official_cask_text = rendered_official_cask_text()
            routes["/repos/Homebrew/homebrew-cask/contents/Casks/h/holdtype.rb?ref=main"] = (
                json.dumps(
                    {
                        "path": "Casks/h/holdtype.rb",
                        "type": "file",
                        "encoding": "base64",
                        "content": base64.b64encode(official_cask_text.encode("utf-8")).decode(
                            "ascii"
                        ),
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes[
                "/repos/holdtype/holdtype-swift/environments/github-pages/secrets?per_page=100"
            ] = (
                json.dumps(
                    {"secrets": [{"name": name} for name in environment_secret_names]}
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/pages"] = (
                json.dumps(
                    {
                        "html_url": "https://holdtype.github.io/holdtype-swift/",
                        "status": "built",
                        "build_type": "workflow",
                        "https_enforced": True,
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--appcast-url",
                    "https://holdtype.github.io/holdtype-swift/appcast.xml",
                    "--expected-homebrew-tap",
                    "holdtype/tap",
                    "--require-homebrew-tap",
                    "--require-homebrew-minimum-macos",
                    "--require-official-homebrew-cask-bump",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertIn("[pass] github-secrets:repository", result.stdout)
        self.assertIn("[pass] github-secrets:environment:github-pages", result.stdout)
        self.assertIn("[pass] secret:APPLE_TEAM_ID", result.stdout)
        self.assertIn("[pass] secret:HOLDTYPE_UPDATE_FEED_URL", result.stdout)
        self.assertIn("[pass] secret:HOMEBREW_TAP_TOKEN", result.stdout)
        self.assertIn("[pass] github-variables:repository", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_TAP_REPOSITORY", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_TAP_REPOSITORY:tap-name", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_EXPECTED_TAP: holdtype/tap", result.stdout)
        self.assertIn("[pass] github-tap-repository:visibility", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_MINIMUM_MACOS", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED", result.stdout)
        self.assertIn("[pass] secret:HOMEBREW_GITHUB_API_TOKEN", result.stdout)
        self.assertIn("[pass] variable:HOMEBREW_OFFICIAL_CASK_FORK_ORG", result.stdout)
        self.assertIn("[pass] github-official-cask:path", result.stdout)
        self.assertIn("[pass] github-official-cask:content", result.stdout)
        self.assertIn("[pass] github-official-cask:token", result.stdout)
        self.assertIn("[pass] github-official-cask:sha256", result.stdout)
        self.assertIn("[pass] github-official-cask:url", result.stdout)
        self.assertIn("[pass] github-official-cask:app", result.stdout)
        self.assertIn("[pass] github-official-cask:forbid-no-check", result.stdout)
        self.assertIn("[pass] github-pages:build_type", result.stdout)
        self.assertIn("[pass] github-pages:appcast-url", result.stdout)

    def test_verify_github_release_setup_checks_official_cask_without_bump_enabled(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps({"variables": []}).encode("utf-8"),
                "application/json",
            )
            official_cask_text = rendered_official_cask_text()
            routes["/repos/Homebrew/homebrew-cask/contents/Casks/h/holdtype.rb?ref=main"] = (
                json.dumps(
                    {
                        "path": "Casks/h/holdtype.rb",
                        "type": "file",
                        "encoding": "base64",
                        "content": base64.b64encode(official_cask_text.encode("utf-8")).decode(
                            "ascii"
                        ),
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-official-homebrew-cask",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertIn("[warn] homebrew-official-cask-bump", result.stdout)
        self.assertNotIn("[fail] secret:HOMEBREW_GITHUB_API_TOKEN", result.stdout)
        self.assertIn("[pass] github-official-cask:path", result.stdout)
        self.assertIn("[pass] github-official-cask:token", result.stdout)
        self.assertIn("[pass] github-official-cask:sha256", result.stdout)
        self.assertIn("[pass] github-official-cask:url", result.stdout)
        self.assertIn("[pass] github-official-cask:app", result.stdout)

    def test_verify_github_release_setup_rejects_wrong_official_cask_content(self) -> None:
        module = load_github_setup_module()
        official_cask_text = """
cask "other-app" do
  version "1.2.3"
  url "https://github.com/example/other/releases/download/v#{version}/Other-#{version}.dmg"
end
"""

        checks = module.check_official_homebrew_cask_file(
            {
                "path": "Casks/h/holdtype.rb",
                "type": "file",
                "encoding": "base64",
                "content": base64.b64encode(official_cask_text.encode("utf-8")).decode("ascii"),
            },
            expected_repository="holdtype/holdtype-swift",
        )

        statuses = {check.name: check.status for check in checks}
        self.assertEqual(statuses["github-official-cask:path"], "pass")
        self.assertEqual(statuses["github-official-cask:type"], "pass")
        self.assertEqual(statuses["github-official-cask:content"], "pass")
        self.assertEqual(statuses["github-official-cask:token"], "fail")
        self.assertEqual(statuses["github-official-cask:url"], "fail")

    def test_verify_github_release_setup_rejects_unpinned_official_cask(self) -> None:
        module = load_github_setup_module()
        official_cask_text = (
            rendered_official_cask_text()
            .replace('  version "1.2.3"', "  version :latest")
            .replace(
                '  sha256 "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"',
                "  sha256 :no_check",
            )
        )

        checks = module.check_official_homebrew_cask_file(
            {
                "path": "Casks/h/holdtype.rb",
                "type": "file",
                "encoding": "base64",
                "content": base64.b64encode(official_cask_text.encode("utf-8")).decode("ascii"),
            },
            expected_repository="holdtype/holdtype-swift",
        )

        statuses = {check.name: check.status for check in checks}
        self.assertEqual(statuses["github-official-cask:token"], "pass")
        self.assertEqual(statuses["github-official-cask:url"], "pass")
        self.assertEqual(statuses["github-official-cask:version"], "fail")
        self.assertEqual(statuses["github-official-cask:sha256"], "fail")
        self.assertEqual(statuses["github-official-cask:forbid-latest"], "fail")
        self.assertEqual(statuses["github-official-cask:forbid-no-check"], "fail")

    def test_verify_github_release_setup_requires_official_bump_token_when_enabled(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED", "value": "true"}
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-official-homebrew-cask-bump",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[pass] variable:HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED", result.stdout)
        self.assertIn("[fail] secret:HOMEBREW_GITHUB_API_TOKEN", result.stdout)

    def test_verify_github_release_setup_requires_homebrew_prefixed_tap_repo(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_TAP_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_TAP_REPOSITORY", "value": "holdtype/tap"},
                            {"name": "HOMEBREW_MINIMUM_MACOS", "value": ">= :tahoe"},
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/tap/"] = (
                json.dumps(
                    {
                        "full_name": "holdtype/tap",
                        "private": False,
                        "archived": False,
                        "default_branch": "main",
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-tap",
                    "--require-homebrew-minimum-macos",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[pass] variable:HOMEBREW_TAP_REPOSITORY: holdtype/tap", result.stdout)
        self.assertIn("[fail] variable:HOMEBREW_TAP_REPOSITORY:repository-name", result.stdout)

    def test_verify_github_release_setup_rejects_unexpected_homebrew_tap_prefix(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_TAP_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_TAP_REPOSITORY", "value": "potapenko/homebrew-tap"},
                            {"name": "HOMEBREW_EXPECTED_TAP", "value": "holdtype/tap"},
                            {"name": "HOMEBREW_MINIMUM_MACOS", "value": ">= :tahoe"},
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/potapenko/homebrew-tap/"] = (
                json.dumps(
                    {
                        "full_name": "potapenko/homebrew-tap",
                        "private": False,
                        "archived": False,
                        "default_branch": "main",
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-tap",
                    "--require-homebrew-minimum-macos",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[pass] variable:HOMEBREW_TAP_REPOSITORY:tap-name: potapenko/tap", result.stdout)
        self.assertIn("[fail] variable:HOMEBREW_EXPECTED_TAP", result.stdout)
        self.assertIn("potapenko/homebrew-tap installs as potapenko/tap", result.stdout)

    def test_verify_github_release_setup_requires_existing_official_cask_for_bump(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_GITHUB_API_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED", "value": "true"}
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-official-homebrew-cask-bump",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[pass] secret:HOMEBREW_GITHUB_API_TOKEN", result.stdout)
        self.assertIn("[fail] github-official-cask", result.stdout)

    def test_verify_github_release_setup_requires_homebrew_tap_repository_variable(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_TAP_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps({"variables": []}).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-tap",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] variable:HOMEBREW_TAP_REPOSITORY", result.stdout)
        self.assertIn("[pass] secret:HOMEBREW_TAP_TOKEN", result.stdout)

    def test_verify_github_release_setup_rejects_private_homebrew_tap_repository(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        repo_secret_names = [
            "APPLE_TEAM_ID",
            "DEVELOPER_ID_CERTIFICATE_BASE64",
            "DEVELOPER_ID_CERTIFICATE_PASSWORD",
            "APP_STORE_CONNECT_KEY_ID",
            "APP_STORE_CONNECT_ISSUER_ID",
            "APP_STORE_CONNECT_PRIVATE_KEY",
            "SPARKLE_EDDSA_PRIVATE_KEY",
            "HOLDTYPE_UPDATE_FEED_URL",
            "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
            "HOMEBREW_TAP_TOKEN",
        ]

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": [{"name": name} for name in repo_secret_names]}).encode(
                    "utf-8"
                ),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {
                        "variables": [
                            {"name": "HOMEBREW_TAP_REPOSITORY", "value": "holdtype/homebrew-tap"},
                            {"name": "HOMEBREW_EXPECTED_TAP", "value": "holdtype/tap"},
                            {"name": "HOMEBREW_MINIMUM_MACOS", "value": ">= :tahoe"},
                        ]
                    }
                ).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/homebrew-tap"] = (
                json.dumps(
                    {
                        "full_name": "holdtype/homebrew-tap",
                        "private": True,
                        "archived": False,
                        "default_branch": "main",
                    }
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-tap",
                    "--require-homebrew-minimum-macos",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] github-tap-repository:visibility", result.stdout)
        self.assertIn("expected public repository", result.stdout)

    def test_verify_github_release_setup_rejects_invalid_homebrew_minimum_macos_variable(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": []}).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps(
                    {"variables": [{"name": "HOMEBREW_MINIMUM_MACOS", "value": "tahoe"}]}
                ).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-minimum-macos",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] variable:HOMEBREW_MINIMUM_MACOS", result.stdout)
        self.assertIn("expected a Homebrew macOS comparison expression", result.stdout)

    def test_verify_github_release_setup_requires_homebrew_minimum_macos_variable(self) -> None:
        routes: dict[str, tuple[bytes, str]] = {}

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self) -> None:  # noqa: N802 - stdlib callback
                response = routes.get(self.path)
                if response is None:
                    self.send_response(404)
                    self.end_headers()
                    return
                body, content_type = response
                self.send_response(200)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format: str, *args: object) -> None:
                return

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            base_url = f"http://127.0.0.1:{server.server_port}"
            routes["/repos/holdtype/holdtype-swift/actions/secrets?per_page=100"] = (
                json.dumps({"secrets": []}).encode("utf-8"),
                "application/json",
            )
            routes["/repos/holdtype/holdtype-swift/actions/variables?per_page=100"] = (
                json.dumps({"variables": []}).encode("utf-8"),
                "application/json",
            )

            result = subprocess.run(
                [
                    str(VERIFY_GITHUB_SETUP_SCRIPT),
                    "--repository",
                    "holdtype/holdtype-swift",
                    "--github-api-url",
                    base_url,
                    "--environment",
                    "",
                    "--skip-pages",
                    "--require-homebrew-minimum-macos",
                    "--timeout",
                    "5",
                ],
                cwd=ROOT,
                env={**os.environ, "GITHUB_TOKEN": "fake-token"},
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)

        self.assertEqual(result.returncode, 1)
        self.assertIn("[fail] variable:HOMEBREW_MINIMUM_MACOS", result.stdout)

    @unittest.skipUnless(shutil.which("hdiutil"), "hdiutil is required")
    def test_verify_dmg_layout_accepts_app_and_applications_shortcut(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            staging_dir = temp_path / "staging"
            staging_dir.mkdir()
            (staging_dir / "HoldType.app").mkdir()
            (staging_dir / "Applications").symlink_to("/Applications")
            dmg_path = temp_path / "HoldType-1.2.3.dmg"

            subprocess.run(
                [
                    "hdiutil",
                    "create",
                    "-volname",
                    "HoldType Test",
                    "-srcfolder",
                    str(staging_dir),
                    "-ov",
                    "-format",
                    "UDZO",
                    str(dmg_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [str(VERIFY_DMG_LAYOUT_SCRIPT), "--dmg", str(dmg_path), "--timeout", "60"],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("DMG layout verified", result.stdout)

    @unittest.skipUnless(shutil.which("hdiutil"), "hdiutil is required")
    def test_verify_dmg_install_copies_app_from_disk_image(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            staging_dir = temp_path / "staging"
            app_dir = staging_dir / "HoldType.app" / "Contents"
            app_dir.mkdir(parents=True)
            with (app_dir / "Info.plist").open("wb") as handle:
                plistlib.dump({"CFBundleName": "HoldType"}, handle)
            (staging_dir / "Applications").symlink_to("/Applications")
            dmg_path = temp_path / "HoldType-1.2.3.dmg"
            install_dir = temp_path / "install"

            subprocess.run(
                [
                    "hdiutil",
                    "create",
                    "-volname",
                    "HoldType Test",
                    "-srcfolder",
                    str(staging_dir),
                    "-ov",
                    "-format",
                    "UDZO",
                    str(dmg_path),
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            result = subprocess.run(
                [
                    str(VERIFY_DMG_INSTALL_SCRIPT),
                    "--dmg",
                    str(dmg_path),
                    "--install-dir",
                    str(install_dir),
                    "--skip-codesign",
                    "--timeout",
                    "60",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("DMG install copy verified", result.stdout)
            self.assertTrue((install_dir / "HoldType.app" / "Contents" / "Info.plist").exists())

    def test_verify_app_update_settings_requires_exact_release_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = Path(temp_dir) / "HoldType.app"
            contents_dir = app_dir / "Contents"
            contents_dir.mkdir(parents=True)
            with (contents_dir / "Info.plist").open("wb") as handle:
                plistlib.dump(
                    {
                        "SUFeedURL": "https://example.com/appcast.xml",
                        "SUPublicEDKey": "public-key",
                    },
                    handle,
                )

            result = subprocess.run(
                [
                    str(VERIFY_UPDATE_SETTINGS_SCRIPT),
                    "--app",
                    str(app_dir),
                    "--expected-feed-url",
                    "https://example.com/appcast.xml",
                    "--expected-public-ed-key",
                    "public-key",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=True,
            )

            self.assertIn("[pass] info-plist:SUFeedURL", result.stdout)
            self.assertIn("[pass] info-plist:SUPublicEDKey", result.stdout)

    def test_verify_app_update_settings_rejects_placeholder_release_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            app_dir = Path(temp_dir) / "HoldType.app"
            contents_dir = app_dir / "Contents"
            contents_dir.mkdir(parents=True)
            with (contents_dir / "Info.plist").open("wb") as handle:
                plistlib.dump(
                    {
                        "SUFeedURL": "$(HOLDTYPE_UPDATE_FEED_URL)",
                        "SUPublicEDKey": "",
                    },
                    handle,
                )

            result = subprocess.run(
                [
                    str(VERIFY_UPDATE_SETTINGS_SCRIPT),
                    "--app",
                    str(app_dir),
                    "--require-configured",
                ],
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                check=False,
            )

            self.assertEqual(result.returncode, 1)
            self.assertIn("[fail] info-plist:SUFeedURL", result.stdout)
            self.assertIn("[fail] info-plist:SUPublicEDKey", result.stdout)

    def test_preview_builder_help_documents_non_release_output(self) -> None:
        result = subprocess.run(
            [str(PREVIEW_DMG_SCRIPT), "--help"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        self.assertIn("non-notarized preview DMG", result.stdout)
        self.assertIn("not a public release artifact", result.stdout)

    def test_release_builder_help_documents_skip_notarization_manifest_kind(self) -> None:
        result = subprocess.run(
            [str(BUILD_RELEASE_SCRIPT), "--help"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

        self.assertIn("notarization-skipped-release", result.stdout)
        self.assertIn("not a public release artifact", result.stdout)

    def test_with_timeout_returns_124_for_expired_command(self) -> None:
        result = subprocess.run(
            [
                str(TIMEOUT_SCRIPT),
                "0.1",
                sys.executable,
                "-c",
                "import time; time.sleep(5)",
            ],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

        self.assertEqual(result.returncode, 124)
        self.assertIn("timed out", result.stderr)


if __name__ == "__main__":
    unittest.main()
