#!/usr/bin/env python3
"""Clean up stale Codex automation helper processes.

This script is deliberately narrow. It targets Codex helper/MCP processes that
scheduled automation runs commonly leave behind. It does not target arbitrary
Node.js processes, the main Codex app, product apps, databases, storage tools,
repository files, or processes owned by other OS users.
"""

from __future__ import annotations

import getpass
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from typing import Any


DEFAULT_GRACE_SECONDS = 2
DEFAULT_PS_TIMEOUT_SECONDS = 30
KILLALL_PROCESS_NAMES: tuple[str, ...] = (
    "SkyComputerUseClient",
    "mcp-server-darwin-arm64",
    "node",
    "node_repl",
)

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


def terminate_candidates(
    candidates: list[CleanupCandidate],
    *,
    apply: bool,
    grace_seconds: int,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "matched": [asdict(candidate) for candidate in candidates],
        "terminated": [],
        "errors": [],
        "remaining": [],
    }
    if not apply:
        return result

    for candidate in candidates:
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
    while time.monotonic() < deadline:
        if not any(process_exists(candidate.pid) for candidate in candidates):
            break
        time.sleep(0.2)

    for candidate in candidates:
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


def run_killall(
    *,
    owner: str,
    apply: bool,
    grace_seconds: int,
    process_names: tuple[str, ...] = KILLALL_PROCESS_NAMES,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "owner": owner,
        "process_names": list(process_names),
        "signals": [],
        "errors": [],
    }
    if not apply:
        return result

    for signal_name in ("TERM", "KILL"):
        if signal_name == "KILL" and grace_seconds > 0:
            time.sleep(grace_seconds)
        for process_name in process_names:
            completed = subprocess.run(
                ["killall", "-u", owner, f"-{signal_name}", process_name],
                capture_output=True,
                check=False,
                text=True,
                timeout=DEFAULT_PS_TIMEOUT_SECONDS,
            )
            entry = {
                "process_name": process_name,
                "signal": signal_name,
                "returncode": completed.returncode,
            }
            stderr = completed.stderr.strip()
            if stderr and "No matching processes belonging to you were found" not in stderr:
                entry["stderr"] = stderr
                result["errors"].append(entry)
            else:
                result["signals"].append(entry)
    return result


def cleanup(
) -> dict[str, Any]:
    current_user = getpass.getuser()
    killall_result = run_killall(
        owner=current_user,
        apply=True,
        grace_seconds=DEFAULT_GRACE_SECONDS,
    )
    processes = read_processes()
    candidates = select_candidates(
        processes,
        owners={current_user},
        min_age_seconds=0,
    )
    process_result = terminate_candidates(
        candidates,
        apply=True,
        grace_seconds=DEFAULT_GRACE_SECONDS,
    )
    return {
        "mode": "apply",
        "current_user": current_user,
        "owners": [current_user],
        "min_age_seconds": 0,
        "grace_seconds": DEFAULT_GRACE_SECONDS,
        "killall": killall_result,
        "processes": process_result,
        "ok": not process_result["errors"]
        and not killall_result["errors"]
        and not process_result["remaining"],
    }


def main() -> int:
    if len(sys.argv) != 1:
        print(
            "automation_resource_cleanup.py takes no arguments; run it directly.",
            file=sys.stderr,
        )
        return 2

    try:
        result = cleanup()
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        result = {
            "mode": "apply",
            "owners": [getpass.getuser()],
            "ok": False,
            "error": str(exc),
        }
        print(json.dumps(result, indent=2, sort_keys=True))
        return 1

    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
