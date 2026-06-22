from __future__ import annotations

import json
import sqlite3
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_ROOT = ROOT / "scripts"
if str(SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SCRIPT_ROOT))

import archive_codex_threads


TARGET_CWD = "/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift"
OTHER_CWD = "/Users/eugenepotapenko/Projects/playphrase.me/source-prep-ssh"


def write_jsonl(
    path: Path,
    thread_id: str,
    automation_id: str,
    *,
    terminal: bool,
    injected_skill_context: bool = False,
    missing_tool_name: str | None = None,
) -> None:
    items = [
        {
            "timestamp": "2026-06-22T09:00:00Z",
            "type": "session_meta",
            "payload": {
                "id": thread_id,
                "cwd": TARGET_CWD,
                "thread_source": "automation",
            },
        },
        {
            "timestamp": "2026-06-22T09:00:01Z",
            "type": "response_item",
            "payload": {
                "type": "message",
                "role": "user",
                "content": [
                    {
                        "type": "input_text",
                        "text": (
                            "Automation: VibeType Swift Archive Completed Automation Threads\n"
                            f"Automation ID: {automation_id}\n"
                        ),
                    }
                ],
            },
        },
    ]
    if injected_skill_context:
        items.append(
            {
                "timestamp": "2026-06-22T09:00:01Z",
                "type": "response_item",
                "payload": {
                    "type": "message",
                    "role": "user",
                    "content": [
                        {
                            "type": "input_text",
                            "text": "<skill>\n<name>source-prep-ssh</name>\n</skill>",
                        }
                    ],
                },
            }
        )
    if terminal:
        items.append(
            {
                "timestamp": "2026-06-22T09:00:02Z",
                "type": "event_msg",
                "payload": {"type": "task_complete"},
            }
        )
    if missing_tool_name:
        items.append(
            {
                "timestamp": "2026-06-22T09:00:03Z",
                "type": "response_item",
                "payload": {
                    "type": "function_call",
                    "call_id": f"call-{thread_id}",
                    "name": missing_tool_name,
                },
            }
        )
    path.write_text(
        "\n".join(json.dumps(item, ensure_ascii=False) for item in items) + "\n",
        encoding="utf-8",
    )


