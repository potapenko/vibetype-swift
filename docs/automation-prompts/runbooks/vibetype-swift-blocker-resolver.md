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

Run one bounded blocked-task resolution sweep.

The current product phase is the native macOS menu bar MVP. The resolver must
prioritize macOS blockers and leave `ios` / `ios-keyboard` blockers deferred to
future v2 work unless a direct user request explicitly includes deferred lanes.

This automation is not the normal implementer and not the backlog groomer. Its
job is to keep blocked tasks actionable by directly resolving every blocked
task it can safely resolve in the current bounded run, or by creating/refining
the follow-up tasks whose completion would unblock the rest. A resolver run
should not stop merely because it handled one blocked task while more blocked
tasks are still safely resolvable from the current checkout. When a fresh
recovery/test pass proves an explicitly linked closeout task or other
same-cause verification blocker, close that verification batch in the same
commit instead of leaving stale blocked noise behind.

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
  future-version iOS, or simulator related
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

Run this selector from the repo root before each blocked-task decision:

```sh
python3 scripts/backlog_blocked_next.py --json
```

Treat selector JSON as the only source of truth for blocked-task ordering. Do
not reimplement sorting or select by filename manually. For sweep continuation,
use the ordered `blocked` array returned by the selector and keep a run-local
set of blocked task ids already handled, skipped, or proven not safely
resolvable in this run. Read each blocked task body only when that task reaches
its turn in the sweep.
Normal resolver runs must leave the selector's default deferred lanes in place.
Do not pass `--include-deferred-lanes` unless the user explicitly opens v2 iOS
blocker resolution.

If selector status is `select`, work on the first ordered blocked task that is
not already in the run-local handled/skipped set. Initially this is
`selected.path`; after an unresolved blocker is recorded in the run-local set,
continue with the next ordered entry from `blocked` instead of reprocessing the
same task forever. Rerun the blocked selector after every commit, status
change, follow-up creation/refinement, or safe batch completion, then rebuild
the run-local queue from the fresh selector output while preserving the
handled/skipped ids from this run.

Continue until the selector reports `no_blocked`, `queue_error`, an active race
condition from the normal selector, or every blocked task returned by the
current selector has either been resolved, given/refreshed a durable resolution
path, or recorded as not safely resolvable in the current run. If status is
`no_blocked`, stop and report that no blocked task remains. If status is
`queue_error`, stop without claiming and report the diagnostics.

The blocked selector chooses the highest-priority blocked task. Ties prefer
the task that directly unblocks the most other tasks, then numeric task id.

## Resolution Work

For each selected blocked task, read only that task body and the smallest
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
verification evidence, stage only resolver-owned changes, and commit. Then
rerun the blocked selector and continue the sweep.

For stale verification blockers, do not stop after updating only the originally
selected task when the repository already contains paired closeout tasks for the
same blocker. Search the active backlog for the selected task id, `closeout`,
and the same bounded verification command. If the same recovery/test result
satisfies those paired closeout tasks, mark the selected original task and the
paired closeout task `done` together. If several blocked tasks share the same
local Xcode/build-service timeout and the same passing focused command, close
that narrow batch together, capped to tasks whose resolution paths already say
they can be marked done after that command passes. This is not permission to
bulk-edit unrelated blocked tasks, runtime-QA blockers, or product-scope
blockers.

If direct resolution is not safe or not possible, create or refine exactly one
follow-up backlog task that can remove that blocker. Before creating a new
task, search `backlog/` for the blocked task id, existing `unblocks` wording,
and the blocker phrase to avoid duplicates. A follow-up task must include:

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

Do not bulk-mark unresolved blocked tasks `done`. Do not mark a task `done`
merely because a follow-up exists. A run-local skip is not a durable status; it
only prevents one unresolved blocker from starving the rest of the current
sweep. After a follow-up later completes, a future resolver pass should
reprocess the original blocked task and either mark it `done` with fresh
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
active MCP tool surface and use Build macOS Apps or macOS-capable
XcodeBuildMCP when it matches the selected macOS verification need; otherwise
use the repository's documented `xcodebuild` fallback and record the reason.
Build iOS Apps / simulator checks are deferred to explicit v2 runs.

## Expected Output

Stage only files changed for this resolver pass and create a scoped completion
checkpoint commit when files changed.

Final report must include every blocked task inspected in the sweep, action
taken for each (`directly_resolved`, `follow_up_created`,
`follow_up_refined`, `tooling_recovered`, `operator_only`, or
`still_blocked_with_reason`), follow-up id/path or operator action when
applicable, local tooling recovery summary, changed files, verification
results, `Tooling` with the Build macOS Apps / XcodeBuildMCP / `xcodebuild` /
Computer Use path used when relevant, cleanup performed with terminated
resources and any
residual resources with reasons, `Thread archive` with `requested` or
`unavailable` according to the MCP/thread lifecycle action, completion commit
hashes if files changed, final blocked selector result, actual cwd, execution
environment, unrelated dirty files preserved, and confirmation that the
canonical checkout now contains all status or resolution-path updates.
