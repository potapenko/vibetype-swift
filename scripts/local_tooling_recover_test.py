#!/usr/bin/env python3
"""Tests for local_tooling_recover.py."""

from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).with_name("local_tooling_recover.py")


def load_recovery_module():
    spec = importlib.util.spec_from_file_location("local_tooling_recover", SCRIPT_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load local_tooling_recover.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["local_tooling_recover"] = module
    spec.loader.exec_module(module)
    return module


class LocalToolingRecoverTests(unittest.TestCase):
    def test_selects_only_stale_allowlisted_tooling_processes(self) -> None:
        module = load_recovery_module()
        processes = module.parse_ps_output(
            """
              10     1  7200 /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild -project vibetype.xcodeproj
              11    10    10 /Applications/Xcode.app/Contents/Developer/usr/bin/xctest current-test
              12     1  8000 /usr/bin/python3 scripts/backlog_next.py --json
              13     1  9000 /Applications/Xcode.app/Contents/SharedFrameworks/SwiftBuild.framework/Versions/A/PlugIns/SWBBuildService.bundle/Contents/MacOS/SWBBuildService
              14    13  9000 /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -v -E -dM -isysroot SDK -x c -c /dev/null
            """
        )

        candidates = module.select_stale_processes(
            processes,
            stale_after_seconds=60,
            current_pid=99999,
        )

        self.assertEqual(
            [candidate.kind for candidate in candidates],
            ["clang_toolchain_probe", "xcodebuild", "swift_build_service"],
        )
        self.assertNotIn(12, [candidate.pid for candidate in candidates])
        self.assertNotIn(11, [candidate.pid for candidate in candidates])

    def test_artifact_candidates_are_repo_and_project_scoped(self) -> None:
        module = load_recovery_module()

        with tempfile.TemporaryDirectory() as root_dir, tempfile.TemporaryDirectory() as home_dir:
            root = Path(root_dir)
            script_cache = root / "scripts" / "__pycache__"
            script_cache.mkdir(parents=True)
            derived_data = (
                Path(home_dir)
                / "Library"
                / "Developer"
                / "Xcode"
                / "DerivedData"
            )
            (derived_data / "vibetype-abc").mkdir(parents=True)
            (derived_data / "OtherProject-abc").mkdir(parents=True)

            candidates = module.artifact_candidates(root, home=Path(home_dir))

        self.assertEqual(
            sorted(path.name for path in candidates),
            ["__pycache__", "vibetype-abc"],
        )

    def test_parse_elapsed_time_formats(self) -> None:
        module = load_recovery_module()

        self.assertEqual(module.parse_elapsed_seconds("42"), 42)
        self.assertEqual(module.parse_elapsed_seconds("03:04"), 184)
        self.assertEqual(module.parse_elapsed_seconds("02:03:04"), 7384)
        self.assertEqual(module.parse_elapsed_seconds("1-02:03:04"), 93784)

    def test_dry_run_does_not_remove_artifacts(self) -> None:
        module = load_recovery_module()

        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            script_cache = root / "scripts" / "__pycache__"
            script_cache.mkdir(parents=True)
            result = module.remove_artifacts([script_cache], apply=False)

            self.assertTrue(script_cache.exists())
            self.assertEqual(result["matched"], [str(script_cache)])
            self.assertEqual(result["removed"], [])


if __name__ == "__main__":
    unittest.main()
