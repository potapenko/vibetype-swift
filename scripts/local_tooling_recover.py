#!/usr/bin/env python3
"""Recover local Xcode/tooling blockers that scheduled agents can safely fix.

This script is intentionally narrow. It targets stale local build/test tooling
for this repository and generated VibeType build artifacts. It does not touch
source files, Git state, databases, object storage, or broad MCP server
processes.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


DEFAULT_STALE_AFTER_SECONDS = 3 * 60
DEFAULT_GRACE_SECONDS = 5
DEFAULT_PS_TIMEOUT_SECONDS = 60

PROCESS_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("xcodebuild", re.compile(r"(^|/|\s)xcodebuild(\s|$)")),
    ("xctest", re.compile(r"(^|/|\s)xctest(\s|$)")),
    ("swift_build_service", re.compile(r"SWBBuildService")),
    (
        "clang_toolchain_probe",
        re.compile(r"(^|/|\s)clang\s+.*-v\s+-E\s+-dM\s+.*(/dev/null|\\dev\\null)"),
    ),
)


@dataclass(frozen=True)
class ProcessInfo:
    pid: int
    ppid: int
    etimes: int
    command: str


@dataclass(frozen=True)
class ProcessCandidate:
    pid: int
    ppid: int
    etimes: int
    kind: str
    command: str
    reason: str


def parse_ps_output(output: str) -> list[ProcessInfo]:
    processes: list[ProcessInfo] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        try:
            pid = int(parts[0])
            ppid = int(parts[1])
            etimes = parse_elapsed_seconds(parts[2])
        except ValueError:
            continue
        processes.append(ProcessInfo(pid=pid, ppid=ppid, etimes=etimes, command=parts[3]))
    return processes


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


def read_processes() -> list[ProcessInfo]:
    completed = run_ps(["ps", "-axo", "pid=,ppid=,etimes=,command="])
    if completed.returncode != 0 and "etimes" in completed.stderr:
        completed = run_ps(["ps", "-axo", "pid=,ppid=,etime=,command="])
    if completed.returncode != 0:
        raise RuntimeError(completed.stderr.strip() or "ps failed")
    return parse_ps_output(completed.stdout)


def run_ps(command: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        capture_output=True,
        check=False,
        text=True,
        timeout=DEFAULT_PS_TIMEOUT_SECONDS,
    )


def match_process_kind(command: str) -> str | None:
    for kind, pattern in PROCESS_PATTERNS:
        if pattern.search(command):
            return kind
    return None


def select_stale_processes(
    processes: list[ProcessInfo],
    stale_after_seconds: int,
    current_pid: int | None = None,
) -> list[ProcessCandidate]:
    own_pid = os.getpid() if current_pid is None else current_pid
    candidates: list[ProcessCandidate] = []
    for process in processes:
        if process.pid == own_pid:
            continue
        kind = match_process_kind(process.command)
        if kind is None:
            continue
        if process.etimes < stale_after_seconds:
            continue
        candidates.append(
            ProcessCandidate(
                pid=process.pid,
                ppid=process.ppid,
                etimes=process.etimes,
                kind=kind,
                command=process.command,
                reason=f"stale {kind} process older than {stale_after_seconds}s",
            )
        )

    return sorted(candidates, key=process_kill_sort_key)


def process_kill_sort_key(candidate: ProcessCandidate) -> tuple[int, int]:
    priority = {
        "clang_toolchain_probe": 0,
        "xctest": 1,
        "xcodebuild": 2,
        "swift_build_service": 3,
    }.get(candidate.kind, 9)
    return (priority, candidate.pid)


def process_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def terminate_processes(
    candidates: list[ProcessCandidate],
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
            result["terminated"].append({"pid": candidate.pid, "signal": "already_exited"})
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
            result["terminated"].append({"pid": candidate.pid, "signal": "already_exited"})
        except PermissionError as exc:
            result["errors"].append({"pid": candidate.pid, "error": str(exc)})

    for candidate in candidates:
        if process_exists(candidate.pid):
            result["remaining"].append(asdict(candidate))
    return result


def artifact_candidates(root: Path, home: Path | None = None) -> list[Path]:
    resolved_root = root.resolve()
    candidates: list[Path] = []
    script_cache = resolved_root / "scripts" / "__pycache__"
    if script_cache.exists():
        candidates.append(script_cache)

    home_dir = Path.home() if home is None else home
    derived_data = home_dir / "Library" / "Developer" / "Xcode" / "DerivedData"
    if derived_data.exists():
        candidates.extend(sorted(derived_data.glob("vibetype-*")))

    return candidates


def remove_artifacts(candidates: list[Path], *, apply: bool) -> dict[str, Any]:
    result: dict[str, Any] = {
        "matched": [str(path) for path in candidates],
        "removed": [],
        "errors": [],
    }
    if not apply:
        return result

    for path in candidates:
        try:
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()
            result["removed"].append(str(path))
        except FileNotFoundError:
            result["removed"].append(str(path))
        except OSError as exc:
            result["errors"].append({"path": str(path), "error": str(exc)})
    return result


def recover(
    root: Path,
    *,
    apply: bool,
    stale_after_seconds: int,
    grace_seconds: int,
) -> dict[str, Any]:
    processes = read_processes()
    stale_processes = select_stale_processes(processes, stale_after_seconds)
    process_result = terminate_processes(
        stale_processes,
        apply=apply,
        grace_seconds=grace_seconds,
    )
    artifacts = remove_artifacts(artifact_candidates(root), apply=apply)
    errors = process_result["errors"] + artifacts["errors"]
    return {
        "mode": "apply" if apply else "dry_run",
        "root": str(root.resolve()),
        "stale_after_seconds": stale_after_seconds,
        "grace_seconds": grace_seconds,
        "processes": process_result,
        "artifacts": artifacts,
        "ok": not errors and not process_result["remaining"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Recover stale local Xcode tooling.")
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument(
        "--apply",
        action="store_true",
        help="terminate stale tooling and remove generated artifacts",
    )
    parser.add_argument(
        "--stale-after-seconds",
        type=int,
        default=DEFAULT_STALE_AFTER_SECONDS,
        help="minimum process age before it may be recovered",
    )
    parser.add_argument(
        "--grace-seconds",
        type=int,
        default=DEFAULT_GRACE_SECONDS,
        help="seconds to wait after TERM before KILL",
    )
    parser.add_argument("--json", action="store_true", help="print JSON report")
    args = parser.parse_args()

    try:
        result = recover(
            Path(args.root),
            apply=args.apply,
            stale_after_seconds=args.stale_after_seconds,
            grace_seconds=args.grace_seconds,
        )
    except Exception as exc:  # pragma: no cover - defensive CLI boundary
        result = {
            "mode": "apply" if args.apply else "dry_run",
            "root": str(Path(args.root).resolve()),
            "ok": False,
            "error": str(exc),
        }
        if args.json:
            print(json.dumps(result, indent=2, sort_keys=True))
        else:
            print(f"local tooling recovery failed: {exc}", file=sys.stderr)
        return 1

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        print(
            "local tooling recovery "
            f"{result['mode']}: "
            f"{len(result['processes']['matched'])} stale processes, "
            f"{len(result['artifacts']['matched'])} generated artifacts"
        )
    return 0 if result["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
