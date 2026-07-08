#!/usr/bin/env python3
"""Verify GitHub repository setup required before creating a release tag."""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any


REQUIRED_SECRET_NAMES = (
    "APPLE_TEAM_ID",
    "DEVELOPER_ID_CERTIFICATE_BASE64",
    "DEVELOPER_ID_CERTIFICATE_PASSWORD",
    "APP_STORE_CONNECT_KEY_ID",
    "APP_STORE_CONNECT_ISSUER_ID",
    "APP_STORE_CONNECT_PRIVATE_KEY",
    "SPARKLE_EDDSA_PRIVATE_KEY",
    "HOLDTYPE_UPDATE_FEED_URL",
    "HOLDTYPE_UPDATE_PUBLIC_ED_KEY",
)

APP_NAME = "HoldType"
CASK_TOKEN = "holdtype"
HOMEBREW_TAP_REPOSITORY_NAME = "HOMEBREW_TAP_REPOSITORY"
HOMEBREW_EXPECTED_TAP_NAME = "HOMEBREW_EXPECTED_TAP"
HOMEBREW_TAP_TOKEN_NAME = "HOMEBREW_TAP_TOKEN"
HOMEBREW_MINIMUM_MACOS_NAME = "HOMEBREW_MINIMUM_MACOS"
HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME = "HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED"
HOMEBREW_OFFICIAL_CASK_FORK_ORG_NAME = "HOMEBREW_OFFICIAL_CASK_FORK_ORG"
HOMEBREW_GITHUB_API_TOKEN_NAME = "HOMEBREW_GITHUB_API_TOKEN"
OFFICIAL_HOMEBREW_CASK_REPOSITORY = "Homebrew/homebrew-cask"
OFFICIAL_HOMEBREW_CASK_PATH = f"Casks/{CASK_TOKEN[0]}/{CASK_TOKEN}.rb"

HOMEBREW_MACOS_COMPARISON_PATTERN = re.compile(r"^(>=|>|<=|<|==) :[a-z][a-z0-9_]*$")
OFFICIAL_CASK_VERSION_PATTERN = re.compile(r'^\s*version\s+"[0-9]+(?:\.[0-9]+)*"\s*$')
OFFICIAL_CASK_SHA256_PATTERN = re.compile(r'^\s*sha256\s+"[0-9a-f]{64}"\s*$')


@dataclass(frozen=True)
class Check:
    name: str
    status: str
    message: str


def pass_check(name: str, message: str) -> Check:
    return Check(name=name, status="pass", message=message)


def warn_check(name: str, message: str) -> Check:
    return Check(name=name, status="warn", message=message)


def fail_check(name: str, message: str) -> Check:
    return Check(name=name, status="fail", message=message)


def print_checks(checks: list[Check]) -> None:
    for check in checks:
        print(f"[{check.status}] {check.name}: {check.message}")


def request_headers(token: str) -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "holdtype-release-setup-verifier",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def github_get_json(url: str, *, token: str, timeout: int) -> tuple[Any | None, Check | None]:
    request = urllib.request.Request(url, headers=request_headers(token))
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8")), None
    except urllib.error.HTTPError as error:
        try:
            body = error.read().decode("utf-8")
        except Exception:  # noqa: BLE001 - best-effort API error detail
            body = ""
        detail = f"HTTP {error.code}"
        if body:
            try:
                parsed = json.loads(body)
            except json.JSONDecodeError:
                detail = f"{detail}: {body.strip()}"
            else:
                message = parsed.get("message") if isinstance(parsed, dict) else None
                if message:
                    detail = f"{detail}: {message}"
        return None, fail_check("github-api", f"{url}: {detail}")
    except (OSError, json.JSONDecodeError) as error:
        return None, fail_check("github-api", f"{url}: {error}")


