#!/usr/bin/env python3
"""Select the next dependency-ready backlog task.

The selector intentionally reads only task front matter and the first title
line. It is the queue controller for scheduled backlog automation; executor
agents should not reimplement selection in prompts.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


TERMINAL_STATUSES = {"done", "in-progress", "blocked"}
CANDIDATE_STATUSES = {"backlog", "ready", ""}
PRIORITY_RANK = {"p0": 0, "p1": 1, "p2": 2, "p3": 3}


@dataclass(frozen=True)
class Task:
    path: Path
    task_id: str
    title: str
    status: str
    visible_status: str
    priority: str
    lane: str
    dependencies: tuple[str, ...]


def normalize_status(value: str | None) -> str:
    return (value or "").strip().lower().rstrip(".")


def parse_front_matter(lines: list[str]) -> dict[str, Any]:
    if not lines or lines[0].strip() != "---":
        return {}

    data: dict[str, Any] = {}
    current_key: str | None = None
    for line in lines[1:]:
        stripped = line.rstrip("\n")
        if stripped == "---":
            break
        key_match = re.match(r"^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$", stripped)
        if key_match:
            current_key = key_match.group(1)
            value = key_match.group(2).strip()
            data[current_key] = value if value else []
            continue
        item_match = re.match(r"^\s+-\s+(.+?)\s*$", stripped)
        if item_match and current_key:
            existing = data.get(current_key)
            if not isinstance(existing, list):
                existing = []
                data[current_key] = existing
            existing.append(item_match.group(1).strip())
    return data


def parse_task(path: Path) -> Task:
    lines = path.read_text(encoding="utf-8").splitlines()
    front_matter = parse_front_matter(lines)
    visible_status = ""
    title = path.stem

    for line in lines:
        if not visible_status:
            status_match = re.match(r"^Status:\s*(.+?)\s*$", line)
            if status_match:
                visible_status = normalize_status(status_match.group(1))
        if line.startswith("# ") and title == path.stem:
            title = line[2:].strip()
        if visible_status and title != path.stem:
            break

    dependencies_value = front_matter.get("dependencies", [])
    if isinstance(dependencies_value, str):
        dependencies = (dependencies_value,) if dependencies_value else ()
    else:
        dependencies = tuple(str(item) for item in dependencies_value)

    task_id = str(front_matter.get("id") or path.stem)
    return Task(
        path=path,
        task_id=task_id,
        title=title,
        status=normalize_status(str(front_matter.get("status", ""))),
        visible_status=visible_status,
        priority=str(front_matter.get("priority") or "P3"),
        lane=str(front_matter.get("lane") or ""),
        dependencies=dependencies,
    )


def task_number(task_id: str) -> int:
    match = re.search(r"(\d+)$", task_id)
    return int(match.group(1)) if match else 1_000_000


def priority_rank(priority: str) -> int:
    return PRIORITY_RANK.get(priority.strip().lower(), 99)


def task_to_json(task: Task, root: Path, unblocks: list[str], unmet: list[str]) -> dict[str, Any]:
    return {
        "id": task.task_id,
        "path": str(task.path.relative_to(root)),
        "title": task.title,
        "status": task.status or "missing",
        "visible_status": task.visible_status or "missing",
        "priority": task.priority,
        "lane": task.lane,
        "dependencies": list(task.dependencies),
        "unmet_dependencies": unmet,
        "unblocks": unblocks,
        "unblock_count": len(unblocks),
    }


def file_mtime_details(path: Path, now: float) -> dict[str, Any]:
    try:
        modified_at_seconds = path.stat().st_mtime
    except OSError:
        return {}

    modified_at = dt.datetime.fromtimestamp(modified_at_seconds, tz=dt.timezone.utc)
    return {
        "file_modified_at": modified_at.isoformat().replace("+00:00", "Z"),
        "file_age_seconds": max(0, int(now - modified_at_seconds)),
    }


def is_expired_in_progress(
    task: Task,
    now: float,
    expire_after_hours: float | None,
) -> bool:
    if task.status != "in-progress" or expire_after_hours is None:
        return False
    try:
        file_age_seconds = now - task.path.stat().st_mtime
    except OSError:
        return False
    return file_age_seconds >= expire_after_hours * 60 * 60


def reset_in_progress_to_backlog(path: Path) -> None:
    lines = path.read_text(encoding="utf-8").splitlines()
    updated: list[str] = []
    in_front_matter = bool(lines and lines[0].strip() == "---")
    front_matter_open = in_front_matter
    front_matter_status_replaced = False
    visible_status_replaced = False

    for index, line in enumerate(lines):
        if index > 0 and front_matter_open and line.strip() == "---":
            front_matter_open = False

        if front_matter_open and re.match(r"^status:\s*in-progress\s*$", line, re.IGNORECASE):
            updated.append("status: backlog")
            front_matter_status_replaced = True
            continue

        if not visible_status_replaced and re.match(
            r"^Status:\s*in-progress\.?\s*$",
            line,
            re.IGNORECASE,
        ):
            updated.append("Status: backlog.")
            visible_status_replaced = True
            continue

        updated.append(line)

    if not front_matter_status_replaced:
        raise ValueError(f"{path}: missing front matter status: in-progress")

    path.write_text("\n".join(updated) + "\n", encoding="utf-8")


def dependency_to_json(dependency_id: str, by_id: dict[str, Task], root: Path) -> dict[str, Any]:
    task = by_id.get(dependency_id)
    if task is None:
        return {"id": dependency_id, "status": "missing"}
    return {
        "id": task.task_id,
        "path": str(task.path.relative_to(root)),
        "title": task.title,
        "status": task.status or "missing",
        "visible_status": task.visible_status or "missing",
    }


def git_last_change(root: Path, task: Task) -> dict[str, str]:
    try:
        relative_path = str(task.path.relative_to(root))
        result = subprocess.run(
            ["git", "-C", str(root), "log", "-1", "--format=%H%x00%cI%x00%s", "--", relative_path],
            capture_output=True,
            check=False,
            text=True,
            timeout=2,
        )
    except (OSError, subprocess.SubprocessError, ValueError):
        return {}

    if result.returncode != 0 or not result.stdout.strip():
        return {}

    parts = result.stdout.strip().split("\x00", 2)
    if len(parts) != 3:
        return {}
    commit_hash, changed_at, subject = parts
    return {
        "last_changed_commit": commit_hash,
        "last_changed_at": changed_at,
        "last_changed_subject": subject,
    }


def in_progress_to_json(
    task: Task,
    root: Path,
    unblocks: list[str],
    blocked_candidates: list[str],
    now: float,
    expire_after_hours: float | None,
) -> dict[str, Any]:
    task_json = task_to_json(task, root, unblocks, [])
    task_json.update(git_last_change(root, task))
    task_json.update(file_mtime_details(task.path, now))
    task_json["expired"] = is_expired_in_progress(task, now, expire_after_hours)
    if expire_after_hours is not None:
        task_json["expires_after_hours"] = expire_after_hours
    task_json["blocked_candidates"] = blocked_candidates
    return task_json


def load_tasks(root: Path) -> tuple[list[Task], list[str]]:
    tasks: list[Task] = []
    errors: list[str] = []
    for path in sorted((root / "backlog").glob("*.md")):
        if path.name.lower() == "readme.md":
            continue
        try:
            tasks.append(parse_task(path))
        except OSError as exc:
            errors.append(f"{path}: {exc}")
    return tasks, errors


def select_task(
    root: Path,
    expire_in_progress_after_hours: float | None = 1.0,
    apply_expired_in_progress: bool = False,
) -> dict[str, Any]:
    now = time.time()
    tasks, errors = load_tasks(root)
    expired_before_apply = [
        task
        for task in tasks
        if is_expired_in_progress(task, now, expire_in_progress_after_hours)
    ]
    expired_before_apply.sort(key=lambda task: (task_number(task.task_id), task.task_id))
    expired_json = [
        {
            **task_to_json(task, root, [], []),
            **git_last_change(root, task),
            **file_mtime_details(task.path, now),
            "expires_after_hours": expire_in_progress_after_hours,
        }
        for task in expired_before_apply
    ]

    expired_reset_paths: list[str] = []
    if apply_expired_in_progress:
        for task in expired_before_apply:
            try:
                reset_in_progress_to_backlog(task.path)
                expired_reset_paths.append(str(task.path.relative_to(root)))
            except (OSError, ValueError) as exc:
                errors.append(str(exc))
        tasks, load_errors = load_tasks(root)
        errors.extend(load_errors)

    by_id: dict[str, Task] = {}
    duplicates: dict[str, list[str]] = {}
    for task in tasks:
        if task.task_id in by_id:
            duplicates.setdefault(task.task_id, [str(by_id[task.task_id].path)]).append(
                str(task.path)
            )
        by_id[task.task_id] = task

    for task_id, paths in sorted(duplicates.items()):
        errors.append(f"duplicate task id {task_id}: {', '.join(paths)}")

    dependents: dict[str, list[str]] = {task.task_id: [] for task in tasks}
    missing_dependencies: dict[str, list[str]] = {}
    for task in tasks:
        for dep in task.dependencies:
            if dep not in by_id:
                missing_dependencies.setdefault(task.task_id, []).append(dep)
            else:
                dependents.setdefault(dep, []).append(task.task_id)

    for task_id, missing in sorted(missing_dependencies.items()):
        errors.append(f"{task_id} references missing dependencies: {', '.join(missing)}")

    skipped = {"done": 0, "in_progress": 0, "blocked": 0, "unknown_status": 0}
    ready: list[Task] = []
    pending: list[tuple[Task, list[str]]] = []
    in_progress: list[Task] = []
    blocked_by_in_progress: dict[str, set[str]] = {}
    for task in tasks:
        if task.status == "done":
            skipped["done"] += 1
            continue
        if task.status == "in-progress":
            skipped["in_progress"] += 1
            in_progress.append(task)
            continue
        if task.status == "blocked":
            skipped["blocked"] += 1
            continue
        if task.status not in CANDIDATE_STATUSES:
            skipped["unknown_status"] += 1
            continue

        unmet = [
            dep
            for dep in task.dependencies
            if dep not in by_id or by_id[dep].status != "done"
        ]
        if unmet:
            for dependency_id in unmet:
                dependency = by_id.get(dependency_id)
                if dependency and dependency.status == "in-progress":
                    blocked_by_in_progress.setdefault(dependency_id, set()).add(task.task_id)
            pending.append((task, unmet))
        else:
            ready.append(task)

    ready.sort(
        key=lambda task: (
            priority_rank(task.priority),
            -len(dependents.get(task.task_id, [])),
            task_number(task.task_id),
            task.task_id,
        )
    )
    pending.sort(key=lambda item: (task_number(item[0].task_id), item[0].task_id))
    in_progress.sort(key=lambda task: (task_number(task.task_id), task.task_id))

    summary = {
        "task_count": len(tasks),
        "ready_count": len(ready),
        "dependency_pending_count": len(pending),
        "blocking_in_progress_count": len(blocked_by_in_progress),
        "expired_in_progress_count": len(expired_before_apply),
        "skipped": skipped,
    }

    if errors:
        return {
            "status": "queue_error",
            "errors": errors,
            "summary": summary,
            "expired_in_progress": expired_json,
            "expired_in_progress_applied": apply_expired_in_progress,
            "expired_in_progress_reset_paths": expired_reset_paths,
        }

    ready_json = [
        task_to_json(task, root, sorted(dependents.get(task.task_id, [])), [])
        for task in ready[:10]
    ]
    pending_json = []
    for task, unmet in pending[:10]:
        task_json = task_to_json(task, root, sorted(dependents.get(task.task_id, [])), unmet)
        task_json["unmet_dependency_statuses"] = [
            dependency_to_json(dependency_id, by_id, root) for dependency_id in unmet
        ]
        pending_json.append(task_json)

    in_progress_json = [
        in_progress_to_json(
            task,
            root,
            sorted(dependents.get(task.task_id, [])),
            sorted(blocked_by_in_progress.get(task.task_id, set())),
            now,
            expire_in_progress_after_hours,
        )
        for task in in_progress[:10]
    ]
    blocking_in_progress_json = [
        in_progress_to_json(
            by_id[task_id],
            root,
            sorted(dependents.get(task_id, [])),
            sorted(blocked_by_in_progress[task_id]),
            now,
            expire_in_progress_after_hours,
        )
        for task_id in sorted(blocked_by_in_progress, key=lambda value: (task_number(value), value))
    ]

    if not ready:
        return {
            "status": "no_ready",
            "selected": None,
            "summary": summary,
            "ready": ready_json,
            "dependency_pending": pending_json,
            "in_progress": in_progress_json,
            "blocking_in_progress": blocking_in_progress_json,
            "expired_in_progress": expired_json,
            "expired_in_progress_applied": apply_expired_in_progress,
            "expired_in_progress_reset_paths": expired_reset_paths,
        }

    selected = ready[0]
    return {
        "status": "select",
        "selected": task_to_json(
            selected,
            root,
            sorted(dependents.get(selected.task_id, [])),
            [],
        ),
        "selection_reason": "highest priority dependency-ready task; ties prefer larger direct unblock count, then numeric task id",
        "summary": summary,
        "ready": ready_json,
        "dependency_pending": pending_json,
        "in_progress": in_progress_json,
        "blocking_in_progress": blocking_in_progress_json,
        "expired_in_progress": expired_json,
        "expired_in_progress_applied": apply_expired_in_progress,
        "expired_in_progress_reset_paths": expired_reset_paths,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select the next backlog task.")
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    parser.add_argument(
        "--expire-in-progress-after-hours",
        type=float,
        default=1.0,
        help="treat in-progress task files older than this many hours as expired claims",
    )
    parser.add_argument(
        "--apply-expired-in-progress",
        action="store_true",
        help="reset expired in-progress task files back to backlog before selection",
    )
    args = parser.parse_args()

    root = Path(args.root).resolve()
    result = select_task(
        root,
        expire_in_progress_after_hours=args.expire_in_progress_after_hours,
        apply_expired_in_progress=args.apply_expired_in_progress,
    )
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        if result["status"] == "select":
            selected = result["selected"]
            print(f"select {selected['id']} {selected['path']}")
        elif result["status"] == "no_ready":
            print("no_ready")
            for task in result.get("blocking_in_progress", []):
                blocked = ", ".join(task.get("blocked_candidates", []))
                print(f"- in-progress dependency {task['id']} blocks: {blocked}")
        else:
            print("queue_error")
            for error in result.get("errors", []):
                print(f"- {error}")
    return 1 if result["status"] == "queue_error" else 0


if __name__ == "__main__":
    raise SystemExit(main())
