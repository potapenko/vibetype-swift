#!/usr/bin/env python3
"""Smoke tests for the standalone blocked-task selector."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("backlog_blocked_next.py")


def load_selector_module():
    spec = importlib.util.spec_from_file_location("backlog_blocked_next", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load backlog_blocked_next.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["backlog_blocked_next"] = module
    spec.loader.exec_module(module)
    return module


def write_task(
    backlog: Path,
    filename: str,
    task_id: str,
    status: str,
    priority: str = "P3",
    dependencies: tuple[str, ...] = (),
    lane: str = "test",
) -> None:
    dependency_block = ""
    if dependencies:
        dependency_block = "dependencies:\n" + "".join(
            f"  - {dependency_id}\n" for dependency_id in dependencies
        )
    (backlog / filename).write_text(
        f"""---
id: {task_id}
status: {status}
priority: {priority}
lane: {lane}
{dependency_block}---

# {task_id} - Test Task

Status: {status}
""",
        encoding="utf-8",
    )


class BacklogBlockedNextTests(unittest.TestCase):
    def test_default_selection_defers_ios_blockers(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(backlog, "vt-001-ios.md", "VT-001", "blocked", priority="P0", lane="ios")
            write_task(
                backlog,
                "vt-002-macos.md",
                "VT-002",
                "blocked",
                priority="P2",
                lane="macos",
            )

            result = module.select_blocked_task(root)

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-002")
        self.assertEqual(result["summary"]["blocked_count"], 1)
        self.assertEqual(result["summary"]["deferred_blocked_count"], 1)
        self.assertEqual(result["deferred_blocked"][0]["id"], "VT-001")

    def test_include_deferred_lanes_allows_ios_blocker_selection(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(
                backlog,
                "vt-001-ios.md",
                "VT-001",
                "blocked",
                priority="P0",
                lane="ios-keyboard",
            )
            write_task(
                backlog,
                "vt-002-macos.md",
                "VT-002",
                "blocked",
                priority="P2",
                lane="macos",
            )

            result = module.select_blocked_task(root, deferred_lanes=frozenset())

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-001")
        self.assertEqual(result["summary"]["deferred_blocked_count"], 0)

    def test_archived_done_dependency_does_not_create_queue_error(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            archive = backlog / "done"
            archive.mkdir(parents=True)
            write_task(archive, "vt-001-done.md", "VT-001", "done", priority="P1")
            write_task(
                backlog,
                "vt-002-blocked.md",
                "VT-002",
                "blocked",
                priority="P1",
                dependencies=("VT-001",),
            )

            result = module.select_blocked_task(root)

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-002")
        self.assertEqual(result["summary"]["archived_done_count"], 1)

    def test_selects_highest_priority_blocked_task(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(backlog, "vt-001-low.md", "VT-001", "blocked", priority="P3")
            write_task(backlog, "vt-002-high.md", "VT-002", "blocked", priority="P1")

            result = module.select_blocked_task(root)

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-002")
        self.assertEqual(result["summary"]["blocked_count"], 2)

    def test_tie_prefers_task_that_unblocks_more_dependents(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(backlog, "vt-001-blocked.md", "VT-001", "blocked", priority="P2")
            write_task(backlog, "vt-002-blocked.md", "VT-002", "blocked", priority="P2")
            write_task(
                backlog,
                "vt-003-dependent.md",
                "VT-003",
                "backlog",
                priority="P2",
                dependencies=("VT-002",),
            )

            result = module.select_blocked_task(root)

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-002")
        self.assertEqual(result["selected"]["unblocks"], ["VT-003"])

    def test_reports_no_blocked_when_queue_has_no_blockers(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(backlog, "vt-001-ready.md", "VT-001", "backlog")

            result = module.select_blocked_task(root)

        self.assertEqual(result["status"], "no_blocked")
        self.assertIsNone(result["selected"])
        self.assertEqual(result["summary"]["blocked_count"], 0)

    def test_cli_json_outputs_selected_blocked_task(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            write_task(backlog, "vt-001-blocked.md", "VT-001", "blocked")

            completed = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "--root", str(root), "--json"],
                capture_output=True,
                check=False,
                text=True,
                timeout=5,
            )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-001")


if __name__ == "__main__":
    unittest.main()