def create_threads_table(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(path)
    try:
        con.execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                cwd TEXT NOT NULL,
                thread_source TEXT NOT NULL,
                archived INTEGER NOT NULL,
                archived_at INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                updated_at_ms INTEGER,
                rollout_path TEXT NOT NULL,
                first_user_message TEXT NOT NULL
            )
            """
        )
        con.commit()
    finally:
        con.close()


class VibeTypeArchiveCodexThreadsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        self.codex_home = Path(self.tempdir.name)
        (self.codex_home / "automations" / "vibetype-swift-archive-completed-automation-threads").mkdir(
            parents=True
        )
        (self.codex_home / "automations" / "vibetype-swift-implementer").mkdir(
            parents=True
        )
        (self.codex_home / "sessions" / "2026" / "06" / "22").mkdir(parents=True)
        (self.codex_home / "archived_sessions").mkdir()
        (
            self.codex_home
            / "automations"
            / "vibetype-swift-archive-completed-automation-threads"
            / "automation.toml"
        ).write_text(
            '\n'.join(
                [
                    'id = "vibetype-swift-archive-completed-automation-threads"',
                    'name = "VibeType Swift Archive Completed Automation Threads"',
                    'status = "ACTIVE"',
                    f'cwds = ["{TARGET_CWD}"]',
                ]
            ),
            encoding="utf-8",
        )
        (
            self.codex_home
            / "automations"
            / "vibetype-swift-implementer"
            / "automation.toml"
        ).write_text(
            '\n'.join(
                [
                    'id = "vibetype-swift-implementer"',
                    'name = "VibeType Swift Implementer"',
                    'status = "ACTIVE"',
                    f'cwds = ["{TARGET_CWD}"]',
                ]
            ),
            encoding="utf-8",
        )
        self.state_db = self.codex_home / "state_5.sqlite"
        create_threads_table(self.state_db)

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def insert_thread(
        self,
        thread_id: str,
        automation_id: str,
        *,
        terminal: bool = True,
        cwd: str = TARGET_CWD,
        thread_source: str = "automation",
        updated_at: int = 1_782_120_000,
        state_db: Path | None = None,
        injected_skill_context: bool = False,
        missing_tool_name: str | None = None,
    ) -> Path:
        rollout_path = (
            self.codex_home
            / "sessions"
            / "2026"
            / "06"
            / "22"
            / f"rollout-2026-06-22T10-00-00-{thread_id}.jsonl"
        )
        write_jsonl(
            rollout_path,
            thread_id,
            automation_id,
            terminal=terminal,
            injected_skill_context=injected_skill_context,
            missing_tool_name=missing_tool_name,
        )
        first_user = (
            "Automation: VibeType Swift Archive Completed Automation Threads\n"
            f"Automation ID: {automation_id}\n"
        )
        con = sqlite3.connect(state_db or self.state_db)
        try:
            con.execute(
                """
                INSERT INTO threads (
                    id, title, cwd, thread_source, archived, archived_at,
                    created_at, updated_at, updated_at_ms, rollout_path,
                    first_user_message
                ) VALUES (?, ?, ?, ?, 0, NULL, ?, ?, ?, ?, ?)
                """,
                (
                    thread_id,
                    first_user,
                    cwd,
                    thread_source,
                    updated_at,
                    updated_at,
                    updated_at * 1000,
                    str(rollout_path),
                    first_user,
                ),
            )
            con.commit()
        finally:
            con.close()
        return rollout_path

    def test_dry_run_finds_all_registry_rows_not_just_one_visible_page(self) -> None:
        self.insert_thread(
            "019eee69-3dd7-7ab1-ad7a-abcbff6b2387",
            "vibetype-swift-archive-completed-automation-threads",
        )
        self.insert_thread(
            "019eeeba-58f9-7272-86d0-87167a38a4f0",
            "vibetype-swift-implementer",
        )
        self.insert_thread(
            "019eeead-744a-78a2-961c-6834cb00a0d3",
            "vibetype-swift-archive-completed-automation-threads",
            cwd=OTHER_CWD,
        )
        self.insert_thread(
            "019eeeba-active",
            "vibetype-swift-implementer",
            terminal=False,
            updated_at=1_782_122_950,
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["remaining_eligible_count"], 2)
        self.assertEqual(report["allowed_active_count"], 1)
        self.assertEqual(
            {
                item["id"]
                for item in report["remaining_eligible"]
            },
            {
                "019eee69-3dd7-7ab1-ad7a-abcbff6b2387",
                "019eeeba-58f9-7272-86d0-87167a38a4f0",
            },
        )

    def test_apply_archives_and_moves_session_files(self) -> None:
        rollout_path = self.insert_thread(
            "019eee69-3dd7-7ab1-ad7a-abcbff6b2387",
            "vibetype-swift-archive-completed-automation-threads",
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
                "--apply",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["archived_count"], 1)
        self.assertEqual(report["moved_count"], 1)
        self.assertEqual(report["remaining_eligible_count"], 0)
        self.assertFalse(rollout_path.exists())

        archived_path = self.codex_home / "archived_sessions" / rollout_path.name
        self.assertTrue(archived_path.exists())
        self.assertTrue(report["backup_paths"])

        con = sqlite3.connect(self.state_db)
        try:
            archived, rollout = con.execute(
                "SELECT archived, rollout_path FROM threads WHERE id = ?",
                ("019eee69-3dd7-7ab1-ad7a-abcbff6b2387",),
            ).fetchone()
        finally:
            con.close()
        self.assertEqual(archived, 1)
        self.assertEqual(rollout, str(archived_path))

    def test_apply_archives_all_eligible_rows_in_one_batch(self) -> None:
        self.insert_thread(
            "019eee69-batch-one",
            "vibetype-swift-archive-completed-automation-threads",
        )
        self.insert_thread(
            "019eee69-batch-two",
            "vibetype-swift-implementer",
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
                "--apply",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["archived_count"], 2)
        self.assertEqual(report["remaining_eligible_count"], 0)

        con = sqlite3.connect(self.state_db)
        try:
            rows = con.execute(
                """
                SELECT id, archived
                  FROM threads
                 WHERE id IN ('019eee69-batch-one', '019eee69-batch-two')
                 ORDER BY id
                """
            ).fetchall()
        finally:
            con.close()
        self.assertEqual(rows, [("019eee69-batch-one", 1), ("019eee69-batch-two", 1)])

    def test_user_source_automation_prompt_is_eligible(self) -> None:
        self.insert_thread(
            "019eee69-user-source",
            "vibetype-swift-implementer",
            thread_source="user",
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["remaining_eligible_count"], 1)
        self.assertEqual(report["remaining_eligible"][0]["id"], "019eee69-user-source")

    def test_missing_set_thread_archived_is_self_archive_hanging(self) -> None:
        self.insert_thread(
            "019eee69-self-archive",
            "vibetype-swift-implementer",
            terminal=False,
            updated_at=1_782_122_990,
            missing_tool_name="set_thread_archived",
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["remaining_eligible_count"], 1)
        self.assertEqual(
            report["remaining_eligible"][0]["reason"],
            "self_archive_thread_tool_hung",
        )

    def test_scans_both_state_database_locations(self) -> None:
        sqlite_state_db = self.codex_home / "sqlite" / "state_5.sqlite"
        create_threads_table(sqlite_state_db)
        self.insert_thread(
            "019eee69-root-state",
            "vibetype-swift-archive-completed-automation-threads",
            state_db=self.state_db,
        )
        self.insert_thread(
            "019eee69-sqlite-state",
            "vibetype-swift-archive-completed-automation-threads",
            state_db=sqlite_state_db,
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["remaining_eligible_count"], 2)
        self.assertEqual(
            {item["id"] for item in report["remaining_eligible"]},
            {"019eee69-root-state", "019eee69-sqlite-state"},
        )

    def test_injected_skill_context_does_not_make_automation_manual(self) -> None:
        self.insert_thread(
            "019eee69-injected-skill",
            "vibetype-swift-implementer",
            thread_source="user",
            terminal=False,
            injected_skill_context=True,
        )

        args = archive_codex_threads.parse_args_for_test(
            [
                "--codex-home",
                str(self.codex_home),
                "--target-cwd",
                TARGET_CWD,
                "--now",
                "1782123000",
            ]
        )
        report = archive_codex_threads.run(args)

        self.assertEqual(report["remaining_eligible_count"], 1)
        self.assertEqual(
            report["remaining_eligible"][0]["reason"], "stale_inactive_automation"
        )

if __name__ == "__main__":
    unittest.main()
