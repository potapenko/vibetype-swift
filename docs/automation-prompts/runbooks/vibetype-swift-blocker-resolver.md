---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: vibetype-swift-blocker-resolver
status: active
---

# VibeType Swift Blocker Resolver Runbook

This runbook is the versioned runtime contract for the current user's
`vibetype-swift-blocker-resolver` installed Codex automation.

Configured automation cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

## Runtime Contract

Run one bounded blocked-task resolution pass.

This automation is not the normal implementer and not the backlog groomer. Its
job is to keep blocked tasks actionable by directly resolving one blocked task
when safe, or by creating/refining exactly one follow-up task whose completion
would unblock it. When the selected task is a stale verification blocker and a
single fresh recovery/test pass proves an explicitly linked closeout task or
other same-cause verification blocker, the resolver may close that small
verification batch in the same commit instead of leaving stale blocked noise
behind.

Use the configured canonical checkout as the source of truth. Historical run
memory is context only; it does not mark tasks complete and must not override
repository workflow files.

Before selection, confirm actual cwd is the configured repository root and
execution environment is `local`. If the run is under an isolated worktree
whose commit will not advance the canonical checkout, stop and report a blocker
before selecting a blocked task.

Required reading before edits:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-onboarding.md`
- `docs/agent-tooling.md` when Xcode, simulator, MCP, runtime QA, or
  tool-selection decisions are involved
- `docs/specs/README.md`
- `docs/specs/brownfield-discovery.md`
- `docs/specs/features/blocked-task-resolution-automation.md`
- `docs/automation-prompts/runbooks/vibetype-swift-implementer.md`
- `docs/specs/features/platform-testing-strategy.md` when the blocker is
  verification, runtime QA, permissions, microphone, paste handoff, macOS UI,
  iOS, or simulator related
- `SWIFT.md` when Swift, SwiftUI, AppKit, Xcode, or tests may change
- any task-relevant specs required by `AGENTS.md` or the selected blocked task

Do not require optional README files that are absent from the checkout.

## Safety Gate

Start with a race-aware checkout, but do not treat dirty Git state as a
blocker:

1. Run `git status --short`.
2. If there are staged or unstaged changes, inspect the relevant diff and
   continue. Preserve all pre-existing changes, including overlapping files, and
   edit against the current contents.
3. Stage and commit only resolver-owned paths. If unrelated changes are already
   staged, use path-limited commit commands such as `git commit --only <owned
   paths>` so the unrelated index does not block progress.
4. Run `python3 scripts/backlog_next.py --json` before blocked selection. This
   normal selector expires stale implementation claims by default.
5. If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
   stage only those reset task files, create a scoped claim-expiry repair
   commit, and rerun `python3 scripts/backlog_next.py --json`.
6. If the normal selector reports a non-expired `in_progress` or
   `blocking_in_progress` task after stale-claim repair, stop without changes
   to avoid racing the implementer in the canonical checkout.
7. If the normal selector reports `queue_error`, stop and report the queue
   diagnostics.

8. Before blocked selection, run local tooling recovery:

```sh
python3 scripts/local_tooling_recover.py --apply --json
```

This step is mandatory. Local Xcode/build/test/simulator hangs, stale
`xcodebuild`, `xctest`, `SWBBuildService`, compiler probes, generated caches,
project-scoped DerivedData, missing local CLI utilities, and stale runner state
are automation problems. The resolver must fix them automatically instead of
waiting for the user.

Do not access MongoDB directly. Do not run destructive database or
object-storage operations. Do not edit sibling repositories unless a selected
task explicitly authorizes it.

Apply run hygiene: close run-owned browser sessions, app launches, simulators,
and dev servers before and after checks when ownership is clear; clean
current-run temporary screenshots, audits, profiles, downloads, bytecode, and
build artifacts before staging; keep only durable reports or explicit evidence.
Follow the hard final resource cleanup and MCP/thread lifecycle guidance in
`docs/agent-tooling.md`: keep MCP inspection task-specific, do not manually
kill broad MCP process names, do not call
`python3 scripts/automation_resource_cleanup.py`, terminate or close every
resource the run started, report any residual resource that cannot be
terminated, and request archive of the current automation thread before the
final response when the thread-management tool is available. For
local build/test tooling, use the repo recovery helper and local
installation/configuration commands when needed; do not downgrade local tooling
repair to a user/operator action.

## Blocked Selector

Run this selector from the repo root:

```sh
python3 scripts/backlog_blocked_next.py --json
```

Treat selector JSON as the only source of truth for blocked-task ordering. Do
not reimplement sorting, select by filename manually, or read non-selected
blocked task bodies.

If selector status is `select`, work on exactly `selected.path`. If status is
`no_blocked`, stop without changing repository files and report that no blocked
task exists. If status is `queue_error`, stop without claiming and report the
diagnostics.

The blocked selector chooses the highest-priority blocked task. Ties prefer
the task that directly unblocks the most other tasks, then numeric task id.

## Resolution Work

After selecting one blocked task, read only that task body and the smallest
task-relevant file set needed to understand the blocker.

Prefer direct resolution when all of these are true:

- the original implementation appears present;
- the original acceptance criteria can be checked without broad new work;
- verification can be rerun with bounded waits;
- any required code or spec repair stays inside the selected task's scope.

For verification-only blockers whose resolution path says the work is already
implemented, first rerun the narrow verification named in the task and
`git diff --check`. If both pass and the repository verification strategy allows
that narrow evidence for the blocker class, mark the selected task `done`
without creating another follow-up task.

If the selected task mentions Xcode, `xcodebuild`, `xctest`,
`SWBBuildService`, compiler probes, simulator tooling, local command line tools,
caches, DerivedData, or test-runner state, the resolver must run local tooling
recovery and then rerun the narrow bounded verification before deciding the
task remains blocked. A stale local tooling blocker may not be recorded as
operator-only without this recovery/retry evidence.

If direct resolution succeeds, mark the selected task `done`, record fresh
verification evidence, stage only resolver-owned changes, and commit.

For stale verification blockers, do not stop after updating only the originally
selected task when the repository already contains paired closeout tasks for the
same blocker. Search the active backlog for the selected task id, `closeout`,
and the same bounded verification command. If the same recovery/test result
satisfies those paired closeout tasks, mark the selected original task and the
paired closeout task `done` together. If several blocked tasks share the same
local Xcode/build-service timeout and the same passing focused command, the
resolver may close that narrow batch together, capped to tasks whose resolution
paths already say they can be marked done after that command passes. This is
not permission to bulk-edit unrelated blocked tasks, runtime-QA blockers, or
product-scope blockers.

If direct resolution is not safe or not possible, create or refine exactly one
follow-up backlog task that can remove the blocker. Before creating a new task,
search `backlog/` for the blocked task id, existing `unblocks` wording, and the
blocker phrase to avoid duplicates. A follow-up task must include:

- the original blocked task id it unblocks;
- small scope and `allowed_paths`;
- concrete acceptance criteria;
- verification commands or evidence;
- any dependency or operator precondition.

Then add or update a `## Resolution Path` section in the selected blocked task.
Include:

