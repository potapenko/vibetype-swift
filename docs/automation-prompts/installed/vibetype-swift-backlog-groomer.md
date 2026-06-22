---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-backlog-groomer
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Backlog Groomer

## Purpose

Maintains small executable backlog/spec/workflow tasks for the macOS MVP without implementing Swift product code.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-backlog-groomer` |
| kind | `cron` |
| name | `VibeType Swift Backlog Groomer` |
| status | `ACTIVE` |
| rrule | `FREQ=HOURLY;INTERVAL=2` |
| model | `gpt-5.5` |
| reasoningEffort | `xhigh` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1781966689120` / `2026-06-20T14:44:49.120000Z` |
| updated_at | `1782119749495` / `2026-06-22T09:15:49.495000Z` |
| promptSource | `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-backlog-groomer/automation.toml` |
| promptLength | `831` characters |

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
Run one scheduled VibeType Swift Backlog Groomer pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md. The runbook is the runtime contract for reading order, safety limits, selector/script, verification, checkpoint commits, and final report. Stop and report the blocker if the runbook cannot be read. Do not run the broad MCP cleanup script; this automation may close only resources clearly started by this run. Then, when the thread-management tool is available, request archive of the current automation thread by calling set_thread_archived with archived true and no threadId. The final report must include Cleanup for run-owned resources only, plus Thread archive: requested or Thread archive: unavailable.
```
