---
kind: installed-automation-prompt
automationLayer: per-user-automation-registry
automationId: vibetype-swift-tooling-unblocker
status: active
inspectedDate: 2026-06-22
---

# VibeType Swift Tooling Unblocker

## Purpose

Repairs local Xcode/build/test/tooling blockers and reruns a bounded health check so normal backlog automation can proceed.

## Restore Fields

| Field | Value |
| --- | --- |
| id | `vibetype-swift-tooling-unblocker` |
| kind | `cron` |
| name | `VibeType Swift Tooling Unblocker` |
| status | `ACTIVE` |
| rrule | `FREQ=MINUTELY;INTERVAL=15` |
| model | `gpt-5.5` |
| reasoningEffort | `xhigh` |
| executionEnvironment | `local` |
| cwds | `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift` |
| created_at | `1782072101740` / `2026-06-21T20:01:41.740000Z` |
| updated_at | `1782119755780` / `2026-06-22T09:15:55.780000Z` |
| promptSource | `docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md` |
| sourceSnapshot | `/Users/eugenepotapenko/.codex/automations/vibetype-swift-tooling-unblocker/automation.toml` |
| promptLength | `1100` characters |

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
Run one scheduled VibeType Swift Tooling Unblocker pass by following the versioned runbook at /Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift/docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md. The runbook is the runtime contract for mandatory local tooling recovery, bounded Xcode health check, selector readback, cleanup, checkpoint handling when files change, and final report. Fix local Xcode/build/test/simulator/cache/DerivedData/missing-local-tool blockers automatically; do not ask the user to clear local tooling. Do not perform destructive database or object-storage operations, destructive Git rollback, external account login, payment/account changes, manual system privacy approval, or broad MCP cleanup. Close only resources clearly started by this run. Then, when the thread-management tool is available, request archive of the current automation thread by calling set_thread_archived with archived true and no threadId. The final report must include Cleanup for run-owned resources only, plus Thread archive: requested or Thread archive: unavailable.
```
