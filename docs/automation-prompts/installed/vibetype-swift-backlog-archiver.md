---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-backlog-archiver
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Backlog Archiver

## Purpose

Runs the completed-backlog archive workflow, moving verified done task files from active backlog into backlog/done when the archive script reports safe moves.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-backlog-archiver` |
| kind | `cron` |
| name | `VibeType Swift Backlog Archiver` |
| status | `ACTIVE` |
| rrule | `FREQ=MINUTELY;INTERVAL=15` |
| model | `gpt-5.4-mini` |
| reasoningEffort | `low` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1782075144575` / `2026-06-21T20:52:24.575000Z` |
| updated_at | `1782119750812` / `2026-06-22T09:15:50.812000Z` |
| promptSource | `docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-backlog-archiver/automation.toml` |
| promptLength | `910` characters |

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
Run one scheduled VibeType Swift Backlog Archiver pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md. The runbook is the runtime contract for reading order, safety limits, archive script, selector readback, verification, checkpoint commits, and final report. Stop and report the blocker if the runbook cannot be read. Do not claim backlog tasks, implement product code, resolve blockers, groom tasks, or run the broad MCP cleanup script. Close only resources clearly started by this run. Then, when the thread-management tool is available, request archive of the current automation thread by calling set_thread_archived with archived true and no threadId. The final report must include Cleanup for run-owned resources only, plus Thread archive: requested or Thread archive: unavailable.
```
