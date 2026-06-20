#!/usr/bin/env python3
"""Select the next dependency-ready backlog task.

The selector intentionally reads only task front matter and the first title
line. It is the queue controller for scheduled backlog automation; executor
agents should not reimplement selection in prompts.
"""

from __future__ import annotations

import argparse
import json
import re
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


def select_task(root: Path) -> dict[str, Any]:
    tasks, errors = load_tasks(root)
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
    for task in tasks:
        if task.status == "done":
            skipped["done"] += 1
            continue
        if task.status == "in-progress":
            skipped["in_progress"] += 1
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

    summary = {
        "task_count": len(tasks),
        "ready_count": len(ready),
        "dependency_pending_count": len(pending),
        "skipped": skipped,
    }

    if errors:
        return {"status": "queue_error", "errors": errors, "summary": summary}

    ready_json = [
        task_to_json(task, root, sorted(dependents.get(task.task_id, [])), [])
        for task in ready[:10]
    ]
    pending_json = [
        task_to_json(task, root, sorted(dependents.get(task.task_id, [])), unmet)
        for task, unmet in pending[:10]
    ]

    if not ready:
        return {
            "status": "no_ready",
            "selected": None,
            "summary": summary,
            "ready": ready_json,
            "dependency_pending": pending_json,
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
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select the next backlog task.")
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    result = select_task(root)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        if result["status"] == "select":
            selected = result["selected"]
            print(f"select {selected['id']} {selected['path']}")
        elif result["status"] == "no_ready":
            print("no_ready")
        else:
            print("queue_error")
            for error in result.get("errors", []):
                print(f"- {error}")
    return 1 if result["status"] == "queue_error" else 0


if __name__ == "__main__":
    raise SystemExit(main())