def repo_api_url(api_base_url: str, repository: str, suffix: str) -> str:
    base = api_base_url.rstrip("/")
    owner, repo = repository.split("/", 1)
    quoted_owner = urllib.parse.quote(owner, safe="")
    quoted_repo = urllib.parse.quote(repo, safe="")
    repo_url = f"{base}/repos/{quoted_owner}/{quoted_repo}"
    normalized_suffix = suffix.strip("/")
    if normalized_suffix:
        return f"{repo_url}/{normalized_suffix}"
    return repo_url


def validate_repository(repository: str, *, check_name: str = "repository") -> Check | None:
    parts = repository.split("/", 1)
    if len(parts) != 2 or not parts[0] or not parts[1] or "/" in parts[1]:
        return fail_check(check_name, f"expected OWNER/REPO, got {repository!r}")
    return None


def validate_homebrew_tap_repository_name(repository: str) -> Check | None:
    repo_name = repository.split("/", 1)[1]
    if repo_name.startswith("homebrew-") and len(repo_name) > len("homebrew-"):
        return None
    return fail_check(
        f"variable:{HOMEBREW_TAP_REPOSITORY_NAME}:repository-name",
        f"expected repository name to start with homebrew-, got {repo_name!r}",
    )


def validate_homebrew_tap_prefix(value: str) -> Check | None:
    parts = value.split("/", 1)
    if len(parts) == 2 and all(part and " " not in part and "/" not in part for part in parts):
        return None
    return fail_check(f"variable:{HOMEBREW_EXPECTED_TAP_NAME}", f"expected OWNER/TAP, got {value!r}")


def homebrew_tap_install_prefix(repository: str) -> str:
    owner, repo_name = repository.split("/", 1)
    return f"{owner}/{repo_name.removeprefix('homebrew-')}"


def extract_secret_names(payload: Any) -> set[str]:
    if not isinstance(payload, dict):
        return set()
    secrets = payload.get("secrets", [])
    if not isinstance(secrets, list):
        return set()
    names = {
        secret.get("name")
        for secret in secrets
        if isinstance(secret, dict) and isinstance(secret.get("name"), str)
    }
    return {name for name in names if name}


def extract_variables(payload: Any) -> dict[str, str]:
    if not isinstance(payload, dict):
        return {}
    variables = payload.get("variables", [])
    if not isinstance(variables, list):
        return {}

    values: dict[str, str] = {}
    for variable in variables:
        if not isinstance(variable, dict):
            continue
        name = variable.get("name")
        value = variable.get("value")
        if isinstance(name, str) and name:
            values[name] = value if isinstance(value, str) else ""
    return values


def validate_homebrew_minimum_macos(value: str) -> Check | None:
    if HOMEBREW_MACOS_COMPARISON_PATTERN.fullmatch(value):
        return None
    return fail_check(
        "variable:HOMEBREW_MINIMUM_MACOS",
        'expected a Homebrew macOS comparison expression such as ">= :tahoe"',
    )


def parse_boolean_flag(value: str) -> bool | None:
    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off", ""}:
        return False
    return None


def validate_github_owner(value: str, *, check_name: str) -> Check | None:
    if value and "/" not in value and " " not in value:
        return None
    return fail_check(check_name, f"expected a GitHub owner or organization, got {value!r}")


def check_secret_set(
    *,
    names_by_source: dict[str, set[str]],
) -> list[Check]:
    checks: list[Check] = []

    for name in REQUIRED_SECRET_NAMES:
        sources = sorted(source for source, names in names_by_source.items() if name in names)
        if sources:
            checks.append(pass_check(f"secret:{name}", f"configured in {', '.join(sources)}"))
        else:
            checks.append(fail_check(f"secret:{name}", "missing from repository/environment secrets"))
    return checks


