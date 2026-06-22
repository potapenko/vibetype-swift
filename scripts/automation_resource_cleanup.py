#!/usr/bin/env python3
"""Clean up stale Codex automation helper processes.

This script is deliberately narrow. It targets Codex helper/MCP processes that
scheduled automation runs commonly leave behind. It does not target arbitrary
Node.js processes, the main Codex app, product apps, databases, storage tools,
or repository files.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


DEFAULT_MIN_AGE_SECONDS = 60
DEFAULT_GRACE_SECONDS = 2
DEFAULT_PS_TIMEOUT_SECONDS = 30

PROCESS_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    (
        "computer_use_client",
        re.compile(r"Codex Computer Use\.app/.*/SkyComputerUseClient .* mcp"),
    ),
    (
        "computer_use_service",
        re.compile(r"\.codex/computer-use/Codex Computer Use\.app/.*/SkyComputerUseService"),
    ),
    ("playwright_mcp_npm", re.compile(r"npm exec @playwright/mcp@latest")),
    ("playwright_mcp_node", re.compile(r"node .*/playwright-mcp(\s|$)")),
    ("xcodebuildmcp_npm", re.compile(r"npm exec xcodebuildmcp@latest mcp")),
    ("xcodebuildmcp_node", re.compile(r"node .*/xcodebuildmcp mcp(\s|$)")),
    ("browser_mcp", re.compile(r"node \./mcp/server\.mjs --stdio")),
    ("codex_node_repl", re.compile(r"/cua_node/bin/node_repl(\s|$)")),
    (
        "pencil_mcp",
        re.compile(r"mcp-server-darwin-arm64 --app desktop"),
    ),
)


@dataclass(frozen=True)
class ProcessInfo:
    owner: str
    pid: int
    ppid: int
    pgid: int
    etimes: int
    rss_kb: int
    pcpu: float
    command: str


@dataclass(frozen=True)
class CleanupCandidate:
    owner: str
    pid: int
    ppid: int
    pgid: int
    etimes: int
    rss_kb: int
    pcpu: float
    kind: str
    command: str
    reason: str


def parse_elapsed_seconds(value: str) -> int:
    if value.isdigit():
        return int(value)

    days = 0
    time_part = value
    if "-" in value:
        day_part, time_part = value.split("-", 1)
        days = int(day_part)

    pieces = [int(piece) for piece in time_part.split(":")]
    if len(pieces) == 3:
        hours, minutes, seconds = pieces
    elif len(pieces) == 2:
        hours = 0
        minutes, seconds = pieces
    else:
        raise ValueError(f"unsupported elapsed time: {value}")
    return days * 24 * 60 * 60 + hours * 60 * 60 + minutes * 60 + seconds


def parse_ps_output(output: str) -> list[ProcessInfo]:
    processes: list[ProcessInfo] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(None, 7)
        if len(parts) < 8:
            continue
        owner, pid_s, ppid_s, pgid_s, elapsed_s, rss_s, pcpu_s, command = parts
        try:
            processes.append(
                ProcessInfo(
                    owner=owner,
                    pid=int(pid_s),
                    ppid=int(ppid_s),
                    pgid=int(pgid_s),
                    etimes=parse_elapsed_seconds(elapsed_s),
                    rss_kb=int(rss_s),
                    pcpu=float(pcpu_s),
                    command=command,
                )
            )
        except ValueError:
            continue
    return processes


def run_ps(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        check=False,
        text=True,
        timeout=DEFAULT_PS_TIMEOUT_SECONDS,
    )


def read_processes() -> list[ProcessInfo]:
    completed = run_ps(
        ["ps", "-axo", "user=,pid=,ppid=,pgid=,etime=,rss=,pcpu=,command="]
    )
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "ps failed")
    return parse_ps_output(completed.stdout)


def match_process_kind(command: str) -> str | None:
    for kind, pattern in PROCESS_PATTERNS:
        if pattern.search(command):
            return kind
    return None


def protected_pids() -> set[int]:
    pids = {os.getpid(), os.getppid()}
    parent = os.getppid()
    for _ in range(16):
        try:
            output = subprocess.check_output(
                ["ps", "-o", "ppid=", "-p", str(parent)],
                text=True,
                timeout=DEFAULT_PS_TIMEOUT_SECONDS,
            )
        except (subprocess.SubprocessError, ValueError):
            break
        value = output.strip()
        if not value:
            break
        try:
            parent = int(value)
        except ValueError:
            break
        if parent <= 1 or parent in pids:
            break
        pids.add(parent)
    return pids


def select_candidates(
    processes: list[ProcessInfo],
    *,
    owners: set[str],
    min_age_seconds: int,
    protected: set[int] | None = None,
) -> list[CleanupCandidate]:
    protected_set = protected_pids() if protected is None else protected
    candidates: list[CleanupCandidate] = []
    for process in processes:
        if process.owner not in owners:
            continue
        if process.pid in protected_set:
            continue
        kind = match_process_kind(process.command)
        if kind is None:
            continue
        if process.etimes < min_age_seconds:
            continue
        candidates.append(
            CleanupCandidate(
                owner=process.owner,
                pid=process.pid,
                ppid=process.ppid,
                pgid=process.pgid,
                etimes=process.etimes,
                rss_kb=process.rss_kb,
                pcpu=process.pcpu,
                kind=kind,
                command=process.command,
                reason=f"allowlisted stale {kind} helper older than {min_age_seconds}s",
            )
        )
    return sorted(candidates, key=lambda candidate: (candidate.owner, candidate.pid))


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def owners_requiring_operator(owners: set[str], current_user: str) -> set[str]:
    if os.geteuid() == 0:
        return set()
    return {owner for owner in owners if owner != current_user}


def operator_command(owner: str, min_age_seconds: int, script_path: Path) -> str:
    return (
        f"sudo -u {owner} python3 {script_path} --apply --owner {owner} "
        f"--min-age-seconds {min_age_seconds} --json"
    )


def terminate_candidates(
    candidates: list[CleanupCandidate],
    *,
    apply: bool,
    grace_seconds: int,
    current_user: str,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "matched": [asdict(candidate) for candidate in candidates],
        "terminated": [],
        "errors": [],
        "remaining": [],
        "permission_required": [],
    }
    if not apply:
        return result

    blocked_owners = owners_requiring_operator(
        {candidate.owner for candidate in candidates},
        current_user,
    )
    for candidate in candidates:
        if candidate.owner in blocked_owners:
            result["permission_required"].append(asdict(candidate))
            continue
        try:
            os.kill(candidate.pid, signal.SIGTERM)
            result["terminated"].append({"pid": candidate.pid, "signal": "TERM"})
        except ProcessLookupError:
            result["terminated"].append(
                {"pid": candidate.pid, "signal": "already_exited"}
            )
        except PermissionError as exc:
            result["errors"].append({"pid": candidate.pid, "error": str(exc)})

    deadline = time.monotonic() + max(0, grace_seconds)
    killable = [candidate for candidate in candidates if candidate.owner not in blocked_owners]
    while time.monotonic() < deadline:
        if not any(process_exists(candidate.pid) for candidate in killable):
            break
        time.sleep(0.2)

    for candidate in killable:
        if not process_exists(candidate.pid):
            continue
        try:
            os.kill(candidate.pid, signal.SIGKILL)
            result["terminated"].append({"pid": candidate.pid, "signal": "KILL"})
        except ProcessLookupError:
            result["terminated"].append(
                {"pid": candidate.pid, "signal": "already_exited"}
            )
        except PermissionError as exc:
            result["errors"].append({"pid": candidate.pid, "error": str(exc)})

    for candidate in candidates:
        if process_exists(candidate.pid):
            result["remaining"].append(asdict(candidate))
    return result


def cleanup(
    *,
    owners: set[str],
    apply: bool,
    min_age_seconds: int,
    grace_seconds: int,
    script_path: Path,
) -> dict[str, Any]:
    current_user = getpass.getuser()
    processes = read_processes()
    candidates = select_candidates(
        processes,
        owners=owners,
        min_age_seconds=min_age_seconds,
    )
    process_result = terminate_candidates(
        candidates,
        apply=apply,
        grace_seconds=grace_seconds,
        current_user=current_user,
    )
    permission_owners = sorted(
        {candidate["owner"] for candidate in process_result["permission_required"]}
    )
    return {
        "mode": "apply" if apply else "dry_run",
        "current_user": current_user,
        "owners": sorted(owners),
        "min_age_seconds": min_age_seconds,
        "grace_seconds": grace_seconds,
        "processes": process_result,
        "operator_commands": [
            operator_command(owner, min_age_seconds, script_path)
            for owner in permission_owners
        ],
        "ok": not process_result["errors"]
        and (not apply or (not process_result["remaining"] and not permission_owners)),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Clean stale Codex automation helpers.")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="terminate matched allowlisted helper processes",
    )
    parser.add_argument(
        "--owner",
        action="append",
        help="process owner to inspect; defaults to the current user",
    )
    parser.add_argument(
        "--min-age-seconds",
        type=int,
        default=DEFAULT_MIN_AGE_SECONDS,
        help="minimum process age before it may be terminated",
    )
    parser.add_argument(
        "--grace-seconds",
        type=int,
        default=DEFAULT_GRACE_SECONDS,
        help="seconds to wait after TERM before KILL",
    )
    parser.add_argument("--json", action="store_true", help="print JSON report")
    args = parser.parse_args()

    owners = set(args.owner or [getpass.getuser()])
    script_path = Path(__file__).resolve()
    try:
        result = cleanup(
            owners=owners,
            apply=args.apply,
            min_age_seconds=args.min_age_seconds,
            grace_seconds=args.grace_seconds,
            script_path=script_path,
        )
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        result = {
            "mode": "apply" if args.apply else "dry_run",
            "owners": sorted(owners),
            "ok": False,
            "error": str(exc),
        }
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(f"automation resource cleanup failed: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        matched = len(result["processes"]["matched"])
        remaining = len(result["processes"]["remaining"])
        print(
            "automation resource cleanup "
            f"{result['mode']}: {matched} matched, {remaining} remaining"
        )
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
