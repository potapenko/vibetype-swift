# Backlog

This directory is the executable development queue for VibeType Swift.

Use `BACKLOG_DEVELOPMENT.md` before selecting work. Executor agents must use
the selector and must not manually choose a task by reading task bodies.

## Select The Next Task

```sh
python3 scripts/backlog_next.py --json
```

If the selector returns `status: "select"`, claim exactly the returned
`selected.path`. If it returns `no_ready` or `queue_error`, stop and report the
result.

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

## Status Values

- `backlog` - unfinished and unclaimed.
- `ready` - optional explicit ready marker; still requires selector checks.
- `in-progress` - claimed and skipped by other executor agents.
- `blocked` - exceptional blocker; skipped by normal executor agents.
- `done` - terminal and verified for the declared scope.

Do not add other status values.