def check_homebrew_tap_set(
    *,
    variables: dict[str, str],
    names_by_source: dict[str, set[str]],
    require_homebrew_tap: bool,
    expected_homebrew_tap: str,
) -> list[Check]:
    checks: list[Check] = []
    repository = variables.get(HOMEBREW_TAP_REPOSITORY_NAME, "")
    configured_expected_tap = variables.get(HOMEBREW_EXPECTED_TAP_NAME, "")
    effective_expected_tap = configured_expected_tap or expected_homebrew_tap
    token_sources = sorted(
        source for source, names in names_by_source.items() if HOMEBREW_TAP_TOKEN_NAME in names
    )

    if not repository and not token_sources and not require_homebrew_tap:
        return [
            warn_check(
                "homebrew-tap",
                "missing HOMEBREW_TAP_REPOSITORY variable and HOMEBREW_TAP_TOKEN secret; Homebrew tap PR will be skipped",
            )
        ]

    derived_tap = ""
    if repository:
        repository_error = validate_repository(
            repository,
            check_name=f"variable:{HOMEBREW_TAP_REPOSITORY_NAME}",
        )
        if repository_error is None:
            checks.append(pass_check(f"variable:{HOMEBREW_TAP_REPOSITORY_NAME}", repository))
            tap_name_error = validate_homebrew_tap_repository_name(repository)
            if tap_name_error is None:
                derived_tap = homebrew_tap_install_prefix(repository)
                checks.append(
                    pass_check(
                        f"variable:{HOMEBREW_TAP_REPOSITORY_NAME}:tap-name",
                        derived_tap,
                    )
                )
            else:
                checks.append(tap_name_error)
        else:
            checks.append(repository_error)
    else:
        checks.append(
            fail_check(
                f"variable:{HOMEBREW_TAP_REPOSITORY_NAME}",
                "missing from repository variables",
            )
        )

    if configured_expected_tap:
        expected_error = validate_homebrew_tap_prefix(configured_expected_tap)
        if expected_error is not None:
            checks.append(expected_error)
        elif expected_homebrew_tap and configured_expected_tap != expected_homebrew_tap:
            checks.append(
                fail_check(
                    f"variable:{HOMEBREW_EXPECTED_TAP_NAME}",
                    f"expected {expected_homebrew_tap}, got {configured_expected_tap}",
                )
            )
        elif derived_tap and configured_expected_tap != derived_tap:
            checks.append(
                fail_check(
                    f"variable:{HOMEBREW_EXPECTED_TAP_NAME}",
                    f"expected {configured_expected_tap}, but {repository} installs as {derived_tap}",
                )
            )
        else:
            checks.append(pass_check(f"variable:{HOMEBREW_EXPECTED_TAP_NAME}", configured_expected_tap))
    elif require_homebrew_tap or repository or token_sources:
        checks.append(
            fail_check(
                f"variable:{HOMEBREW_EXPECTED_TAP_NAME}",
                "missing from repository variables",
            )
        )
    elif effective_expected_tap:
        expected_error = validate_homebrew_tap_prefix(effective_expected_tap)
        if expected_error is not None:
            checks.append(expected_error)
        else:
            checks.append(pass_check("expected-homebrew-tap", effective_expected_tap))

    if token_sources:
        checks.append(
            pass_check(
                f"secret:{HOMEBREW_TAP_TOKEN_NAME}",
                f"configured in {', '.join(token_sources)}",
            )
        )
    else:
        checks.append(
            fail_check(
                f"secret:{HOMEBREW_TAP_TOKEN_NAME}",
                "missing from repository/environment secrets",
            )
        )
    return checks


def check_variable_set(
    *,
    variables: dict[str, str],
    require_homebrew_minimum_macos: bool,
) -> list[Check]:
    checks: list[Check] = []
    name = HOMEBREW_MINIMUM_MACOS_NAME
    if name in variables:
        value = variables[name]
        value_error = validate_homebrew_minimum_macos(value)
        if value_error is not None:
            checks.append(value_error)
        else:
            checks.append(pass_check(f"variable:{name}", value))
    elif require_homebrew_minimum_macos:
        checks.append(fail_check(f"variable:{name}", "missing from repository variables"))
    else:
        checks.append(
            warn_check(
                f"variable:{name}",
                "missing; official Homebrew cask submission bundle will be skipped",
            )
        )
    return checks


