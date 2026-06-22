#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any


DEFAULT_TARGET_CWD = "/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift"
HOUSEKEEPING_ID = "vibetype-swift-archive-completed-automation-threads"
THREAD_TOOL_NAMES = {"list_threads", "read_thread", "set_thread_archived"}
SELF_ARCHIVE_CLEANUP_TOOL_NAMES = THREAD_TOOL_NAMES | {"exec_command"}


@dataclass(frozen=True)
class AutomationDef:
    id: str
    name: str
    status: str
    path: str


@dataclass(frozen=True)
class ThreadRow:
    id: str
    title: str
    cwd: str
    thread_source: str
    archived: int
    archived_at: int | None
    created_at: int
    updated_at: int
    updated_at_ms: int | None
    rollout_path: str
    first_user_message: str


@dataclass
class LogSummary:
    exists: bool
    session_cwd: str | None = None
    thread_source: str | None = None
    automation_id: str | None = None
    automation_name: str | None = None
    task_terminal: bool = False
    final_answer: bool = False
    user_after_automation_prompt: bool = False
    missing_tool_calls: list[dict[str, str]] | None = None


def _parse_scalar(text: str, key: str) -> str:
    match = re.search(rf'^{re.escape(key)}\s*=\s*"([^"]*)"', text, re.MULTILINE)
    return match.group(1) if match else ""


def _parse_cwds(text: str) -> list[str]:
    match = re.search(r"^cwds\s*=\s*\[(.*)\]", text, re.MULTILINE)
    if match:
        return re.findall(r'"([^"]*)"', match.group(1))
    cwd = _parse_scalar(text, "cwd")
    return [cwd] if cwd else []


def load_automation_defs(codex_home: Path, target_cwd: str) -> list[AutomationDef]:
    automations: list[AutomationDef] = []
    root = codex_home / "automations"
    for path in sorted(root.glob("*/automation.toml")):
        text = path.read_text(encoding="utf-8", errors="replace")
        if target_cwd not in _parse_cwds(text):
            continue
        automation_id = _parse_scalar(text, "id")
        name = _parse_scalar(text, "name")
        status = _parse_scalar(text, "status")
        if automation_id and name:
            automations.append(
                AutomationDef(
                    id=automation_id,
                    name=name,
                    status=status,
                    path=str(path),
                )
            )
    return automations


def choose_state_dbs(codex_home: Path) -> list[Path]:
    candidates = [
        codex_home / "sqlite" / "state_5.sqlite",
        codex_home / "state_5.sqlite",
    ]
    state_dbs: list[Path] = []
    for path in candidates:
        if path.exists():
            resolved = path.resolve()
            if resolved not in [existing.resolve() for existing in state_dbs]:
                state_dbs.append(path)
    if state_dbs:
        return state_dbs
    raise FileNotFoundError("state_5.sqlite not found under Codex home")


def connect_rows(state_db: Path, target_cwd: str) -> list[ThreadRow]:
    con = sqlite3.connect(state_db)
    con.row_factory = sqlite3.Row
    try:
        rows = con.execute(
            """
            SELECT
                id,
                title,
                cwd,
                thread_source,
                archived,
                archived_at,
                created_at,
                updated_at,
                updated_at_ms,
                rollout_path,
                first_user_message
            FROM threads
            WHERE archived = 0
              AND cwd = ?
            ORDER BY updated_at DESC
            """,
            (target_cwd,),
        ).fetchall()
    finally:
        con.close()
    return [ThreadRow(**dict(row)) for row in rows]


def _message_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts: list[str] = []
    for item in content:
        if isinstance(item, dict):
            text = item.get("text") or item.get("input_text") or item.get("content")
            if isinstance(text, str):
                parts.append(text)
    return "\n".join(parts)


def _automation_line_value(text: str, field: str) -> str | None:
    prefix = f"{field}:"
    for line in text.splitlines():
        if line.startswith(prefix):
            return line.split(":", 1)[1].strip()
    return None


def _is_injected_context_message(text: str) -> bool:
    stripped = text.lstrip()
    return stripped.startswith(
        (
            "<skill>",
            "<environment_context>",
            "# AGENTS.md instructions for ",
        )
    )


