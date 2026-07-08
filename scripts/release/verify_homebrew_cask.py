#!/usr/bin/env python3
"""Verify a rendered HoldType Homebrew cask before audit or PR submission."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path


APP_NAME = "HoldType"
CASK_TOKEN = "holdtype"
SHA256_PATTERN = re.compile(r"^[0-9a-f]{64}$")


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


def validate_repository_slug(repository: str) -> Check | None:
    parts = repository.split("/", 1)
    if (
        len(parts) != 2
        or not parts[0]
        or not parts[1]
        or " " in parts[0]
        or " " in parts[1]
        or "/" in parts[1]
    ):
        return fail_check("repository", f"expected OWNER/REPO, got {repository!r}")
    return None


def validate_sha256(sha256: str) -> Check | None:
    if SHA256_PATTERN.fullmatch(sha256.lower()):
        return None
    return fail_check("sha256", "expected 64 hexadecimal characters")


def contains_line(text: str, line: str) -> bool:
    return any(candidate.strip() == line for candidate in text.splitlines())


def validate_official_layout(path: Path) -> list[Check]:
    expected = ("Casks", CASK_TOKEN[0], f"{CASK_TOKEN}.rb")
    if len(path.parts) >= 3 and path.parts[-3:] == expected:
        return [pass_check("homebrew-cask:official-layout", str(path))]
    return [
        fail_check(
            "homebrew-cask:official-layout",
            f"expected path ending in {'/'.join(expected)}, got {path}",
        )
    ]


def validate_cask_text(
    *,
    text: str,
    version: str,
    sha256: str,
    repository: str,
    homepage: str,
    minimum_macos: str,
    require_minimum_macos: bool,
) -> list[Check]:
    expected_url = (
        f"https://github.com/{repository}/releases/download/v#{{version}}/"
        f"{APP_NAME}-#{{version}}.dmg"
    )
    expected_fragments = {
        "homebrew-cask:token": f'cask "{CASK_TOKEN}" do',
        "homebrew-cask:version": f'version "{version}"',
        "homebrew-cask:sha256": f'sha256 "{sha256.lower()}"',
        "homebrew-cask:url": expected_url,
        "homebrew-cask:name": f'name "{APP_NAME}"',
        "homebrew-cask:desc": 'desc "Native macOS menu bar dictation utility"',
        "homebrew-cask:homepage": f'homepage "{homepage}"',
        "homebrew-cask:livecheck-url": "url :url",
        "homebrew-cask:livecheck-strategy": "strategy :github_latest",
        "homebrew-cask:auto-updates": "auto_updates true",
        "homebrew-cask:app": f'app "{APP_NAME}.app"',
        "homebrew-cask:uninstall-quit": 'uninstall quit: "app.holdtype.HoldType"',
        "homebrew-cask:zap": "zap trash: [",
        "homebrew-cask:zap-caches": '"~/Library/Caches/HoldType"',
        "homebrew-cask:zap-preferences": '"~/Library/Preferences/app.holdtype.HoldType.plist"',
        "homebrew-cask:zap-saved-state": '"~/Library/Saved Application State/app.holdtype.HoldType.savedState"',
    }

    checks: list[Check] = []
    for name, fragment in expected_fragments.items():
        if fragment in text:
            checks.append(pass_check(name, "present"))
        else:
            checks.append(fail_check(name, f"missing {fragment!r}"))

    forbidden_fragments = {
        "homebrew-cask:forbid-latest": "version :latest",
        "homebrew-cask:forbid-verified": "verified:",
        "homebrew-cask:forbid-no-check": "sha256 :no_check",
    }
    for name, fragment in forbidden_fragments.items():
        if fragment in text:
            checks.append(fail_check(name, f"must not use {fragment!r}"))
        else:
            checks.append(pass_check(name, "absent"))

    if minimum_macos:
        line = f'depends_on macos: "{minimum_macos}"'
        if contains_line(text, line):
            checks.append(pass_check("homebrew-cask:minimum-macos", minimum_macos))
        else:
            checks.append(fail_check("homebrew-cask:minimum-macos", f"missing {line!r}"))
    elif require_minimum_macos:
        checks.append(fail_check("homebrew-cask:minimum-macos", "missing required minimum macOS"))

    return checks


def collect_checks(
    *,
    cask_path: Path,
    version: str,
    sha256: str,
    repository: str,
    homepage: str,
    minimum_macos: str,
    require_minimum_macos: bool,
    official_layout: bool,
) -> list[Check]:
    checks: list[Check] = []
    if not cask_path.exists():
        return [fail_check("homebrew-cask:file", f"missing {cask_path}")]
    checks.append(pass_check("homebrew-cask:file", str(cask_path)))

    repository_error = validate_repository_slug(repository)
    if repository_error is not None:
        checks.append(repository_error)
    sha_error = validate_sha256(sha256)
    if sha_error is not None:
        checks.append(sha_error)
    if repository_error is not None or sha_error is not None:
        return checks

    if official_layout:
        checks.extend(validate_official_layout(cask_path))

    homepage = homepage or f"https://github.com/{repository}"
    checks.extend(
        validate_cask_text(
            text=cask_path.read_text(),
            version=version,
            sha256=sha256,
            repository=repository,
            homepage=homepage,
            minimum_macos=minimum_macos,
            require_minimum_macos=require_minimum_macos,
        )
    )
    return checks


def print_text(checks: list[Check], *, stream: object = sys.stdout) -> None:
    for check in checks:
        print(f"[{check.status}] {check.name}: {check.message}", file=stream)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cask-path", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--sha256", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--homepage", default="")
    parser.add_argument("--minimum-macos", default="")
    parser.add_argument("--require-minimum-macos", action="store_true")
    parser.add_argument("--official-layout", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args()

    checks = collect_checks(
        cask_path=Path(args.cask_path),
        version=args.version,
        sha256=args.sha256,
        repository=args.repository,
        homepage=args.homepage,
        minimum_macos=args.minimum_macos,
        require_minimum_macos=args.require_minimum_macos,
        official_layout=args.official_layout,
    )
    failures = [check for check in checks if check.status == "fail"]

    if args.json:
        print(json.dumps({"checks": [check.to_json() for check in checks]}, indent=2))
    elif args.quiet:
        if failures:
            print_text(failures, stream=sys.stderr)
    else:
        print_text(checks)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
