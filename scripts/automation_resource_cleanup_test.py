#!/usr/bin/env python3
"""Focused tests for automation_resource_cleanup.py."""

from __future__ import annotations

import unittest

from automation_resource_cleanup import (
    match_process_kind,
    parse_elapsed_seconds,
    parse_ps_output,
    select_candidates,
    terminate_candidates,
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

    def test_other_owner_apply_requires_operator(self) -> None:
        rows = """
codex3 200 1 200 00:04 2048 0.0 npm exec @playwright/mcp@latest
"""
        candidates = select_candidates(
            parse_ps_output(rows),
            owners={"codex3"},
            min_age_seconds=1,
            protected=set(),
        )
        result = terminate_candidates(
            candidates,
            apply=True,
            grace_seconds=0,
            current_user="me",
        )
        self.assertEqual(len(result["permission_required"]), 1)
        self.assertEqual(result["permission_required"][0]["owner"], "codex3")


if __name__ == "__main__":
    unittest.main()
