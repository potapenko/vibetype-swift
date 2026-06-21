#!/usr/bin/env python3
"""Smoke tests for the standalone backlog selector."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("backlog_next.py")


def load_selector_module():
    spec = importlib.util.spec_from_file_location("backlog_next", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load backlog_next.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["backlog_next"] = module
    spec.loader.exec_module(module)
    return module


class BacklogNextTests(unittest.TestCase):
    def test_archived_done_dependency_makes_active_task_ready(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            archive = backlog / "done"
            archive.mkdir(parents=True)
            (archive / "vt-001-parent.md").write_text(
                """---
id: VT-001
status: done
priority: P1
lane: test
---

# VT-001 - Parent

Status: done
""",
                encoding="utf-8",
            )
            (backlog / "vt-002-dependent.md").write_text(
                """---
id: VT-002
status: backlog
priority: P1
lane: test
dependencies:
  - VT-001
---

# VT-002 - Dependent

Status: backlog.
""",
                encoding="utf-8",
            )

            result = module.select_task(root)

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-002")
        self.assertEqual(result["summary"]["task_count"], 1)
        self.assertEqual(result["summary"]["archived_done_count"], 1)
        self.assertEqual(result["summary"]["ready_count"], 1)

    def test_archived_done_duplicate_id_is_queue_error(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            archive = backlog / "done"
            archive.mkdir(parents=True)
            for parent in (backlog, archive):
                (parent / "vt-001-task.md").write_text(
                    """---
id: VT-001
status: done
priority: P1
lane: test
---

# VT-001 - Task

Status: done
""",
                    encoding="utf-8",
                )

            result = module.select_task(root)

        self.assertEqual(result["status"], "queue_error")
        self.assertIn("duplicate task id VT-001", result["errors"][0])

    def test_no_ready_reports_in_progress_dependency_blocker(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            (backlog / "vt-001-parent.md").write_text(
                """---
id: VT-001
status: in-progress
priority: P1
lane: test
---

# VT-001 - Parent

Status: in-progress.
""",
                encoding="utf-8",
            )
            (backlog / "vt-002-dependent.md").write_text(
                """---
id: VT-002
status: backlog
priority: P1
lane: test
dependencies:
  - VT-001
---

# VT-002 - Dependent

Status: backlog.
""",
                encoding="utf-8",
            )

            result = module.select_task(root)

        self.assertEqual(result["status"], "no_ready")
        self.assertEqual(result["summary"]["ready_count"], 0)
        self.assertEqual(result["summary"]["blocking_in_progress_count"], 1)
        self.assertEqual(result["in_progress"][0]["id"], "VT-001")
        self.assertEqual(result["blocking_in_progress"][0]["id"], "VT-001")
        self.assertEqual(result["blocking_in_progress"][0]["blocked_candidates"], ["VT-002"])
        self.assertEqual(
            result["dependency_pending"][0]["unmet_dependency_statuses"][0]["status"],
            "in-progress",
        )

    def test_default_run_resets_expired_in_progress_before_selection(self) -> None:
        module = load_selector_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            task_path = backlog / "vt-001-parent.md"
            task_path.write_text(
                """---
id: VT-001
status: in-progress
priority: P1
lane: test
---

# VT-001 - Parent

Status: in-progress.
""",
                encoding="utf-8",
            )
            (backlog / "vt-002-dependent.md").write_text(
                """---
id: VT-002
status: backlog
priority: P1
lane: test
dependencies:
  - VT-001
---

# VT-002 - Dependent

Status: backlog.
""",
                encoding="utf-8",
            )
            two_hours_ago = time.time() - (2 * 60 * 60)
            os.utime(task_path, (two_hours_ago, two_hours_ago))

            result = module.select_task(root)
            task_text = task_path.read_text(encoding="utf-8")

        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-001")
        self.assertEqual(result["summary"]["expired_in_progress_count"], 1)
        self.assertEqual(result["expired_in_progress_reset_paths"], ["backlog/vt-001-parent.md"])
        self.assertIn("status: backlog", task_text)
        self.assertIn("Status: backlog.", task_text)

    def test_cli_json_resets_expired_in_progress_without_extra_flags(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            backlog = root / "backlog"
            backlog.mkdir()
            task_path = backlog / "vt-001-parent.md"
            task_path.write_text(
                """---
id: VT-001
status: in-progress
priority: P1
lane: test
---

# VT-001 - Parent

Status: in-progress.
""",
                encoding="utf-8",
            )
            two_hours_ago = time.time() - (2 * 60 * 60)
            os.utime(task_path, (two_hours_ago, two_hours_ago))

            completed = subprocess.run(
                [sys.executable, str(SCRIPT_PATH), "--root", str(root), "--json"],
                capture_output=True,
                check=False,
                text=True,
                timeout=5,
            )
            task_text = task_path.read_text(encoding="utf-8")

        self.assertEqual(completed.returncode, 0, completed.stderr)
        result = json.loads(completed.stdout)
        self.assertEqual(result["status"], "select")
        self.assertEqual(result["selected"]["id"], "VT-001")
        self.assertEqual(result["expired_in_progress_reset_paths"], ["backlog/vt-001-parent.md"])
        self.assertTrue(result["expired_in_progress_applied"])
        self.assertIn("status: backlog", task_text)
        self.assertIn("Status: backlog.", task_text)


if __name__ == "__main__":
    unittest.main()
