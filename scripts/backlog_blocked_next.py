#!/usr/bin/env python3
"""Select the next blocked backlog task for blocker-resolution automation."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from backlog_next import (
    Task,
    git_last_change,
    load_tasks_with_archived_done,
    priority_rank,
    task_number,
    task_to_json,
)


def status_summary(tasks: list[Task]) -> dict[str, int]:
    summary = {
        "task_count": len(tasks),
        "blocked_count": 0,
        "done_count": 0,
        "in_progress_count": 0,
        "candidate_count": 0,
        "unknown_status_count": 0,
    }
    for task in tasks:
        if task.status == "blocked":
            summary["blocked_count"] += 1
        elif task.status == "done":
            summary["done_count"] += 1
        elif task.status == "in-progress":
            summary["in_progress_count"] += 1
        elif task.status in {"", "backlog", "ready"}:
            summary["candidate_count"] += 1
        else:
            summary["unknown_status_count"] += 1
    return summary


def task_dependency_maps(tasks: list[Task]) -> tuple[dict[str, Task], dict[str, list[str]], list[str]]:
    by_id: dict[str, Task] = {}
    duplicates: dict[str, list[str]] = {}
    errors: list[str] = []

    for task in tasks:
        if task.task_id in by_id:
            duplicates.setdefault(task.task_id, [str(by_id[task.task_id].path)]).append(
                str(task.path)
            )
        by_id[task.task_id] = task

    for task_id, paths in sorted(duplicates.items()):
        errors.append(f"duplicate task id {task_id}: {', '.join(paths)}")

    dependents: dict[str, list[str]] = {task.task_id: [] for task in tasks}
    for task in tasks:
        for dependency_id in task.dependencies:
            if dependency_id in by_id:
                dependents.setdefault(dependency_id, []).append(task.task_id)
            else:
                errors.append(f"{task.task_id} references missing dependency: {dependency_id}")

    for dependent_ids in dependents.values():
        dependent_ids.sort(key=lambda value: (task_number(value), value))

    return by_id, dependents, errors


def blocked_task_to_json(task: Task, root: Path, dependents: dict[str, list[str]]) -> dict[str, Any]:
    task_json = task_to_json(
        task,
        root,
        dependents.get(task.task_id, []),
        [],
    )
    task_json.update(git_last_change(root, task))
    return task_json


def select_blocked_task(root: Path) -> dict[str, Any]:
    active_tasks, archived_done_tasks, errors = load_tasks_with_archived_done(root)
    all_tasks = active_tasks + archived_done_tasks
    _by_id, dependents, dependency_errors = task_dependency_maps(all_tasks)
    errors.extend(dependency_errors)
    summary = status_summary(active_tasks)
    summary["archived_done_count"] = len(archived_done_tasks)

    blocked_tasks = [task for task in active_tasks if task.status == "blocked"]
    blocked_tasks.sort(
        key=lambda task: (
            priority_rank(task.priority),
            -len(dependents.get(task.task_id, [])),
            task_number(task.task_id),
            task.task_id,
        )
    )

    blocked_json = [
        blocked_task_to_json(task, root, dependents)
        for task in blocked_tasks[:10]
    ]

    if errors:
        return {
            "status": "queue_error",
            "errors": errors,
            "summary": summary,
            "blocked": blocked_json,
        }

    if not blocked_tasks:
        return {
            "status": "no_blocked",
            "selected": None,
            "summary": summary,
            "blocked": blocked_json,
        }

    selected = blocked_tasks[0]
    return {
        "status": "select",
        "selected": blocked_task_to_json(selected, root, dependents),
        "selection_reason": (
            "highest priority blocked task; ties prefer larger direct unblock "
            "count, then numeric task id"
        ),
        "summary": summary,
        "blocked": blocked_json,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select the next blocked backlog task.")
    parser.add_argument("--root", default=".", help="repository root")
    parser.add_argument("--json", action="store_true", help="print machine-readable JSON")
    args = parser.parse_args()

    root = Path(args.root).resolve()
    result = select_blocked_task(root)
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        if result["status"] == "select":
            selected = result["selected"]
            print(f"select {selected['id']} {selected['path']}")
        elif result["status"] == "no_blocked":
            print("no_blocked")
        else:
            print("queue_error")
            for error in result.get("errors", []):
                print(f"- {error}")
    return 1 if result["status"] == "queue_error" else 0


if __name__ == "__main__":
    raise SystemExit(main())