def check_official_homebrew_cask_bump_set(
    *,
    variables: dict[str, str],
    names_by_source: dict[str, set[str]],
    require_official_bump: bool,
) -> list[Check]:
    enabled_value = variables.get(HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME, "")
    token_sources = sorted(
        source
        for source, names in names_by_source.items()
        if HOMEBREW_GITHUB_API_TOKEN_NAME in names
    )
    enabled = parse_boolean_flag(enabled_value)
    checks: list[Check] = []

    if enabled is None:
        checks.append(
            fail_check(
                f"variable:{HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME}",
                "expected true or false",
            )
        )
        return checks

    if not enabled:
        if require_official_bump:
            checks.append(
                fail_check(
                    f"variable:{HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME}",
                    "missing or disabled",
                )
            )
        else:
            checks.append(
                warn_check(
                    "homebrew-official-cask-bump",
                    "disabled; official Homebrew Cask bump PR will be skipped",
                )
            )
        return checks

    checks.append(pass_check(f"variable:{HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME}", "true"))
    if token_sources:
        checks.append(
            pass_check(
                f"secret:{HOMEBREW_GITHUB_API_TOKEN_NAME}",
                f"configured in {', '.join(token_sources)}",
            )
        )
    else:
        checks.append(
            fail_check(
                f"secret:{HOMEBREW_GITHUB_API_TOKEN_NAME}",
                "missing from repository/environment secrets",
            )
        )

    fork_org = variables.get(HOMEBREW_OFFICIAL_CASK_FORK_ORG_NAME, "")
    if fork_org:
        owner_error = validate_github_owner(
            fork_org,
            check_name=f"variable:{HOMEBREW_OFFICIAL_CASK_FORK_ORG_NAME}",
        )
        if owner_error is None:
            checks.append(pass_check(f"variable:{HOMEBREW_OFFICIAL_CASK_FORK_ORG_NAME}", fork_org))
        else:
            checks.append(owner_error)
    return checks


def decode_github_content(payload: dict[str, Any]) -> tuple[str, Check | None]:
    encoding = payload.get("encoding")
    content = payload.get("content")
    if encoding != "base64" or not isinstance(content, str) or not content:
        return "", fail_check("github-official-cask:content", "missing base64 file content")

    try:
        decoded = base64.b64decode("".join(content.split()), validate=True)
        return decoded.decode("utf-8"), None
    except (binascii.Error, UnicodeDecodeError) as error:
        return "", fail_check("github-official-cask:content", f"could not decode file content: {error}")


def contains_line_matching(text: str, pattern: re.Pattern[str]) -> bool:
    return any(pattern.fullmatch(line) for line in text.splitlines())


def check_official_homebrew_cask_text(
    text: str,
    *,
    expected_repository: str,
) -> list[Check]:
    expected_url = (
        f"https://github.com/{expected_repository}/releases/download/v#{{version}}/"
        f"{APP_NAME}-#{{version}}.dmg"
    )
    expected_fragments = {
        "github-official-cask:token": f'cask "{CASK_TOKEN}" do',
        "github-official-cask:url": expected_url,
        "github-official-cask:name": f'name "{APP_NAME}"',
        "github-official-cask:desc": 'desc "Native macOS menu bar dictation utility"',
        "github-official-cask:homepage": f'homepage "https://github.com/{expected_repository}"',
        "github-official-cask:livecheck-url": "url :url",
        "github-official-cask:livecheck-strategy": "strategy :github_latest",
        "github-official-cask:auto-updates": "auto_updates true",
        "github-official-cask:app": f'app "{APP_NAME}.app"',
        "github-official-cask:uninstall-quit": 'uninstall quit: "app.holdtype.HoldType"',
        "github-official-cask:zap": "zap trash: [",
        "github-official-cask:zap-caches": '"~/Library/Caches/HoldType"',
        "github-official-cask:zap-preferences": '"~/Library/Preferences/app.holdtype.HoldType.plist"',
        "github-official-cask:zap-saved-state": (
            '"~/Library/Saved Application State/app.holdtype.HoldType.savedState"'
        ),
    }

    checks: list[Check] = []
    for name, fragment in expected_fragments.items():
        if fragment in text:
            checks.append(pass_check(name, "present"))
        else:
            checks.append(fail_check(name, f"missing {fragment!r}"))

    if contains_line_matching(text, OFFICIAL_CASK_VERSION_PATTERN):
        checks.append(pass_check("github-official-cask:version", "pinned"))
    else:
        checks.append(fail_check("github-official-cask:version", "missing pinned numeric version"))

    if contains_line_matching(text, OFFICIAL_CASK_SHA256_PATTERN):
        checks.append(pass_check("github-official-cask:sha256", "pinned"))
    else:
        checks.append(fail_check("github-official-cask:sha256", "missing pinned SHA-256"))

    forbidden_fragments = {
        "github-official-cask:forbid-latest": "version :latest",
        "github-official-cask:forbid-no-check": "sha256 :no_check",
    }
    for name, fragment in forbidden_fragments.items():
        if fragment in text:
            checks.append(fail_check(name, f"must not use {fragment!r}"))
        else:
            checks.append(pass_check(name, "absent"))

    return checks


