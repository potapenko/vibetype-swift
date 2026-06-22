# Blocked Task Resolution Automation

## Goal

Prevent blocked backlog tasks from becoming abandoned work.

The resolver turns blocked tasks into completed tasks, executable follow-up
tasks, automation-recoverable local tooling repairs, or precise operator-only
unblock requests.

## Behavior

Each resolver run should:

1. Respect the repository workflow contract and canonical checkout.
2. Avoid racing an active implementer claim.
3. Select the next blocked task through the blocked-task selector.
4. Read only the selected blocked task and the files needed to understand its
   blocker.
5. Run local tooling recovery before treating Xcode, build-service,
   compiler-probe, runner, cache, simulator, DerivedData, missing local
   utility, or missing local library state as a blocker.
6. Prefer a direct unblock when the original acceptance criteria are already
   satisfied and verification can be rerun safely.
7. Otherwise create or refine one follow-up backlog task that can remove the
   blocker.
8. Record a durable resolution path on the blocked task.
9. Keep a run-local handled/skipped set so one unresolved blocked task cannot
   starve the rest of the blocked queue.
10. Rerun the blocked selector after each committed resolution and continue the
    sweep until every blocked task in the current selector output is either
    resolved, given/refreshed a durable resolution path, or recorded as not
    safely resolvable in the current run.
11. Commit only the resolver-owned backlog, spec, workflow, or narrowly scoped
    code changes.

If the selected blocker is stale verification debt and the same fresh recovery
plus bounded verification command satisfies explicitly linked closeout tasks or
other same-cause verification blockers, the resolver should close that narrow
verification batch together. The batch must be capped to tasks whose resolution
paths already say that passing command is enough to mark them done. This does
not allow bulk-editing unrelated blocked tasks, runtime-QA blockers, or tasks
that still need product implementation.

## Selection

Blocked selection is deterministic and repeated during a sweep:

- highest priority first;
- ties prefer the task that directly unblocks the most other tasks;
- remaining ties use numeric task id.

The selector must not make normal executor tasks look ready. Normal
implementation continues to use `scripts/backlog_next.py`; blocked resolution
uses `scripts/backlog_blocked_next.py`. The selector's ordered `blocked` array
is the sweep queue; task bodies are read one at a time when their turn arrives.
After each blocker is completed, updated with a durable resolution path, or
proven not safely resolvable in the current run, the resolver reruns the
blocked selector, preserves this run's handled/skipped ids, and continues with
the next ordered blocked task.

## Resolution Path

Every blocked task must have a resolution path before a run reports it as
handled.

For automation-recoverable local tooling blockers, the path records:

- the recovery command:
  `python3 scripts/local_tooling_recover.py --apply --json`;
- any local install or configuration command used to make the required tool
  available;
- the bounded verification command to retry immediately afterward;
- the fresh recovery and verification result;
- why the blocker remains if recovery fails.

For repository-solvable blockers, the path cites exactly one follow-up backlog
task with:

- the original task id it unblocks;
- small scope;
- `allowed_paths`;
- acceptance criteria;
- verification.

For operator-only blockers, the path records the exact operator action or
status check required, why local tooling recovery does not apply, and why a
repository task would not help yet.

## Non-Goals

- Do not replace normal backlog execution.
- Do not bulk-mark unresolved blocked tasks done.
- Do not create duplicate follow-up tasks.
- Do not let one unresolved blocked task prevent inspection of the remaining
  blocked queue in the same bounded run.
- Do not hide external blockers by marking work done without verification.
- Do not perform destructive cleanup, database operations, remote storage
  mutations, or broad unrelated process cleanup.
