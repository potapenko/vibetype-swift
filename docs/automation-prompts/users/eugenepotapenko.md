---
kind: automation-user-inventory
automationLayer: per-user-automation-registry
localUser: eugenepotapenko
status: inspected
---

# eugenepotapenko Automation Inventory

Inventory date: 2026-06-21
Inspected user home: `/Users/eugenepotapenko`
Inspected Codex home: `/Users/eugenepotapenko/.codex`
Repository cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
Inventory status: inspected

## Summary

| Automation id | Name | Status | Schedule | Model | Environment | Prompt source |
| --- | --- | --- | --- | --- | --- | --- |
| `vibetype-swift-backlog-groomer` | VibeType Swift Backlog Groomer | active | `FREQ=HOURLY;INTERVAL=2` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md` |
| `vibetype-swift-blocker-resolver` | VibeType Swift Blocker Resolver | active | `FREQ=HOURLY;INTERVAL=1` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md` |
| `vibetype-swift-implementer` | VibeType Swift Implementer | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-implementer.md` |

Installed automation count for this repository: 3.
Active count for this repository: 3.
Paused count for this repository: 0.

## Installed Automations

### `vibetype-swift-backlog-groomer`

- Installed status: `ACTIVE`
- Schedule: `FREQ=HOURLY;INTERVAL=2`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md`
- Selector/script:
  `python3 scripts/backlog_next.py --json`
- Expected output: up to eight groomed backlog/spec/workflow tasks, selector
  status, verification, and scoped checkpoint commit when files change
- Safety/browser evidence contract: no browser requirement; do not implement
  Swift product code; stop on dirty/staged worktree or in-progress task; no DB
  or destructive storage operations
- Current decision: active

### `vibetype-swift-blocker-resolver`

- Installed status: `ACTIVE`
- Schedule: `FREQ=HOURLY;INTERVAL=1`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md`
- Selector/script:
  `python3 scripts/backlog_blocked_next.py --json`
- Expected output: one selected blocked task either directly resolved,
  connected to one concrete follow-up task, or recorded with an exact
  operator-only unblock action
- Safety/runtime evidence contract: stop on dirty checkout or active
  in-progress task; avoid duplicate follow-ups; use bounded verification; no
  DB or destructive storage operations
- Current decision: active

### `vibetype-swift-implementer`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/vibetype-swift-implementer.md`
- Selector/script:
  `python3 scripts/backlog_next.py --json`
- Expected output: one selected backlog iteration with claim/completion
  checkpoint commits, verification, platform smoke evidence when required, and
  cleanup report
- Safety/runtime evidence contract: explicit runtime QA decision for each
  product delta; Computer Use required for bounded app-run QA when visible
  macOS surfaces or user interactions change; no live OpenAI API in normal
  automation; no DB or destructive storage operations
- Current decision: active

## Missing Or Paused Roles

No installed automation for this repository is paused or missing during this
inventory pass.

## Verification

Commands/evidence used:

```sh
env CODEX_HOME=/Users/eugenepotapenko/.codex sh -c 'rg -n "^id =|^name =|^prompt =|^status =|^rrule =|^model =|^reasoning_effort =|^execution_environment =|^cwds =" "$CODEX_HOME"/automations/*/automation.toml'
git diff --check
git diff --cached --check
```
