#!/usr/bin/env python3
"""Smoke tests for completed backlog task archival."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("backlog_archive_done.py")


def load_archive_module():
    scripts_dir = str(SCRIPT_PATH.parent)
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
    spec = importlib.util.spec_from_file_location("backlog_archive_done", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load backlog_archive_done.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["backlog_archive_done"] = module
    spec.loader.exec_module(module)
    return module


def init_git(root: Path) -> None:
    subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True, text=True)
    subprocess.run(
        ["git", "config", "user.email", "test@example.invalid"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Backlog Test"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )
    subprocess.run(["git", "add", "."], cwd=root, check=True, capture_output=True, text=True)
    subprocess.run(
        ["git", "commit", "--no-gpg-sign", "-m", "seed backlog"],
        cwd=root,
        check=True,
        capture_output=True,
        text=True,
    )


def write_task(
    backlog: Path,
    filename: str,
    task_id: str,
    status: str,
    dependencies: tuple[str, ...] = (),
    visible_status: str | None = None,
) -> None:
    dependency_block = ""
    if dependencies:
        dependency_block = "dependencies:\n" + "".join(
            f"  - {dependency_id}\n" for dependency_id in dependencies
        )
    visible = visible_status or status
    (backlog / filename).write_text(
        f"""---
id: {task_id}
status: {status}
priority: P1
lane: test
{dependency_block}---

# {task_id} - Test Task

Status: {visible}
""",
        encoding="utf-8",
    )


class BacklogArchiveDoneTests(unittest.TestCase):
    def test_dry_run_reports_done_tasks_without_moving(self) -> None:
        module = load_archive_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            task_path = backlog / "vt-001-done.md"
            write_task(backlog, task_path.name, "VT-001", "done")
            init_git(root)

            result = module.archive_done_tasks(root)

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["summary"]["planned_count"], 1)
            self.assertEqual(result["summary"]["moved_count"], 0)
            self.assertTrue(task_path.exists())
            self.assertFalse((backlog / "done" / task_path.name).exists())

    def test_apply_moves_done_task_to_archive(self) -> None:
        module = load_archive_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            task_path = backlog / "vt-001-done.md"
            write_task(backlog, task_path.name, "VT-001", "done")
            init_git(root)

            result = module.archive_done_tasks(root, apply=True)

            self.assertEqual(result["status"], "ok")
            self.assertEqual(result["summary"]["planned_count"], 1)
            self.assertEqual(result["summary"]["moved_count"], 1)
            self.assertFalse(task_path.exists())
            self.assertTrue((backlog / "done" / task_path.name).exists())

    def test_skips_done_status_mismatch(self) -> None:
        module = load_archive_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            task_path = backlog / "vt-001-mismatch.md"
            write_task(backlog, task_path.name, "VT-001", "done", visible_status="backlog")
            init_git(root)

            result = module.archive_done_tasks(root, apply=True)

            self.assertEqual(result["summary"]["planned_count"], 0)
            self.assertEqual(result["summary"]["moved_count"], 0)
            self.assertEqual(result["skipped"][0]["reason"], "done_status_mismatch")
            self.assertTrue(task_path.exists())


if __name__ == "__main__":
    unittest.main()
