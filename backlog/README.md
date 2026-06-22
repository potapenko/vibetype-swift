# Backlog

This directory is the executable development queue for VibeType Swift.

Use `BACKLOG_DEVELOPMENT.md` before selecting work. Executor agents must use
the selector and must not manually choose a task by reading task bodies.

Top-level `backlog/*.md` files are the active queue. Completed tasks may be
archived under `backlog/done/`; those files remain dependency records but are
not executable tasks.

## Select The Next Task

```sh
python3 scripts/backlog_next.py --json
```

If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
stage only those reset task files, create a scoped repair commit such as
`Expire stale backlog claims`, and rerun the same selector command before
claiming work.

If the selector returns `status: "select"` after any stale-claim repair, claim
exactly the returned `selected.path`. If it returns `no_ready` or
`queue_error`, stop and report the result.

The current default product phase is the macOS menu bar MVP. The selector
therefore defers `ios` and `ios-keyboard` lanes by default and reports them in
the JSON `deferred` fields instead of selecting them. Only use
`--include-deferred-lanes` for an explicit v2 iOS run or direct user request.

## Archive Completed Tasks

Maintenance agents should keep completed tasks out of the active queue:

```sh
python3 scripts/backlog_archive_done.py --dry-run --json
python3 scripts/backlog_archive_done.py --apply --json
```

The archive command moves only clean top-level tasks whose front matter and
visible status are both `done`. After an apply run, rerun
`python3 scripts/backlog_next.py --json`, run `git diff --check`, and create a
scoped checkpoint commit for the moved task files.

## Task Template

```text
---
id: VT-000
status: backlog
priority: P2
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---

# Short Task Title

Status: backlog
Priority: P2
Lane: specs
Dependencies: none
Expected outputs: spec update, verification result
Verification: git diff --check

## Goal

One short product or engineering goal.

## Scope

- The specific file or behavior to change.
- The exact output expected from this task.

## Non-goals

- Adjacent work that should not be pulled into this task.

## Acceptance

- Observable checks for completion.

## Notes

- Links to relevant specs, reference files, or prior decisions.
```

## Umbrella Parents

Large product areas should be represented as parent tasks with dependencies on
small child tasks. Parent tasks are planning containers, not normal
implementation slices.

Use this pattern when a product area is too large for one agent checkpoint:

- keep the parent task in `status: backlog`
- add all child task ids to the parent's `dependencies`
- make each child task independently selectable and verifiable
- keep each child near a 10-minute agent slice when possible
- do not claim a parent task while its children are still incomplete

The selector will naturally prefer ready child tasks. Parent tasks become ready
only after their children are complete and can then be used for final review,
cleanup, or closeout.

## Status Values

- `backlog` - unfinished and unclaimed.
- `ready` - optional explicit ready marker; still requires selector checks.
- `in-progress` - claimed and skipped by other executor agents while the claim
  is fresh; scheduled automation expires task files older than one hour and
  resets only the claim status to `backlog`.
- `blocked` - exceptional blocker; skipped by normal executor agents until a
  blocker-resolution pass or human changes it. A blocked task must include a
  durable `## Resolution Path` or equivalent report entry that either cites one
  concrete follow-up task to remove the blocker, names the required
  automation-recoverable local tooling recovery, or records the exact
  operator-only action/status check needed to unblock it.
- `done` - terminal and verified for the declared scope. Done tasks may be
  moved to `backlog/done/` by the archive automation.

Do not add other status values.

## Dirty Git State

Dirty worktrees and staged unrelated changes are not backlog blockers. Agents
must continue work by reading the current diff, preserving unrelated edits, and
committing only their owned paths. Do not revert user or concurrent agent
changes. Do not include unrelated changes in a task commit. Use path-limited
staging and commit commands when the index is dirty.

Do not create or follow backlog instructions that stop on "GitHub dirty",
"dirty Git", dirty worktree, unstaged changes, staged changes, uncommitted
changes, or overlapping edits. If such wording appears in a generated task,
runbook, or automation prompt, treat it as invalid for this repository and
repair it when the file is in scope.

## Automation-Recoverable Blockers

Xcode, `xcodebuild`, `xctest`, `SWBBuildService`, compiler-probe, DerivedData,
simulator-runner, generated-cache, missing local utility, and missing local
library blockers are not human chores by default. Before a task records or
repeats one of those blockers, the agent must run:

```sh
python3 scripts/local_tooling_recover.py --apply --json
```

Then install/configure any missing local tools or libraries needed for the
selected task, and rerun the narrow bounded verification that failed. Only
classify a remaining blocker as operator-only if the recovery helper and local
tool installation/configuration are not applicable or the fresh result proves a
non-tooling external boundary is still required.