def read_log_summary(path_text: str) -> LogSummary:
    path = Path(path_text) if path_text else Path("")
    if not path.exists():
        return LogSummary(exists=False, missing_tool_calls=[])

    calls: dict[str, str] = {}
    outputs: set[str] = set()
    summary = LogSummary(exists=True, missing_tool_calls=[])
    seen_automation_prompt = False

    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                continue

            item_type = item.get("type")
            payload = item.get("payload") or {}

            if item_type == "session_meta":
                summary.session_cwd = payload.get("cwd") or summary.session_cwd
                summary.thread_source = (
                    payload.get("thread_source") or summary.thread_source
                )
                continue

            if item_type == "event_msg":
                event_type = payload.get("type")
                if event_type in {"task_complete", "task_failed"}:
                    summary.task_terminal = True
                continue

            if item_type != "response_item" or not isinstance(payload, dict):
                continue

            payload_type = payload.get("type")
            if payload_type == "function_call":
                call_id = payload.get("call_id")
                name = payload.get("name")
                if isinstance(call_id, str) and isinstance(name, str):
                    calls[call_id] = name
                continue

            if payload_type == "function_call_output":
                call_id = payload.get("call_id")
                if isinstance(call_id, str):
                    outputs.add(call_id)
                continue

            if payload_type != "message":
                continue

            role = payload.get("role")
            text = _message_text(payload.get("content"))
            phase = payload.get("phase")
            if role == "assistant" and phase == "final_answer":
                summary.final_answer = True
            if role != "user":
                continue

            if text.startswith("Automation:"):
                if seen_automation_prompt:
                    summary.user_after_automation_prompt = True
                seen_automation_prompt = True
                summary.automation_name = (
                    _automation_line_value(text, "Automation")
                    or summary.automation_name
                )
                summary.automation_id = (
                    _automation_line_value(text, "Automation ID")
                    or summary.automation_id
                )
            elif seen_automation_prompt and not _is_injected_context_message(text):
                summary.user_after_automation_prompt = True

    summary.missing_tool_calls = [
        {"call_id": call_id, "name": name}
        for call_id, name in calls.items()
        if call_id not in outputs
    ]
    return summary


def match_automation(
    row: ThreadRow, summary: LogSummary, automations: list[AutomationDef]
) -> AutomationDef | None:
    haystacks = [
        row.title or "",
        row.first_user_message or "",
        summary.automation_id or "",
        summary.automation_name or "",
    ]
    for automation in automations:
        if summary.automation_id == automation.id:
            return automation
        if any(f"Automation ID: {automation.id}" in value for value in haystacks):
            return automation
    for automation in automations:
        if summary.automation_name == automation.name:
            return automation
        if row.thread_source == "automation" and row.title == automation.name:
            return automation
        if row.title.startswith(f"Automation: {automation.name}"):
            return automation
        if row.first_user_message.startswith(f"Automation: {automation.name}"):
            return automation
    return None


def classify_row(
    row: ThreadRow,
    summary: LogSummary,
    automation: AutomationDef | None,
    *,
    target_cwd: str,
    stale_seconds: int,
    thread_tool_stale_seconds: int,
    now: int,
) -> tuple[bool, str]:
    if row.cwd != target_cwd:
        return False, "out_of_scope"
    if automation is None:
        return False, "manual_or_unclear"
    registry_automation_prompt = row.title.startswith(
        "Automation:"
    ) or row.first_user_message.startswith("Automation:")
    if row.thread_source != "automation" and not registry_automation_prompt:
        return False, "manual_or_unclear"
    if summary.exists and summary.session_cwd and summary.session_cwd != target_cwd:
        return False, "out_of_scope_log"
    if (
        summary.exists
        and summary.thread_source
        and summary.thread_source not in {"automation", "user"}
    ):
        return False, "not_automation_log"
    if summary.user_after_automation_prompt:
        return False, "manual_or_unclear"

    terminal = summary.task_terminal or summary.final_answer
    if terminal:
        return True, "terminal_automation"

    age_seconds = max(0, now - int(row.updated_at or 0))
    missing = summary.missing_tool_calls or []
    missing_thread_tools_only = bool(missing) and all(
        item.get("name") in THREAD_TOOL_NAMES for item in missing
    )
    missing_archive_tools_only = bool(missing) and all(
        item.get("name") == "set_thread_archived" for item in missing
    )
    missing_self_archive_cleanup_tools_only = (
        bool(missing)
        and any(item.get("name") == "set_thread_archived" for item in missing)
        and all(item.get("name") in SELF_ARCHIVE_CLEANUP_TOOL_NAMES for item in missing)
    )
    missing_housekeeping_cleanup_tools_only = (
        bool(missing)
        and automation.id == HOUSEKEEPING_ID
        and any(item.get("name") in THREAD_TOOL_NAMES for item in missing)
        and all(item.get("name") in SELF_ARCHIVE_CLEANUP_TOOL_NAMES for item in missing)
    )
    no_missing_tools = not missing
    if missing_archive_tools_only:
        return True, "self_archive_thread_tool_hung"
    if missing_self_archive_cleanup_tools_only and age_seconds >= stale_seconds:
        return True, "stale_self_archive_cleanup_hung"
    if (
        automation.id == HOUSEKEEPING_ID
        and missing_thread_tools_only
        and age_seconds >= thread_tool_stale_seconds
    ):
        return True, "stale_housekeeping_thread_tool_hung"
    if (
        missing_housekeeping_cleanup_tools_only
        and age_seconds >= thread_tool_stale_seconds
    ):
        return True, "stale_housekeeping_thread_tool_hung"
    if age_seconds >= stale_seconds and no_missing_tools:
        return True, "stale_inactive_automation"
    if (
        automation.id == HOUSEKEEPING_ID
        and age_seconds >= stale_seconds
        and (no_missing_tools or missing_thread_tools_only)
    ):
        return True, "stale_housekeeping_inactive"

    return False, "active_or_pending"


