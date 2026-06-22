---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-blocker-resolver
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Blocker Resolver

## Purpose

Sweeps blocked backlog tasks and either resolves them, records precise operator-only unblock actions, or creates/refines one concrete follow-up task.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-blocker-resolver` |
| kind | `cron` |
| name | `VibeType Swift Blocker Resolver` |
| status | `ACTIVE` |
| rrule | `FREQ=HOURLY;INTERVAL=1` |
| model | `gpt-5.5` |
| reasoningEffort | `xhigh` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1781994310808` / `2026-06-20T22:25:10.808000Z` |
| updated_at | `1782119753692` / `2026-06-22T09:15:53.692000Z` |
| promptSource | `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-blocker-resolver/automation.toml` |
| promptLength | `833` characters |

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
Run one scheduled VibeType Swift Blocker Resolver pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md. The runbook is the runtime contract for reading order, safety limits, selector/script, verification, checkpoint commits, and final report. Stop and report the blocker if the runbook cannot be read. Do not run the broad MCP cleanup script; this automation may close only resources clearly started by this run. Then, when the thread-management tool is available, request archive of the current automation thread by calling set_thread_archived with archived true and no threadId. The final report must include Cleanup for run-owned resources only, plus Thread archive: requested or Thread archive: unavailable.
```