- blocker category;
- follow-up id/path, or the exact operator-only unblock action;
- unblock condition;
- why the current run could not finish it directly.

For operator-only blockers, do not create a weak repository task. This category
is only valid after local recovery and bounded retry have been attempted, or
when the blocker is clearly outside local tooling. Record the shortest exact
operator command, status check, or manual system action that would unblock the
original task, and explain why automatic tooling recovery, local installation,
or repository work cannot advance it. Destructive database/object-storage
operations, destructive Git rollback, external account login, payment/account
changes, and manual system privacy approval remain operator-only; stale local
Xcode/build/simulator state does not.

Do not bulk-edit every blocked task. Do not mark a task `done` merely because a
follow-up exists. After a follow-up later completes, a future resolver pass
should reprocess the original blocked task and either mark it `done` with fresh
evidence or reset it to `backlog` if it genuinely needs implementation rerun.

## Verification

For backlog/spec/runbook-only changes, run:

```sh
python3 scripts/backlog_blocked_next.py --json
python3 scripts/backlog_next.py --json
git diff --check
```

When selector code changes, run its focused tests:

```sh
python3 scripts/backlog_blocked_next_test.py
python3 scripts/backlog_next_test.py
```

For Swift behavior changes, run the selected task's verification and the
repository baseline unless the selected blocker requires narrower evidence:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
git diff --check
```

For Swift test changes or test-covered behavior:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
git diff --check
```

Use bounded waits for external tools. Do not call the live OpenAI API from
normal automation. Do not require real microphone input or real system
permission prompts for normal tests.
When the blocker is platform verification or simulator evidence, check the
active MCP tool surface and use XcodeBuildMCP when it matches the selected
verification need; otherwise use the repository's documented `xcodebuild`
fallback and record the reason.

## Expected Output

Stage only files changed for this resolver pass and create a scoped completion
checkpoint commit when files changed.

Final report must include selected blocked task id/title/path, action taken
(`directly_resolved`, `follow_up_created`, `follow_up_refined`,
`tooling_recovered`, or `operator_only`), follow-up id/path or operator action,
local tooling recovery summary, changed files, verification results, `Tooling`
with the XcodeBuildMCP / `xcodebuild` / Computer Use path used when relevant,
cleanup performed with terminated resources and any residual resources with
reasons, `Thread archive` with `requested` or `unavailable` according to the
MCP/thread lifecycle action, completion commit hash if files changed,
next blocked selector result if checked, actual cwd, execution environment,
unrelated dirty files preserved, and confirmation that the canonical checkout
now contains the status or resolution-path update.
