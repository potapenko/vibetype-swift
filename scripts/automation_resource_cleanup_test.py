#!/usr/bin/env python3
"""Focused tests for automation_resource_cleanup.py."""

from __future__ import annotations

import io
import sys
import unittest
from unittest.mock import patch

from automation_resource_cleanup import (
    KILLALL_PROCESS_NAMES,
    main,
    match_process_kind,
    parse_elapsed_seconds,
    parse_ps_output,
    run_killall,
    select_candidates,
)


class AutomationResourceCleanupTests(unittest.TestCase):
    def test_parse_elapsed_seconds(self) -> None:
        self.assertEqual(parse_elapsed_seconds("00:02"), 2)
        self.assertEqual(parse_elapsed_seconds("01:02:03"), 3723)
        self.assertEqual(parse_elapsed_seconds("2-01:02:03"), 176523)

    def test_allowlist_matches_codex_helpers_only(self) -> None:
        self.assertEqual(
            match_process_kind(
                "npm exec @playwright/mcp@latest  "
            ),
            "playwright_mcp_npm",
        )
        self.assertEqual(
            match_process_kind(
                "node /Users/me/.npm/_npx/x/node_modules/.bin/xcodebuildmcp mcp"
            ),
            "xcodebuildmcp_node",
        )
        self.assertEqual(
            match_process_kind("/Applications/OpenWhispr.app/Contents/MacOS/OpenWhispr"),
            None,
        )
        self.assertEqual(match_process_kind("node ./normal-dev-server.js"), None)

    def test_select_candidates_filters_owner_age_and_kind(self) -> None:
        rows = """
me 100 1 100 00:02 1024 0.0 npm exec @playwright/mcp@latest
me 101 1 101 00:01 2048 0.0 npm exec @playwright/mcp@latest
other 102 1 102 00:04 2048 0.0 npm exec @playwright/mcp@latest
me 103 1 103 00:04 2048 0.0 node ./normal-dev-server.js
"""
        processes = parse_ps_output(rows)
        candidates = select_candidates(
            processes,
            owners={"me"},
            min_age_seconds=2,
            protected=set(),
        )
        self.assertEqual([candidate.pid for candidate in candidates], [100])

    def test_killall_dry_run_records_current_target_names(self) -> None:
        result = run_killall(owner="me", apply=False, grace_seconds=0)
        self.assertEqual(result["process_names"], list(KILLALL_PROCESS_NAMES))
        self.assertEqual(result["signals"], [])
        self.assertEqual(result["errors"], [])

    def test_cli_rejects_arguments(self) -> None:
        with (
            patch.object(sys, "argv", ["automation_resource_cleanup.py", "--apply"]),
            patch("sys.stderr", new_callable=io.StringIO),
        ):
            self.assertEqual(main(), 2)


if __name__ == "__main__":
    unittest.main()
