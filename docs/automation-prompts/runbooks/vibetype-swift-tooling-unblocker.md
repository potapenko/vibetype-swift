---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: vibetype-swift-tooling-unblocker
status: active
---

# VibeType Swift Tooling Unblocker Runbook

This runbook is the versioned runtime contract for the current user's
`vibetype-swift-tooling-unblocker` installed Codex automation.

Configured automation cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

## Runtime Contract

Run one bounded local tooling unblock pass for VibeType Swift.

This automation exists to prevent implementer, resolver, and groomer agents
from waiting on stale local tooling. It should repair local Xcode/build/test
tooling problems directly and leave the repository ready for the normal
selector-driven agents.

Use the configured canonical checkout as the source of truth. Historical run
memory is context only.

Required reading before action:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-tooling.md`
- `docs/specs/features/blocked-task-resolution-automation.md`
- this runbook

## Recovery Rule

Agents must fix local tooling automatically. Do not ask the user to clear
Xcode, `xcodebuild`, `xctest`, `SWBBuildService`, compiler-probe, simulator,
DerivedData, generated-cache, missing local utility, missing Apple platform, or
missing local library blockers.

Run from the repository root:

```sh
python3 scripts/local_tooling_recover.py --apply --json
```

Then run a bounded health check:

```sh
/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests
```

If `/opt/homebrew/bin/timeout` is missing, install GNU coreutils with the local
package manager and rerun the command. If Xcode command line tools, simulator
support, or another local utility/library needed for the health check is
missing and can be installed or selected from the shell, do that inside the
bounded run and record the command.

Do not perform destructive database operations, destructive object-storage
operations, destructive Git rollback, external account login, payment/account
changes, manual system privacy approval, or broad unrelated process cleanup.

## Selector Readback

After recovery and health check, run:

```sh
python3 scripts/backlog_next.py --json
python3 scripts/backlog_blocked_next.py --json
git diff --check
```

Do not claim backlog tasks and do not mark tasks done. If the health check
passes and a blocked verification task is now resolvable, report that the
blocker resolver should run next. If local tooling still fails, report the
remaining exact command/result and what automatic repair was attempted.

## Checkpoint

This automation normally changes no repository files. If it updates a runbook,
workflow note, or durable QA report as part of a selected manual fix, stage only
that scoped file set and create a checkpoint commit. Never stage unrelated user
changes or generated local artifacts.

## Expected Output

Final report must include actual cwd, execution environment, recovery command,
recovery JSON summary, any install/configuration commands run, health-check
command/result, selector status after recovery, blocked selector result after
recovery, `git diff --check` result, changed files if any, commit hash if any,
cleanup performed, remaining blocker if any, and `Thread archive` with
`requested` or `unavailable` according to the thread-management tool surface.
