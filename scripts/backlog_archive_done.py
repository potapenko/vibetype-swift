#!/usr/bin/env python3
"""Archive completed backlog tasks out of the active queue."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any

from backlog_next import ARCHIVED_DONE_DIR, Task, load_tasks


def relative_path(root: Path, path: Path) -> str:
    return str(path.relative_to(root))


def git_status(root: Path, path: Path) -> str | None:
    try:
        pathspec = str(path.relative_to(root))
    except ValueError:
        return None

    try:
        result = subprocess.run(
            ["git", "-C", str(root), "status", "--porcelain", "--", pathspec],
            capture_output=True,
            check=False,
            text=True,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None

    if result.returncode != 0:
        return None
    return result.stdout.strip()


def move_entry(root: Path, task: Task, destination: Path) -> dict[str, Any]:
    return {
        "id": task.task_id,
        "from": relative_path(root, task.path),
        "to": relative_path(root, destination),
    }


def skip_entry(root: Path, task: Task, reason: str) -> dict[str, Any]:
    return {
        "id": task.task_id,
        "path": relative_path(root, task.path),
        "reason": reason,
    }


def archive_done_tasks(
    root: Path,
    apply: bool = False,
    limit: int | None = None,
) -> dict[str, Any]:
    active_tasks, errors = load_tasks(root)
    archive_dir = root / ARCHIVED_DONE_DIR
    planned: list[dict[str, Any]] = []
    moved: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []

    if errors:
        return {
            "status": "queue_error",
            "apply": apply,
            "errors": errors,
            "summary": {
                "active_task_count": len(active_tasks),
                "planned_count": 0,
                "moved_count": 0,
                "skipped_count": 0,
            },
        }

    for task in active_tasks:
        if task.status != "done" and task.visible_status != "done":
            continue
        if task.status != "done" or task.visible_status != "done":
            skipped.append(skip_entry(root, task, "done_status_mismatch"))
            continue

        destination = archive_dir / task.path.name
        if destination.exists():
            skipped.append(skip_entry(root, task, "destination_exists"))
            continue

        status = git_status(root, task.path)
        if status is None:
            skipped.append(skip_entry(root, task, "git_status_unavailable"))
            continue
        if status:
            skipped.append(skip_entry(root, task, "source_has_uncommitted_changes"))
            continue

        planned.append(move_entry(root, task, destination))
        if limit is not None and len(planned) >= limit:
            break

    if apply and planned:
        archive_dir.mkdir(parents=True, exist_ok=True)
        for entry in planned:
            source = root / entry["from"]
            destination = root / entry["to"]
            source.rename(destination)
            moved.append(entry)

    return {
        "status": "ok",
        "apply": apply,
        "archive_dir": str(ARCHIVED_DONE_DIR),
        "summary": {
            "active_task_count": len(active_tasks),
            "planned_count": len(planned),
            "moved_count": len(moved),
            "skipped_count": len(skipped),
        },
        "planned": planned,
        "moved": moved,
        "skipped": skipped,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Archive completed backlog tasks.")
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--apply", action="store_true", help="move eligible done tasks")
    parser.add_argument("--dry-run", action="store_true", help="preview moves without changing files")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument("--limit", type=int, help="maximum number of eligible tasks to move")
    args = parser.parse_args()

    if args.apply and args.dry_run:
        parser.error("--apply and --dry-run are mutually exclusive")
    if args.limit is not None and args.limit < 1:
        parser.error("--limit must be positive")

    root = Path(args.root).resolve()
    result = archive_done_tasks(root, apply=args.apply, limit=args.limit)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    elif result["status"] == "queue_error":
        print("queue_error")
        for error in result.get("errors", []):
            print(f"- {error}")
    else:
        summary = result["summary"]
        action = "moved" if args.apply else "would_move"
        print(f"{action} {summary['moved_count'] if args.apply else summary['planned_count']}")
        if summary["skipped_count"]:
            print(f"skipped {summary['skipped_count']}")

    return 1 if result["status"] == "queue_error" else 0


if __name__ == "__main__":
    raise SystemExit(main())
