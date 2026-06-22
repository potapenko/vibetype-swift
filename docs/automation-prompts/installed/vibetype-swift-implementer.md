---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-implementer
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Implementer

## Purpose

Runs one selector-approved product implementation iteration with claim/completion checkpoints, verification, cleanup, and thread self-archive reporting.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-implementer` |
| kind | `cron` |
| name | `VibeType Swift Implementer` |
| status | `ACTIVE` |
| rrule | `FREQ=MINUTELY;INTERVAL=15` |
| model | `gpt-5.5` |
| reasoningEffort | `xhigh` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1781965982356` / `2026-06-20T14:33:02.356000Z` |
| updated_at | `1782119754804` / `2026-06-22T09:15:54.804000Z` |
| promptSource | `docs/automation-prompts/runbooks/vibetype-swift-implementer.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-implementer/automation.toml` |
| promptLength | `1250` characters |

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
Run one scheduled VibeType Swift Implementer pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/vibetype-swift-implementer.md. The runbook is the runtime contract for reading order, safety limits, selector/script, verification, checkpoint commits, and final report. Stop and report the blocker if the runbook cannot be read. Mandatory final cleanup gate: after verification/checkpoint handling and before the final response, run exactly `python3 scripts/automation_resource_cleanup.py` from the repository root. The script takes no parameters and performs current-user killall cleanup for Codex MCP/helper processes. Include the cleanup JSON summary and any residual current-user pid/owner/command details; do not inspect or clean processes owned by other OS users; do not claim cleanup succeeded while residual current-user resources remain. Then, when the thread-management tool is available, request archive of the current automation thread by calling set_thread_archived with archived true and no threadId. The final report must include Cleanup with terminated resources and residual resources, plus Thread archive: requested or Thread archive: unavailable.
```
