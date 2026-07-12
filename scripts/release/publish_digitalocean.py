#!/usr/bin/env python3
"""Force and verify a HoldType App Platform static-site deployment."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Sequence
from pathlib import Path
from typing import Any


DEFAULT_APP_NAME = "holdtype"
DEFAULT_MARKER = 'data-site-locale="en"'
REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_APP_SPEC = REPOSITORY_ROOT / ".do" / "app.yaml"
LOCALE_ROUTES = (
    ("", "en"),
    ("es/", "es"),
    ("de/", "de"),
    ("fr/", "fr"),
    ("pt-br/", "pt-BR"),
    ("ja/", "ja"),
    ("zh-hans/", "zh-Hans"),
    ("ko/", "ko"),
    ("ru/", "ru"),
    ("ar/", "ar"),
)


class PublishError(RuntimeError):
    """Raised when a deployment cannot be completed or verified."""


def parse_json(text: str, *, command: Sequence[str]) -> Any:
    try:
        return json.loads(text)
    except json.JSONDecodeError as error:
        rendered = " ".join(command)
        raise PublishError(f"{rendered} returned invalid JSON: {error}") from error


def objects(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        return [payload]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def find_app_id(payload: Any, app_name: str) -> str:
    matches: list[str] = []
    for app in objects(payload):
        spec = app.get("spec")
        name = spec.get("name") if isinstance(spec, dict) else app.get("name")
        app_id = app.get("id")
        if name == app_name and isinstance(app_id, str) and app_id:
            matches.append(app_id)

    if not matches:
        raise PublishError(f"DigitalOcean app {app_name!r} was not found")
    if len(matches) > 1:
        raise PublishError(f"DigitalOcean app name {app_name!r} is not unique")
    return matches[0]


def deployment_id_and_phase(payload: Any) -> tuple[str | None, str | None]:
    candidates = objects(payload)
    if not candidates:
        return None, None
    candidate = candidates[0]
    app = candidate.get("app", candidate)
    if isinstance(app, dict) and isinstance(app.get("active_deployment"), dict):
        deployment = app["active_deployment"]
    else:
        deployment = candidate.get("deployment", candidate)
    if not isinstance(deployment, dict):
        return None, None
    deployment_id = deployment.get("id")
    phase = deployment.get("phase") or deployment.get("status")
    return (
        deployment_id if isinstance(deployment_id, str) else None,
        phase.upper() if isinstance(phase, str) else None,
    )


def default_ingress_url(payload: Any) -> str:
    candidates = objects(payload)
    if not candidates:
        raise PublishError("DigitalOcean app details are empty")
    app = candidates[0].get("app", candidates[0])
    if not isinstance(app, dict):
        raise PublishError("DigitalOcean app details have an unexpected shape")

    ingress = app.get("default_ingress")
    if isinstance(ingress, str) and ingress:
        hostname = ingress
    elif isinstance(ingress, dict):
        hostname = ingress.get("hostname") or ingress.get("domain")
    else:
        hostname = None

    if not isinstance(hostname, str) or not hostname:
        for key in ("live_url", "live_url_base"):
            value = app.get(key)
            if isinstance(value, str) and value:
                return value.rstrip("/") + "/"
        raise PublishError("DigitalOcean app does not report a default ingress")
    if "://" not in hostname:
        hostname = f"https://{hostname}"
    return hostname.rstrip("/") + "/"


def run_doctl(doctl: str, arguments: Sequence[str], *, timeout: float) -> Any:
    command = [doctl, *arguments, "--output", "json"]
    try:
        result = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
            timeout=max(1.0, timeout),
        )
    except subprocess.TimeoutExpired as error:
        raise PublishError(f"{' '.join(command)} timed out") from error
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "unknown error"
        raise PublishError(f"{' '.join(command)} failed: {detail}")
    return parse_json(result.stdout, command=command)


def remaining(deadline: float) -> float:
    value = deadline - time.monotonic()
    if value <= 0:
        raise PublishError("DigitalOcean publish timed out")
    return value


def cache_bust(url: str, deployment_id: str | None) -> str:
    if not deployment_id:
        return url
    parts = urllib.parse.urlsplit(url)
    query = urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
    query.append(("deployment", deployment_id))
    return urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, parts.path, urllib.parse.urlencode(query), parts.fragment)
    )


def verification_targets(
    base_url: str,
    *,
    deployment_id: str | None,
    root_marker: str,
) -> list[dict[str, Any]]:
    normalized_base = base_url.rstrip("/") + "/"
    targets: list[dict[str, Any]] = []
    for route, locale in LOCALE_ROUTES:
        url = urllib.parse.urljoin(normalized_base, route)
        required = [f'data-site-locale="{locale}"']
        forbidden: list[str] = []
        if not route:
            required.append(root_marker)
            forbidden.append("data-i18n")
        targets.append(
            {
                "label": f"/{route}",
                "url": cache_bust(url, deployment_id),
                "required": required,
                "forbidden": forbidden,
            }
        )
    targets.append(
        {
            "label": "/sitemap.xml",
            "url": cache_bust(
                urllib.parse.urljoin(normalized_base, "sitemap.xml"), deployment_id
            ),
            "required": ["<loc>https://holdtype.app/ru/</loc>"],
            "forbidden": [],
        }
    )
    return targets


def verify_landing(
    url: str,
    *,
    required_markers: Sequence[str],
    forbidden_markers: Sequence[str] = (),
    deadline: float,
    request_timeout: float,
    retry_delay: float = 5.0,
) -> None:
    required = [marker.encode("utf-8") for marker in required_markers]
    forbidden = [marker.encode("utf-8") for marker in forbidden_markers]
    last_error = "no response"
    while True:
        attempt_timeout = min(request_timeout, remaining(deadline))
        try:
            request = urllib.request.Request(
                url,
                headers={"User-Agent": "HoldType-publish-verifier/1"},
            )
            with urllib.request.urlopen(request, timeout=attempt_timeout) as response:
                body = response.read()
            missing = [marker.decode("utf-8") for marker in required if marker not in body]
            present = [marker.decode("utf-8") for marker in forbidden if marker in body]
            if not missing and not present:
                return
            details: list[str] = []
            if missing:
                details.append(f"missing {missing!r}")
            if present:
                details.append(f"contains forbidden {present!r}")
            last_error = "; ".join(details)
        except (OSError, urllib.error.URLError) as error:
            last_error = str(error)

        wait = min(retry_delay, remaining(deadline))
        if wait <= 0:
            break
        time.sleep(wait)

    raise PublishError(f"landing verification failed for {url}: {last_error}")


def verify_public_site(
    base_url: str,
    *,
    deployment_id: str | None,
    root_marker: str,
    deadline: float,
    request_timeout: float,
) -> None:
    for target in verification_targets(
        base_url,
        deployment_id=deployment_id,
        root_marker=root_marker,
    ):
        print(f"Verifying {target['label']} at {target['url']}...")
        verify_landing(
            target["url"],
            required_markers=target["required"],
            forbidden_markers=target["forbidden"],
            deadline=deadline,
            request_timeout=request_timeout,
        )


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(
        description="Force a DigitalOcean App Platform rebuild and verify the landing page."
    )
    result.add_argument("--app-id", default=os.environ.get("DIGITALOCEAN_APP_ID"))
    result.add_argument("--app-name", default=DEFAULT_APP_NAME)
    result.add_argument(
        "--spec",
        type=Path,
        default=DEFAULT_APP_SPEC,
        help="App Platform spec to synchronize before deployment",
    )
    result.add_argument(
        "--url",
        help="additional public URL to verify after the technical App Platform URL",
    )
    result.add_argument("--marker", default=DEFAULT_MARKER)
    result.add_argument("--timeout", type=float, default=600.0)
    result.add_argument("--request-timeout", type=float, default=20.0)
    result.add_argument("--doctl", default="doctl")
    result.add_argument("--dry-run", action="store_true")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    arguments = parser().parse_args(argv)
    if arguments.timeout <= 0 or arguments.request_timeout <= 0:
        raise PublishError("timeouts must be positive")

    app_spec = arguments.spec.resolve()
    if not app_spec.is_file():
        raise PublishError(f"DigitalOcean app spec not found: {app_spec}")

    doctl = shutil.which(arguments.doctl)
    if not doctl:
        raise PublishError(f"{arguments.doctl!r} is not installed")

    if arguments.dry_run:
        app_id = arguments.app_id or f"<app named {arguments.app_name}>"
        print(
            "DRY RUN:",
            doctl,
            "apps update",
            app_id,
            "--spec",
            app_spec,
            "--update-sources --wait --output json",
        )
        print("DRY RUN: verify 10 locale routes and sitemap at <DigitalOcean technical URL>")
        if arguments.url:
            print("DRY RUN: verify", arguments.url)
        return 0

    deadline = time.monotonic() + arguments.timeout
    app_id = arguments.app_id
    if not app_id:
        apps = run_doctl(doctl, ["apps", "list"], timeout=remaining(deadline))
        app_id = find_app_id(apps, arguments.app_name)

    print(f"Synchronizing and deploying DigitalOcean app {app_id} from {app_spec}...")
    run_doctl(
        doctl,
        [
            "apps",
            "update",
            app_id,
            "--spec",
            str(app_spec),
            "--update-sources",
            "--wait",
        ],
        timeout=remaining(deadline),
    )

    app = run_doctl(doctl, ["apps", "get", app_id], timeout=remaining(deadline))
    deployment_id, phase = deployment_id_and_phase(app)
    if phase != "ACTIVE":
        raise PublishError(
            f"deployment {deployment_id or '<unknown>'} finished as {phase or '<unknown>'}"
        )

    technical_url = default_ingress_url(app)
    urls = [technical_url]
    if arguments.url:
        public_url = arguments.url.rstrip("/") + "/"
        if public_url != technical_url:
            urls.append(public_url)

    for verify_url in urls:
        verify_public_site(
            verify_url,
            deployment_id=deployment_id,
            root_marker=arguments.marker,
            deadline=deadline,
            request_timeout=arguments.request_timeout,
        )
    print("Published and verified:", ", ".join(urls))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PublishError as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
