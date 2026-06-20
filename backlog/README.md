# Backlog

This directory is the executable development queue for VibeType Swift.

Use `BACKLOG_DEVELOPMENT.md` before selecting work. Executor agents must use
the selector and must not manually choose a task by reading task bodies.

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
- `blocked` - exceptional blocker; skipped by normal executor agents.
- `done` - terminal and verified for the declared scope.

Do not add other status values.