def discover(
    *,
    codex_home: Path,
    target_cwd: str,
    stale_seconds: int,
    thread_tool_stale_seconds: int,
    now: int,
) -> dict[str, Any]:
    automations = load_automation_defs(codex_home, target_cwd)
    state_dbs = choose_state_dbs(codex_home)
    eligible: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []
    allowed_active: list[dict[str, Any]] = []

    scanned_unarchived_in_scope = 0
    for state_db in state_dbs:
        rows = connect_rows(state_db, target_cwd)
        scanned_unarchived_in_scope += len(rows)
        for row in rows:
            summary = read_log_summary(row.rollout_path)
            automation = match_automation(row, summary, automations)
            is_eligible, reason = classify_row(
                row,
                summary,
                automation,
                target_cwd=target_cwd,
                stale_seconds=stale_seconds,
                thread_tool_stale_seconds=thread_tool_stale_seconds,
                now=now,
            )
            item = {
                "state_db": str(state_db),
                "id": row.id,
                "automation_id": automation.id if automation else None,
                "automation_name": automation.name if automation else None,
                "reason": reason,
                "updated_at": row.updated_at,
                "rollout_path": row.rollout_path,
                "missing_tool_calls": summary.missing_tool_calls or [],
            }
            if is_eligible:
                eligible.append(item)
            elif reason == "active_or_pending":
                allowed_active.append(item)
            else:
                skipped.append(item)

    return {
        "state_dbs": [str(path) for path in state_dbs],
        "target_cwd": target_cwd,
        "automation_ids": [automation.id for automation in automations],
        "automation_names": [automation.name for automation in automations],
        "scanned_unarchived_in_scope": scanned_unarchived_in_scope,
        "eligible": eligible,
        "eligible_count": len(eligible),
        "allowed_active": allowed_active,
        "allowed_active_count": len(allowed_active),
        "skipped": skipped,
        "skipped_count": len(skipped),
    }


def archive_once(
    *,
    codex_home: Path,
    state_db: Path,
    eligible: list[dict[str, Any]],
    now: int,
) -> dict[str, Any]:
    if not eligible:
        return {"archived_count": 0, "moved_count": 0, "backup_path": None}

    backup_path = state_db.with_name(
        f"{state_db.name}.bak-vibetype-thread-cleanup-{now}"
    )
    source_con = sqlite3.connect(state_db)
    try:
        backup_con = sqlite3.connect(backup_path)
        try:
            source_con.backup(backup_con)
        finally:
            backup_con.close()
    finally:
        source_con.close()

    archive_dir = codex_home / "archived_sessions"
    archive_dir.mkdir(parents=True, exist_ok=True)

    archived_count = 0
    moved_count = 0
    con = sqlite3.connect(state_db)
    try:
        for item in eligible:
            rollout_path = item["rollout_path"]
            source_path = Path(rollout_path) if rollout_path else None
            archived_path = source_path
            if source_path and str(source_path).startswith(str(codex_home / "sessions")):
                archived_path = archive_dir / source_path.name
                if source_path.exists() and not archived_path.exists():
                    shutil.move(str(source_path), str(archived_path))
                    moved_count += 1
            cursor = con.execute(
                """
                UPDATE threads
                   SET archived = 1,
                       archived_at = ?,
                       rollout_path = ?
                 WHERE id = ?
                   AND archived = 0
                """,
                (now, str(archived_path) if archived_path else rollout_path, item["id"]),
            )
            archived_count += max(0, cursor.rowcount)
        con.commit()
    finally:
        con.close()

    return {
        "archived_count": archived_count,
        "moved_count": moved_count,
        "backup_path": str(backup_path),
    }


