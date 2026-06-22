---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-archive-completed-automation-threads
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Archive Completed Automation Threads

## Purpose

Archives completed or safely stale Codex automation threads for this exact repository cwd, verifies the local registry has no remaining eligible threads, runs the allowed final resource cleanup gate, and requests self-archive.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-archive-completed-automation-threads` |
| kind | `cron` |
| name | `VibeType Swift Archive Completed Automation Threads` |
| status | `ACTIVE` |
| rrule | `FREQ=MINUTELY;INTERVAL=15` |
| model | `gpt-5.4-mini` |
| reasoningEffort | `low` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1782068006109` / `2026-06-21T18:53:26.109000Z` |
| updated_at | `1782125740852` / `2026-06-22T10:55:40.852000Z` |
| promptSource | `docs/automation-prompts/runbooks/archive-completed-automation-threads.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-archive-completed-automation-threads/automation.toml` |
| promptLength | `6437` characters |

## Recreation Notes

To recreate through the Codex automation tool, use `mode: create` with
the restore fields above. Use the prompt block below exactly as the
`prompt` value. If an automation with the same role already exists, view
that automation first and update it instead of creating a duplicate.

The recorded `id` is the installed local automation id observed at the
snapshot time. If the tool derives ids from names during create, verify
the resulting id after creation and update this file in the same commit.

## Installed Prompt

```text
Run one current-repository-only VibeType Swift archive-housekeeping pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/archive-completed-automation-threads.md. The runbook is the runtime contract for current-user MCP cleanup, thread-tool discovery, sequential thread-management calls, local registry fallback, current-repository installed automation inventory, readback safety gates, a single-invocation internal page-drain loop, stale interrupted, stale hanging in-progress, self-archive hanging in-progress, and housekeeping thread-tool hanging automation-run handling, visible-page counting, installed housekeeping automation readback, current-thread archive, and final reporting. Scope is exact cwd only: /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift. Mandatory final cleanup gate: after archive verification/report preparation and before the final response, run exactly `python3 scripts/automation_resource_cleanup.py` from the repository root. Include the cleanup JSON summary and any residual current-user pid/owner/command details; do not inspect or clean processes owned by other OS users. Do not inspect, read, archive, or count Codex threads from any other repository cwd.

Use thread-management tools when available, but cron sessions may not expose list_threads/read_thread/set_thread_archived. If thread tools are unavailable, do not stop at thread_tools_unavailable; run the repository local registry fallback helper instead. Do not write ad hoc SQLite queries. The only allowed registry fallback is `python3 scripts/archive_codex_threads.py --target-cwd /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift --json`, followed by `python3 scripts/archive_codex_threads.py --target-cwd /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift --apply --json` when `remaining_eligible_count > 0`. The registry fallback scans both DB locations exactly: ~/.codex/sqlite/state_5.sqlite and ~/.codex/state_5.sqlite. The helper creates backups before apply, archives every eligible row in the eligible batch, and loops until `remaining_eligible_count=0`. Success is possible only when `remaining_eligible_count=0`.

Acceptance rule for this automation: one run cleans the entire eligible batch. If the helper dry-run or apply reports eligible_count N, the pass must attempt all N eligible rows, not just one thread. Do not stop after one thread id, one page, one default-size result set, or one archived chat. If archived_count=1 while eligible_count>1, report the automation as broken instead of successful.

Call thread-management tools sequentially only: do not call list_threads/read_thread/set_thread_archived through parallel wrappers, and do not run them in parallel with shell/file reads. In this single automation invocation, repeatedly call unfiltered list_threads with the largest practical limit when thread tools are available, because the unfiltered list mirrors the sidebar and exact searches can miss sidebar-visible rows. Filter that visible page to exact cwd, read back each in-scope candidate, and count readback-eligible automation-run threads on the unfiltered visible page. Treat completed, stale interrupted, stale hanging in-progress, self-archive hanging in-progress, and this housekeeping automation's thread-tool hanging in-progress runs as archive-eligible when the runbook gates pass. A run with only missing set_thread_archived after reaching final self-archive is archive-eligible cleanup residue. For this housekeeping automation only, if readback or registry summary shows no running or pending tool call, no user continuation, no unresolved user question, no repository files attributable to that housekeeping run, and the latest visible progress has been waiting on thread-tool discovery, list_threads, read_thread, or set_thread_archived for at least 2 minutes, treat it as archive-eligible cleanup residue.

The first loop iteration is mandatory: if the first unfiltered visible page contains any readback-eligible automation-run threads, archive every eligible thread from that first visible batch even when the count is one or two. Apply the two-thread allowance only after at least one eligible visible page has already been archived in this invocation, when deciding whether to start a later page-drain pass. If the first unfiltered visible page contains zero eligible threads, still run the local registry fallback dry-run/apply and require `remaining_eligible_count=0` before success. On later fresh unfiltered visible pages, if the page contains two or fewer readback-eligible threads, leave that small residual page unarchived and exit the thread-tool page loop only after the local registry fallback also reports `remaining_eligible_count=0`; if it contains more than two, archive every eligible thread in that visible batch. After each archive batch, immediately re-run unfiltered list_threads/readbacks or the local registry helper in the same invocation so older pages can surface. Add exact installed automation id/name searches only as supplemental discovery after the unfiltered visible-page pass; never use exact searches instead of the unfiltered visible-page pass.

Treat active, pending, manual, or ambiguous current-repository candidates that do not pass stale/self-archive/thread-tool-hanging eligibility as skip reasons, not as a reason to abandon archiving separate readback-verified or registry-verified eligible threads in the same batch. Manual/user chats must remain skipped/manual_or_unclear, not archived. Stop with a blocker only if thread tools and the local registry helper are both unavailable, or if an apply pass archives zero rows while eligible rows remain. At the end, this archive-housekeeping chat must self-archive too: when set_thread_archived is available, request archive of the current housekeeping automation thread by calling set_thread_archived with archived true and no threadId. If set_thread_archived is unavailable, the next registry fallback pass must archive this completed housekeeping thread. The final report must include Cleanup with terminated resources and residual resources, first_visible_page_eligible_count, visible_page_eligible_count, registry_archived_count, registry_remaining_eligible_count, registry_allowed_active_count, registry_backup_paths, plus current_thread_archive requested or unavailable.
```