def check_official_homebrew_cask_file(
    payload: Any,
    *,
    expected_repository: str,
) -> list[Check]:
    if not isinstance(payload, dict):
        return [fail_check("github-official-cask", "API response is not an object")]

    checks: list[Check] = []
    path = payload.get("path")
    if path == OFFICIAL_HOMEBREW_CASK_PATH:
        checks.append(pass_check("github-official-cask:path", OFFICIAL_HOMEBREW_CASK_PATH))
    else:
        checks.append(
            fail_check(
                "github-official-cask:path",
                f"expected {OFFICIAL_HOMEBREW_CASK_PATH}, got {path!r}",
            )
        )

    content_type = payload.get("type")
    if content_type == "file":
        checks.append(pass_check("github-official-cask:type", "file"))
    else:
        checks.append(
            fail_check("github-official-cask:type", f"expected file, got {content_type!r}")
        )

    text, content_error = decode_github_content(payload)
    if content_error is not None:
        checks.append(content_error)
        return checks
    checks.append(pass_check("github-official-cask:content", "decoded"))

    checks.extend(check_official_homebrew_cask_text(text, expected_repository=expected_repository))
    return checks


def check_homebrew_tap_repository(
    *,
    payload: Any,
    expected_repository: str,
) -> list[Check]:
    if not isinstance(payload, dict):
        return [fail_check("github-tap-repository", "API response is not an object")]

    checks: list[Check] = []
    full_name = payload.get("full_name")
    if full_name == expected_repository:
        checks.append(pass_check("github-tap-repository:name", expected_repository))
    else:
        checks.append(
            fail_check(
                "github-tap-repository:name",
                f"expected {expected_repository}, got {full_name!r}",
            )
        )

    private = payload.get("private")
    if private is False:
        checks.append(pass_check("github-tap-repository:visibility", "public"))
    else:
        checks.append(
            fail_check(
                "github-tap-repository:visibility",
                f"expected public repository, got private={private!r}",
            )
        )

    archived = payload.get("archived")
    if archived is False:
        checks.append(pass_check("github-tap-repository:archived", "false"))
    elif archived is True:
        checks.append(fail_check("github-tap-repository:archived", "tap repository is archived"))
    else:
        checks.append(warn_check("github-tap-repository:archived", f"unexpected value {archived!r}"))

    default_branch = payload.get("default_branch")
    if isinstance(default_branch, str) and default_branch:
        checks.append(pass_check("github-tap-repository:default-branch", default_branch))
    else:
        checks.append(warn_check("github-tap-repository:default-branch", "missing from API response"))
    return checks


