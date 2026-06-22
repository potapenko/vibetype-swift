---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: vibetype-swift-backlog-archiver
status: active
---

# VibeType Swift Backlog Archiver Runbook

This runbook is the versioned runtime contract for the current user's
`vibetype-swift-backlog-archiver` installed Codex automation.

Configured automation cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

## Resource Cleanup Gate

At the start of the run, before archive work or MCP-heavy tool use, run from
the repository root:

```sh
python3 scripts/automation_resource_cleanup.py --apply --min-age-seconds 60 --json
```

At the end of the run, after verification/checkpoint handling and immediately
before the final response, run:

```sh
python3 scripts/automation_resource_cleanup.py --apply --min-age-seconds 0 --json
```

Include both cleanup JSON summaries in the final report. If the script reports
`permission_required`, `operator_commands`, or remaining processes, report the
owner, pid, command, and reason instead of claiming cleanup succeeded.

## Runtime Contract

Run one bounded completed-backlog archival pass for VibeType Swift.

This automation keeps verified `done` tasks out of the active top-level
`backlog/` queue. It does not implement product code, resolve blocked tasks,
groom new tasks, or claim normal backlog work.

Use the configured canonical checkout as the source of truth. Historical run
memory is context only.

Required reading before action:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-onboarding.md`
- `docs/agent-tooling.md`
- `docs/specs/features/backlog-grooming-automation.md`
- this runbook

## Safety

Start with:

```sh
git status --short
python3 scripts/backlog_archive_done.py --dry-run --json
```

Dirty Git state is not a blocker. Preserve unrelated changes and use
path-limited staging and commits. The archive script skips done task files that
have uncommitted source changes, status mismatches, destination collisions, or
unavailable Git status.

Do not manually move task files. Do not archive `backlog`, `ready`,
`in-progress`, or `blocked` tasks. Do not edit sibling repositories. Do not run
destructive database or object-storage operations.

Before the final response, follow the hard final resource cleanup and
MCP/thread lifecycle guidance in `docs/agent-tooling.md`: terminate or close
every resource the run started, clean only non-durable run-owned temporary
artifacts, report any residual resource that cannot be terminated, and request
archive of the current automation thread when the thread-management tool is
available.

## Apply Rule

If the dry-run reports `planned_count` greater than zero, run:

```sh
python3 scripts/backlog_archive_done.py --apply --json
python3 scripts/backlog_next.py --json
python3 scripts/backlog_blocked_next.py --json
python3 scripts/backlog_archive_done.py --dry-run --json
git diff --check
```

If the apply run moved files, stage only the moved backlog paths and create a
scoped checkpoint commit:

```sh
git add -- <moved-from-paths> <moved-to-paths>
git commit --only <moved-from-paths> <moved-to-paths> -m "Archive completed backlog tasks"
```

If unrelated changes are present, inspect enough status/diff to confirm they
are not staged into the archive commit. Do not revert or stash them.

If dry-run reports no planned moves, do not create an empty commit. Still run
normal and blocked selector readback plus `git diff --check` and report the
active task count, archived done count, selector status, and skipped archive
count.

## Verification

For normal archival runs, verification is:

```sh
python3 scripts/backlog_next.py --json
python3 scripts/backlog_blocked_next.py --json
python3 scripts/backlog_archive_done.py --dry-run --json
git diff --check
```

When archive tooling code changes, run the focused Python tests:

```sh
python3 scripts/backlog_archive_done_test.py
python3 scripts/backlog_next_test.py
python3 scripts/backlog_blocked_next_test.py
```

## Expected Output

Final report must include actual cwd, dry-run planned/skipped counts, apply
moved/skipped counts when applicable, active task count, archived done count,
normal selector status, blocked selector status, verification results, commit
hash if files changed, unrelated dirty files preserved, cleanup performed with
terminated resources and any residual resources with reasons, and `Thread
archive` with `requested` or `unavailable` according to the thread-management
tool surface.
