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

| Automation id | Name | Status | Schedule | Model | Environment | Prompt snapshot | Runtime runbook |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `vibetype-swift-archive-completed-automation-threads` | VibeType Swift Archive Completed Automation Threads | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.4-mini` / `low` | `local` | `docs/automation-prompts/installed/vibetype-swift-archive-completed-automation-threads.md` | `docs/automation-prompts/runbooks/archive-completed-automation-threads.md` |
| `vibetype-swift-backlog-archiver` | VibeType Swift Backlog Archiver | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.4-mini` / `low` | `local` | `docs/automation-prompts/installed/vibetype-swift-backlog-archiver.md` | `docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md` |
| `vibetype-swift-backlog-groomer` | VibeType Swift Backlog Groomer | active | `FREQ=HOURLY;INTERVAL=2` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/installed/vibetype-swift-backlog-groomer.md` | `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md` |
| `vibetype-swift-blocker-resolver` | VibeType Swift Blocker Resolver | active | `FREQ=HOURLY;INTERVAL=1` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/installed/vibetype-swift-blocker-resolver.md` | `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md` |
| `vibetype-swift-implementer` | VibeType Swift Implementer | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/installed/vibetype-swift-implementer.md` | `docs/automation-prompts/runbooks/vibetype-swift-implementer.md` |
| `vibetype-swift-tooling-unblocker` | VibeType Swift Tooling Unblocker | active | `FREQ=MINUTELY;INTERVAL=15` | `gpt-5.5` / `xhigh` | `local` | `docs/automation-prompts/installed/vibetype-swift-tooling-unblocker.md` | `docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md` |

Installed automation count for this repository: 6.
Active count for this repository: 6.
Paused count for this repository: 0.

Current-user MCP cleanup gate: only two installed automations may call
`python3 scripts/automation_resource_cleanup.py`:
`vibetype-swift-implementer`, once at the end of an implementation run, and
`vibetype-swift-archive-completed-automation-threads`, once at the end of each
housekeeping run. The script takes no parameters, ignores processes owned by
other OS users, and runs current-user killall cleanup for the allowlisted
Codex helper/MCP process names.

All other installed automations must not call
`python3 scripts/automation_resource_cleanup.py`. They may only terminate or
close resources clearly started by their own run and should still request
current-thread archive when thread management is available.

## Installed Automations

### `vibetype-swift-archive-completed-automation-threads`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.4-mini` / `low`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-archive-completed-automation-threads.md`
- Runtime contract: `docs/automation-prompts/runbooks/archive-completed-automation-threads.md`
- Purpose: Archives completed or safely stale Codex automation threads for this exact repository cwd, verifies the local registry has no remaining eligible threads, runs the allowed final resource cleanup gate, and requests self-archive.
- Prompt length: `6437` characters

### `vibetype-swift-backlog-archiver`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.4-mini` / `low`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-backlog-archiver.md`
- Runtime contract: `docs/automation-prompts/runbooks/vibetype-swift-backlog-archiver.md`
- Purpose: Runs the completed-backlog archive workflow, moving verified done task files from active backlog into backlog/done when the archive script reports safe moves.
- Prompt length: `910` characters

### `vibetype-swift-backlog-groomer`

- Installed status: `ACTIVE`
- Schedule: `FREQ=HOURLY;INTERVAL=2`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-backlog-groomer.md`
- Runtime contract: `docs/automation-prompts/runbooks/vibetype-swift-backlog-groomer.md`
- Purpose: Maintains small executable backlog/spec/workflow tasks for the macOS MVP without implementing Swift product code.
- Prompt length: `831` characters

### `vibetype-swift-blocker-resolver`

- Installed status: `ACTIVE`
- Schedule: `FREQ=HOURLY;INTERVAL=1`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-blocker-resolver.md`
- Runtime contract: `docs/automation-prompts/runbooks/vibetype-swift-blocker-resolver.md`
- Purpose: Sweeps blocked backlog tasks and either resolves them, records precise operator-only unblock actions, or creates/refines one concrete follow-up task.
- Prompt length: `833` characters

### `vibetype-swift-implementer`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-implementer.md`
- Runtime contract: `docs/automation-prompts/runbooks/vibetype-swift-implementer.md`
- Purpose: Runs one selector-approved product implementation iteration with claim/completion checkpoints, verification, cleanup, and thread self-archive reporting.
- Prompt length: `1250` characters

### `vibetype-swift-tooling-unblocker`

- Installed status: `ACTIVE`
- Schedule: `FREQ=MINUTELY;INTERVAL=15`
- Model / reasoning effort: `gpt-5.5` / `xhigh`
- Execution environment: `local`
- Cwd: `/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`
- Prompt snapshot: `docs/automation-prompts/installed/vibetype-swift-tooling-unblocker.md`
- Runtime contract: `docs/automation-prompts/runbooks/vibetype-swift-tooling-unblocker.md`
- Purpose: Repairs local Xcode/build/test/tooling blockers and reruns a bounded health check so normal backlog automation can proceed.
- Prompt length: `1100` characters

## Missing Or Paused Roles

All six installed automations for this repository are active. No installed
automation role is missing or paused in the inspected local registry.

## Verification

Commands/evidence used:

```sh
python3 - <<'PY'
from pathlib import Path
import tomli
target = '/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift'
base = Path('/Users/eugenepotapenko/.codex/automations')
for path in sorted(base.glob('*/automation.toml')):
    data = tomli.loads(path.read_text())
    if target in data.get('cwds', []):
        print(data['id'], data['rrule'], data['model'], data['reasoning_effort'])
PY
git diff --check
git diff --cached --check
```
