---
kind: automation-user-inventory
automationLayer: per-user-automation-registry
localUser: eugenepotapenko
status: inspected
---

# eugenepotapenko Automation Inventory

Inventory date: 2026-06-22
Inspected user home: `/Users/eugenepotapenko`
Inspected Codex home: `/Users/eugenepotapenko/.codex`
Repository cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
Inventory status: inspected

## Summary

| Automation id | Name | Status | Schedule | Model | Environment | Prompt source |
| --- | --- | --- | --- | --- | --- | --- |
| `vibetype-swift-backlog-archiver` | VibeType Swift Backlog Archiver | paused | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.4-mini` / `low` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md` |
| `vibetype-swift-backlog-groomer` | VibeType Swift Backlog Groomer | paused | `FREQ=HOURLY;INTERVAL=2` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md` |
| `vibetype-swift-blocker-resolver` | VibeType Swift Blocker Resolver | paused | `FREQ=HOURLY;INTERVAL=1` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md` |
| `vibetype-swift-implementer` | VibeType Swift Implementer | paused | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-implementer.md` |
| `vibetype-swift-tooling-unblocker` | VibeType Swift Tooling Unblocker | paused | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md` |
| `vibetype-swift-archive-completed-automation-threads` | VibeType Swift Archive Completed Automation Threads | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.4-mini` / `low` | `local` | `docs/automation-prompts/runbooks/archive-completed-automation-threads.md` |

Installed automation count for this repository: 6.
Active count for this repository: 1.
Paused count for this repository: 5.

Current-user MCP cleanup gate: only two installed automations may call
`python3 scripts/automation_resource_cleanup.py`:
`vibetype-swift-implementer`, once at the end of an implementation run, and
`vibetype-swift-archive-completed-automation-threads`, once at the end of each
15-minute housekeeping run. The script takes no parameters, ignores processes
owned by other OS users, and runs current-user killall cleanup for the
allowlisted Codex helper/MCP process names.

All other installed automations must not call
`python3 scripts/automation_resource_cleanup.py`. They may only terminate or
close resources clearly started by their own run and should still request
current-thread archive when thread management is available.

## Installed Automations

### `vibetype-swift-backlog-archiver`

- Installed status: `PAUSED`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.4-mini` / `low`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md`
- Archive script:
  `python3 scripts/backlog_archive_done.py --apply --json`
- Expected output: one bounded completed-backlog archive pass, selector
  readback, `git diff --check`, scoped checkpoint commit when files move,
  run-owned cleanup report without the broad MCP cleanup script, and
  current-thread archive status when thread management is available
- Safety contract: move only clean verified `done` task files from top-level
  `backlog/` to `backlog/done/`; do not claim tasks, implement product code,
  resolve blockers, groom tasks, or run destructive database/storage operations
- Current decision: paused until the cleanup mechanism is verified and the
  operator explicitly resumes this automation

### `vibetype-swift-backlog-groomer`

- Installed status: `PAUSED`
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
- Tooling contract: read `docs/agent-tooling.md` before creating platform or
  shared SwiftUI tasks that name XcodeBuildMCP, `xcodebuild`, Computer Use, or
  fallback evidence; perform run-owned cleanup, do not call the broad MCP
  cleanup script, and request current-thread archive before the final report
  when thread management is available
- Safety/browser evidence contract: no browser requirement; do not implement
  Swift product code; dirty Git state is not a blocker and must be preserved
  with path-limited commits; no DB or destructive storage operations
- Current decision: paused until the cleanup mechanism is verified and the
  operator explicitly resumes this automation

### `vibetype-swift-blocker-resolver`

- Installed status: `PAUSED`
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
  operator-only unblock action; run-owned cleanup report without the broad MCP
  cleanup script and current-thread archive requested before the final report
  when thread management is available
- Tooling contract: read `docs/agent-tooling.md` when a blocker involves
  Xcode, simulator, MCP, runtime QA, or tool-selection decisions
- Safety/runtime evidence contract: dirty Git state is not a blocker and must
  be preserved with path-limited commits; avoid duplicate follow-ups; use
  bounded verification; no DB or destructive storage operations
- Current decision: paused until the cleanup mechanism is verified and the
  operator explicitly resumes this automation

### `vibetype-swift-implementer`

- Installed status: `PAUSED`
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
  mandatory final `python3 scripts/automation_resource_cleanup.py` current-user
  MCP cleanup report, including current-thread archive status when thread
  management is available
- Tooling contract: read `docs/agent-tooling.md` when Xcode, simulator, MCP,
  runtime QA, or tool-selection decisions are involved
- Safety/runtime evidence contract: explicit runtime QA decision for each
  product delta; Computer Use required for bounded app-run QA when visible
  macOS surfaces or user interactions change; no live OpenAI API in normal
  automation; no DB or destructive storage operations
- Current decision: paused until the cleanup mechanism is verified and the
  operator explicitly resumes this automation

### `vibetype-swift-tooling-unblocker`

- Installed status: `PAUSED`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md`
- Recovery script:
  `python3 scripts/local_tooling_recover.py --apply --json`
- Expected output: one bounded local tooling recovery pass, bounded macOS
  unit-test health check, selector readback, run-owned cleanup report without
  the broad MCP cleanup script, and current-thread archive status when thread
  management is available
- Safety/runtime evidence contract: fix local Xcode/build/test/simulator,
  cache, DerivedData, missing local utility, and missing local library blockers
  automatically; do not perform destructive database/storage operations,
  destructive Git rollback, external account login, payment/account changes, or
  manual system privacy approval
- Current decision: paused until the cleanup mechanism is verified and the
  operator explicitly resumes this automation

### `vibetype-swift-archive-completed-automation-threads`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.4-mini` / `low`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt shape: short pointer prompt
- Versioned runtime contract:
  `docs/automation-prompts/runbooks/archive-completed-automation-threads.md`
- Expected output: one current-repository-only archive-housekeeping pass that
  readback-verifies completed, stale interrupted, and stale hanging
  in-progress automation-run threads, treats self-archive hanging
  in-progress runs as immediately eligible, always archives the first visible
  eligible page even when it has only one or two eligible threads, drains newly
  exposed pages inside the same automation invocation, and uses the at-most-two
  eligible thread allowance only to avoid starting a later page-drain pass;
  runs final
  `python3 scripts/automation_resource_cleanup.py` current-user MCP cleanup,
  and archives the current housekeeping thread
- Safety/thread contract: use thread-management tools as source of truth;
  never use Codex SQLite files such as `state_5.sqlite` or filesystem helpers
  to decide what the live sidebar contains;
  inspect only automation threads for this exact cwd; do not inspect, count, or
  archive other-repository, active, pending, manual, or ambiguous threads;
  request current housekeeping thread archive before the final report when the
  thread-management tool is available
- Current decision: active as the only scheduled non-implementer cleanup
  automation, running every 15 minutes

## Missing Or Paused Roles

Five installed work automations for this repository are paused during this
inventory pass. The archive-housekeeping cleanup automation is active. No
installed automation role is missing.

## Verification

Commands/evidence used:

```sh
env CODEX_HOME=/Users/eugenepotapenko/.codex sh -c 'rg -n "^id =|^name =|^prompt =|^status =|^rrule =|^model =|^reasoning_effort =|^execution_environment =|^cwds =" "$CODEX_HOME"/automations/*/automation.toml'
git diff --check
git diff --cached --check
```