def _group_by_state_db(items: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for item in items:
        grouped.setdefault(str(item["state_db"]), []).append(item)
    return grouped


def run(args: argparse.Namespace) -> dict[str, Any]:
    codex_home = Path(args.codex_home).expanduser()
    target_cwd = args.target_cwd
    stale_seconds = int(args.stale_minutes * 60)
    thread_tool_stale_seconds = int(args.thread_tool_stale_minutes * 60)
    now = int(args.now or time.time())

    passes: list[dict[str, Any]] = []
    archived_total = 0
    moved_total = 0
    backup_paths: list[str] = []

    for pass_index in range(1, args.max_passes + 1):
        report = discover(
            codex_home=codex_home,
            target_cwd=target_cwd,
            stale_seconds=stale_seconds,
            thread_tool_stale_seconds=thread_tool_stale_seconds,
            now=now,
        )
        pass_report: dict[str, Any] = {
            "pass": pass_index,
            "eligible_count": report["eligible_count"],
            "allowed_active_count": report["allowed_active_count"],
            "skipped_count": report["skipped_count"],
            "eligible": report["eligible"],
            "allowed_active": report["allowed_active"],
        }
        if not args.apply or report["eligible_count"] == 0:
            passes.append(pass_report)
            final = report
            break

        pass_archived_count = 0
        pass_moved_count = 0
        pass_backup_paths: list[str] = []
        for state_db, eligible in _group_by_state_db(report["eligible"]).items():
            archive_report = archive_once(
                codex_home=codex_home,
                state_db=Path(state_db),
                eligible=eligible,
                now=now,
            )
            pass_archived_count += int(archive_report["archived_count"])
            pass_moved_count += int(archive_report["moved_count"])
            if archive_report["backup_path"]:
                pass_backup_paths.append(str(archive_report["backup_path"]))
        archived_total += pass_archived_count
        moved_total += pass_moved_count
        backup_paths.extend(pass_backup_paths)
        pass_report.update(
            {
                "archived_count": pass_archived_count,
                "moved_count": pass_moved_count,
                "backup_paths": pass_backup_paths,
            }
        )
        passes.append(pass_report)

        if pass_archived_count == 0:
            final = discover(
                codex_home=codex_home,
                target_cwd=target_cwd,
                stale_seconds=stale_seconds,
                thread_tool_stale_seconds=thread_tool_stale_seconds,
                now=now,
            )
            break
    else:
        final = discover(
            codex_home=codex_home,
            target_cwd=target_cwd,
            stale_seconds=stale_seconds,
            thread_tool_stale_seconds=thread_tool_stale_seconds,
            now=now,
        )

    status = "applied" if args.apply else "dry-run"
    return {
        "status": status,
        "target_cwd": target_cwd,
        "state_dbs": final["state_dbs"],
        "automation_ids": final["automation_ids"],
        "automation_names": final["automation_names"],
        "passes": passes,
        "archived_count": archived_total,
        "moved_count": moved_total,
        "backup_paths": backup_paths,
        "remaining_eligible_count": final["eligible_count"],
        "remaining_eligible": final["eligible"],
        "allowed_active_count": final["allowed_active_count"],
        "allowed_active": final["allowed_active"],
        "skipped_count": final["skipped_count"],
        "skipped": final["skipped"],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Archive eligible Codex automation threads for one cwd."
    )
    parser.add_argument("--codex-home", default=str(Path.home() / ".codex"))
    parser.add_argument("--target-cwd", default=DEFAULT_TARGET_CWD)
    parser.add_argument("--stale-minutes", type=int, default=30)
    parser.add_argument("--thread-tool-stale-minutes", type=int, default=2)
    parser.add_argument("--max-passes", type=int, default=10)
    parser.add_argument("--now", type=int, default=0)
    parser.add_argument("--apply", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser


def parse_args() -> argparse.Namespace:
    return build_parser().parse_args()


def parse_args_for_test(argv: list[str]) -> argparse.Namespace:
    return build_parser().parse_args(argv)


def main() -> int:
    args = parse_args()
    report = run(args)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print(
            "status={status} archived_count={archived_count} "
            "remaining_eligible_count={remaining_eligible_count} "
            "allowed_active_count={allowed_active_count}".format(**report)
        )
    if not args.apply:
        return 0
    return 0 if report["remaining_eligible_count"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
