# Blocked Task Resolution Automation

## Goal

Prevent blocked backlog tasks from becoming abandoned work.

The resolver turns a blocked task into either a completed task, an executable
follow-up task, or a precise operator-only unblock request.

## Behavior

Each resolver run should:

1. Respect the repository workflow contract and canonical checkout.
2. Avoid racing an active implementer claim.
3. Select one blocked task through the blocked-task selector.
4. Read only the selected blocked task and the files needed to understand its
   blocker.
5. Prefer a direct unblock when the original acceptance criteria are already
   satisfied and verification can be rerun safely.
6. Otherwise create or refine one follow-up backlog task that can remove the
   blocker.
7. Record a durable resolution path on the blocked task.
8. Commit only the resolver-owned backlog, spec, workflow, or narrowly scoped
   code changes.

## Selection

Blocked selection is deterministic:

- highest priority first;
- ties prefer the task that directly unblocks the most other tasks;
- remaining ties use numeric task id.

The selector must not make normal executor tasks look ready. Normal
implementation continues to use `scripts/backlog_next.py`; blocked resolution
uses `scripts/backlog_blocked_next.py`.

## Resolution Path

Every blocked task must have a resolution path before a run reports it as
handled.

For repository-solvable blockers, the path cites exactly one follow-up backlog
task with:

- the original task id it unblocks;
- small scope;
- `allowed_paths`;
- acceptance criteria;
- verification.

For operator-only blockers, the path records the exact operator action or
status check required and why a repository task would not help yet.

## Non-Goals

- Do not replace normal backlog execution.
- Do not bulk-edit every blocked task in one run.
- Do not create duplicate follow-up tasks.
- Do not hide external blockers by marking work done without verification.
- Do not perform destructive cleanup, database operations, or remote storage
  mutations.