def check_pages(payload: Any, expected_appcast_url: str) -> list[Check]:
    if not isinstance(payload, dict):
        return [fail_check("github-pages", "API response is not an object")]

    checks: list[Check] = []
    html_url = payload.get("html_url")
    if isinstance(html_url, str) and html_url:
        checks.append(pass_check("github-pages:url", html_url))
    else:
        checks.append(fail_check("github-pages:url", "missing html_url"))

    status = payload.get("status")
    if status in {"built", "building"}:
        checks.append(pass_check("github-pages:status", str(status)))
    else:
        checks.append(warn_check("github-pages:status", f"unexpected status {status!r}"))

    build_type = payload.get("build_type")
    if build_type == "workflow":
        checks.append(pass_check("github-pages:build_type", "workflow"))
    elif build_type is None:
        checks.append(warn_check("github-pages:build_type", "missing from API response; confirm Actions source in UI"))
    else:
        checks.append(fail_check("github-pages:build_type", f"expected workflow, got {build_type!r}"))

    https_enforced = payload.get("https_enforced")
    if https_enforced is True:
        checks.append(pass_check("github-pages:https_enforced", "true"))
    else:
        checks.append(warn_check("github-pages:https_enforced", f"expected true, got {https_enforced!r}"))

    if expected_appcast_url and isinstance(html_url, str) and html_url:
        expected_prefix = f"{html_url.rstrip('/')}/"
        if expected_appcast_url.startswith(expected_prefix):
            checks.append(pass_check("github-pages:appcast-url", expected_appcast_url))
        else:
            checks.append(
                warn_check(
                    "github-pages:appcast-url",
                    f"{expected_appcast_url} does not start with {expected_prefix}",
                )
            )
    return checks


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", default=os.environ.get("GITHUB_REPOSITORY", ""))
    parser.add_argument("--environment", default="github-pages")
    parser.add_argument("--github-api-url", default=os.environ.get("GITHUB_API_URL", "https://api.github.com"))
    parser.add_argument("--github-token-env", default="GITHUB_TOKEN")
    parser.add_argument("--appcast-url", default=os.environ.get("HOLDTYPE_UPDATE_FEED_URL", ""))
    parser.add_argument(
        "--expected-homebrew-tap",
        default=os.environ.get(HOMEBREW_EXPECTED_TAP_NAME, ""),
        help="Expected user-facing tap prefix such as holdtype/tap",
    )
    parser.add_argument("--require-homebrew-tap", action="store_true")
    parser.add_argument("--require-homebrew-minimum-macos", action="store_true")
    parser.add_argument(
        "--require-official-homebrew-cask",
        action="store_true",
        help="require the short `brew install --cask holdtype` upstream cask to exist",
    )
    parser.add_argument("--require-official-homebrew-cask-bump", action="store_true")
    parser.add_argument("--skip-pages", action="store_true")
    parser.add_argument("--timeout", type=int, default=30)
    parser.add_argument("--strict", action="store_true", help="treat warnings as failures")
    args = parser.parse_args()

    checks: list[Check] = []
    if not args.repository:
        checks.append(fail_check("repository", "missing --repository or GITHUB_REPOSITORY"))
    else:
        repository_error = validate_repository(args.repository)
        if repository_error is not None:
            checks.append(repository_error)
    token = os.environ.get(args.github_token_env, "")
    if not token:
        checks.append(fail_check("github-token", f"missing ${args.github_token_env}"))
    if checks:
        print_checks(checks)
        return 1

    repo_secrets_url = repo_api_url(
        args.github_api_url,
        args.repository,
        "actions/secrets?per_page=100",
    )
    repo_secrets, error = github_get_json(repo_secrets_url, token=token, timeout=args.timeout)
    if error is not None:
        checks.append(error)
        print_checks(checks)
        return 1
    names_by_source = {"repository": extract_secret_names(repo_secrets)}
    checks.append(pass_check("github-secrets:repository", f"{len(names_by_source['repository'])} secrets visible"))

    repo_variables_url = repo_api_url(
        args.github_api_url,
        args.repository,
        "actions/variables?per_page=100",
    )
    variables: dict[str, str] = {}
    repo_variables, variables_error = github_get_json(repo_variables_url, token=token, timeout=args.timeout)
    if variables_error is None:
        variables = extract_variables(repo_variables)
        checks.append(pass_check("github-variables:repository", f"{len(variables)} variables visible"))
        checks.extend(
            check_variable_set(
                variables=variables,
                require_homebrew_minimum_macos=args.require_homebrew_minimum_macos,
            )
        )
    else:
        if args.require_homebrew_minimum_macos:
            checks.append(fail_check("github-variables:repository", variables_error.message))
        else:
            checks.append(warn_check("github-variables:repository", variables_error.message))

    if args.environment:
        env_name = urllib.parse.quote(args.environment, safe="")
        env_secrets_url = repo_api_url(
            args.github_api_url,
            args.repository,
            f"environments/{env_name}/secrets?per_page=100",
        )
        env_secrets, env_error = github_get_json(env_secrets_url, token=token, timeout=args.timeout)
        if env_error is None:
            names_by_source[f"environment:{args.environment}"] = extract_secret_names(env_secrets)
            checks.append(
                pass_check(
                    f"github-secrets:environment:{args.environment}",
                    f"{len(names_by_source[f'environment:{args.environment}'])} secrets visible",
                )
            )
        else:
            checks.append(warn_check(f"github-secrets:environment:{args.environment}", env_error.message))

    checks.extend(check_secret_set(names_by_source=names_by_source))
    checks.extend(
        check_homebrew_tap_set(
            variables=variables,
            names_by_source=names_by_source,
            require_homebrew_tap=args.require_homebrew_tap,
            expected_homebrew_tap=args.expected_homebrew_tap,
        )
    )
    checks.extend(
        check_official_homebrew_cask_bump_set(
            variables=variables,
            names_by_source=names_by_source,
            require_official_bump=args.require_official_homebrew_cask_bump,
        )
    )

    official_bump_enabled = (
        parse_boolean_flag(variables.get(HOMEBREW_OFFICIAL_CASK_BUMP_ENABLED_NAME, "")) is True
    )
    if args.require_official_homebrew_cask or official_bump_enabled:
        official_cask_url = repo_api_url(
            args.github_api_url,
            OFFICIAL_HOMEBREW_CASK_REPOSITORY,
            f"contents/{OFFICIAL_HOMEBREW_CASK_PATH}?ref=main",
        )
        official_cask, official_cask_error = github_get_json(
            official_cask_url,
            token=token,
            timeout=args.timeout,
        )
        if official_cask_error is None:
            checks.extend(
                check_official_homebrew_cask_file(
                    official_cask,
                    expected_repository=args.repository,
                )
            )
        else:
            checks.append(fail_check("github-official-cask", official_cask_error.message))

    tap_repository = variables.get(HOMEBREW_TAP_REPOSITORY_NAME, "")
    if tap_repository and validate_repository(tap_repository) is None:
        tap_url = repo_api_url(args.github_api_url, tap_repository, "")
        tap_payload, tap_error = github_get_json(tap_url, token=token, timeout=args.timeout)
        if tap_error is None:
            checks.extend(
                check_homebrew_tap_repository(
                    payload=tap_payload,
                    expected_repository=tap_repository,
                )
            )
        elif args.require_homebrew_tap:
            checks.append(fail_check("github-tap-repository", tap_error.message))
        else:
            checks.append(warn_check("github-tap-repository", tap_error.message))

    if not args.skip_pages:
        pages_url = repo_api_url(args.github_api_url, args.repository, "pages")
        pages, pages_error = github_get_json(pages_url, token=token, timeout=args.timeout)
        if pages_error is not None:
            checks.append(fail_check("github-pages", pages_error.message))
        else:
            checks.extend(check_pages(pages, args.appcast_url))

    print_checks(checks)
    has_failures = any(check.status == "fail" for check in checks)
    has_warnings = any(check.status == "warn" for check in checks)
    return 1 if has_failures or (args.strict and has_warnings) else 0


if __name__ == "__main__":
    raise SystemExit(main())
