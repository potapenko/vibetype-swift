# Backlog Development

Status: primary development workflow for this repository.

This file is the root-level development contract for working through backlog
tasks and restartable agent runs. It applies to Swift app implementation,
specs, docs, reference audits, build configuration, verification, and future
development lanes unless a narrower root workflow file explicitly overrides it.

Use this file after `AGENTS.md` and before opening detailed backlog task
bodies.

## Principle

Development is coordinated through committed backlog tasks, not a live chat
thread.

A chat may still discuss architecture, create backlog tasks, review results, or
decide priorities. It is not the durable source of truth for work state. The
source of truth is the repository: backlog files, specs, reference reports,
verification artifacts, and checkpoint commits.

The normal unit of work is:

```text
selector-approved backlog task
  -> claim commit
  -> bounded implementation or docs/spec work
  -> verification
  -> completion or blocker commit
  -> follow-up tasks when needed
```

## When To Use This

Use this workflow for:

- Swift and SwiftUI implementation tasks;
- specs, docs, reference audits, app configuration, and verification work;
- scheduled Codex automations;
- manual Codex iterations that should be restartable without chat memory;
- long migrations that need durable task state and executable follow-up work.

Do not use an ad hoc coordinator process as the default. If a task really needs
coordination, make that an explicit backlog task or user request and keep the
result durable.

## Backlog Shape

One task is one small Markdown file.

The active development backlog lives in:

```text
backlog/
```

`README.md` files in backlog folders are instructions and templates. They are
not executable tasks.

## Task Header

Task headers must support shallow scanning. Agents should be able to decide
whether a task is ready without reading the whole body.

Recommended front matter:

```text
---
id: VT-001
status: backlog
priority: P1
lane: specs
dependencies:
allowed_paths:
  - docs/specs/**
verification:
  - git diff --check
---
```

Recommended visible header fields:

```text
Status: backlog
Priority: P1
Lane: specs
Dependencies: none
Expected outputs: spec update, verification result
Verification: git diff --check
```

Every task must make scope, expected output, dependencies, and verification
clear enough for the selector to decide whether it is executable without
reading the task body.

Status values:

- no `status` or `backlog` - unfinished and unclaimed; not directly executable
  until the selector reports it as dependency-ready;
- `ready` - optional explicit ready marker; still requires selector dependency
  checks before claim;
- `in-progress` - claimed by an agent and skipped by other agents;
- `blocked` - an exceptional blocker that is not merely unfinished
  dependencies; skipped by normal executor agents until a blocker-resolution
  agent or human changes the task; blocked tasks must include a durable
  resolution path, not just a stop note;
- `done` - terminal and verified for the declared scope.

Do not introduce other status values. A task must not be marked `blocked`
solely because its dependencies are not `done`; leave it `backlog` and let the
selector skip it as dependency-pending.

`in-progress` is a short-lived claim, not a durable wait state. It must end
with a committed `done`, `blocked`, or claim-expiry reset. Scheduled automation
must expire `in-progress` task files whose file modification time is more than
one hour old, reset only their claim status to `backlog`, commit that repair,
and rerun selection before claiming work.

## Selection Rule

Agents must not read the full backlog body before selecting work. They also
must not reimplement queue selection in prompt logic.

Use this flow:

1. Run `python3 scripts/backlog_next.py --json` from the canonical checkout.
   This standard selector run expires stale `in-progress` claims by default.
2. If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
   stage only those reset task files, create a scoped claim-expiry repair
   commit such as `Expire stale backlog claims`, and rerun the same selector
   command before claiming work.
3. If the selector returns `status: "select"`, claim exactly the returned
   `selected.path`.
4. If the selector returns `status: "no_ready"`, stop and report that no
   dependency-ready task is available. Include any `in_progress` and
   `blocking_in_progress` diagnostics from the selector. Do not mark arbitrary
   tasks `blocked`.
5. If the selector returns `status: "queue_error"`, stop and report the queue
   diagnostics. Do not claim a task.
6. Read the selected task body only after claim.

The selector reads only front matter and title lines. It treats `done`,
`in-progress`, and `blocked` as skipped states, treats `backlog`, `ready`, and
missing status as candidates, checks that all declared dependencies are `done`,
and picks the dependency-ready task with the highest priority. It also reports
active claims, stale claim candidates, reset paths, and unmet dependency
statuses so stale claims are visible instead of ordinary dependency debt. Ties
prefer the task that directly unblocks the most other tasks, then the numeric
task id.

## Local Tooling Recovery

Local Xcode, simulator, build-service, compiler-probe, runner, cache,
DerivedData, missing local command-line utility, and missing local library
failures are automation-recoverable unless the task evidence proves that
recovery would require a real user decision, login, permission grant, or
destructive operation.

Agents must not classify local tooling as operator-only just because the fix is
forceful. Before stopping on a local tooling blocker, run the bounded recovery
helper from the repository root:

```sh
python3 scripts/local_tooling_recover.py --apply --json
```

The helper may terminate allowlisted stale local Xcode/build/test tooling
processes and remove generated VibeType artifacts such as project-scoped
DerivedData and selector bytecode. Agents may also install or configure missing
local tools, command-line utilities, Apple platforms, or libraries when needed
for the selected task. They must not touch source files outside the selected
scope, Git history/state destructively, databases, remote storage, broad MCP
server processes, or unrelated projects.

After recovery, rerun the narrow command that originally proved the blocker,
using a timeout. Only record a remaining blocker after this recovery path has
run and the fresh bounded command still fails. The blocker evidence must
include the recovery JSON summary and the rerun command/result.

Operator-only is reserved for actions an agent cannot perform safely even with
local shell access, such as approving a system privacy prompt, logging into an
external account, payment/account changes, destructive Git rollback, or
destructive database/object-storage operations.

## Oversized Task Decomposition

A normal implementation agent should not execute a task that is obviously
larger than one bounded iteration.

A task is probably oversized when it asks for several app surfaces, permission
flows, external-service calls, state machines, persistence changes, specs, and
verification layers at the same time.

When a backlog-grooming task or coordinator pass finds an oversized task that
is not `done` or `in-progress`:

1. do not claim it for implementation;
2. keep the oversized task `backlog` as a dependency-gated umbrella;
3. add small child task files that each have one observable output and one
   focused verification path;
4. add the child task ids to the parent dependencies, or add one small
   `decompose-*` task if the child set is unclear;
5. never rewrite or split an `in-progress` task unless the user explicitly asks
   for that handoff.

The goal is to make the next executable unit small enough for an agent to
complete, verify, and checkpoint in one short run.

## Claim Rule

Before substantive work, claim the selected task:

1. confirm the actual cwd is the canonical checkout or a checkout with a tested
   merge-back path;
2. set only the selected task to `Status: in-progress` and `status:
   in-progress`;
3. run `git diff --check`;
4. stage only the selected task file;
5. create a small claim checkpoint commit.

Dirty Git state is not a blocker. If unrelated files are modified or staged,
leave them intact and continue. Use path-limited staging and commits, such as
`git add <owned paths>` and `git commit --only <owned paths>`, so unrelated
changes are not included. If a selected file already has edits, read the diff
and build on the current contents without reverting them. Do not stop merely
because the worktree or index is dirty.

If the claim still cannot be committed after path-limited commit handling,
record the exact Git command/error and keep working around the Git state. Dirty
Git is not a valid reason to abandon selection or report no work. Only a real
Git failure that prevents writing the selected task file at all may block the
claim.

Do not implement, inspect private task details, or run validation for an
unclaimed task.

## Execution Rule

After claiming:

- read only the selected task body and required root workflow files;
- follow the task's dependencies, scope, allowed paths, denied paths, and
  expected outputs;
- read `SWIFT.md` before Swift or SwiftUI source changes;
- read the relevant feature spec before changing product behavior;
- update specs when behavior changes;
- use the smallest task-specific reading slice;
- do not widen into adjacent tasks;
- write durable reports or evidence when the task asks for them;
- create follow-up task files for downstream or cross-boundary work;
- keep chat updates short and treat repository files as the durable state.
- never treat unrelated dirty Git state as a task blocker; preserve it, work
  around it, and commit only the current task's owned paths.

## Forbidden Dirty-Git Stop Rule

Do not add or follow any rule that stops an agent because the checkout is
"GitHub dirty", "dirty Git", a dirty worktree, a dirty checkout, has staged
changes, has unstaged changes, has uncommitted changes, or has overlapping
local edits. Those conditions must be handled by reading the diff, preserving
the current contents, and committing only owned paths.

If an existing prompt, runbook, automation memory, or generated instruction says
to stop because of dirty Git state, the repository rule here overrides it for
this checkout. Patch that instruction when it is in the repository. If it is
outside the repository, ignore the dirty-stop portion and continue with
path-limited Git operations.

## Completion Rule

At the end of the iteration:

1. run the task's verification;
2. mark the task `Status: done` and `status: done` only when the declared scope
   is complete;
3. if the task cannot be completed because of a real blocker discovered after
   claim, set `Status: blocked` and `status: blocked`, then record blocker
   evidence in the task or declared report;
4. when marking a task blocked, add a `## Resolution Path` section or an
   equivalent durable report entry that names exactly what would unblock the
   task;
5. for any blocker that can be solved inside the repository, create or update
   exactly one concrete follow-up task that can remove the blocker, and record
   that task id/path in the blocked task; if a suitable follow-up already
   exists, cite it instead of duplicating it;
6. for operator-only or external blockers, first prove that the local tooling
   recovery path above does not apply; then record the shortest exact operator
   action or status check that would unblock the task and explain why no
   repository task is useful yet;
7. add other follow-up tasks only when they are real next work;
8. stage only files changed for the iteration, using path-limited staging and
   commit commands so pre-existing dirty files are not included;
9. run `git diff --cached --check`;
10. create a scoped completion checkpoint commit;
11. report claim commit, completion commit, verification, changed files, next
   eligible task, and remaining blockers.

Completion is not a chat summary alone. The terminal task state must be
committed.

Blocked is not a terminal abandonment state. It is a queued state for
blocker-resolution work. A blocked task without a resolution path is incomplete
workflow state and should be repaired by the next blocker-resolution pass.

## OpenWhispr Reference Rule

The copied OpenWhispr source under `references/openwhispr-main/` is reference
material only. Use it to understand behavior around hotkeys, recording,
permissions, paste handoff, settings, and edge cases.

Do not port Electron, React, Node.js runtime code, local model downloaders,
meeting features, notes, account, cloud sync, billing, or telemetry behavior
into the Swift app unless a future spec explicitly changes the MVP scope.

When a task needs OpenWhispr evidence, cite the specific reference file and
translate the behavior into a Swift product spec or native service boundary
before implementation.

## Verification Baseline

For Swift behavior changes:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
git diff --check
```

For Swift test changes or behavior with test coverage:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
git diff --check
```

For docs/spec-only changes:

```sh
git diff --check
```

Use a narrower command only when the selected task explicitly allows it and the
final report explains the verification scope. External-service, microphone,
permissions, or app-run checks must use bounded waits and controllable fakes
where practical.

Use `docs/specs/features/platform-testing-strategy.md` to decide when a task
needs extra platform evidence. Computer Use is for bounded macOS runtime smoke
when a selected task changes visible app surfaces. XcodeBuildMCP / Build iOS
Apps is for future iOS simulator build, test, screenshot, and UI-snapshot
checks when an iOS target exists or a selected task changes shared iOS/macOS
SwiftUI surfaces. Use `docs/agent-tooling.md` to discover active MCP tools and
choose the task-appropriate Xcode, simulator, or Computer Use path.

## Relationship To Other Files

- `AGENTS.md` defines workflow, safety, and agent rules.
- `BACKLOG_DEVELOPMENT.md` defines queue execution, claim, and checkpoint
  behavior.
- `SWIFT.md` defines Swift, SwiftUI, AppKit interop, and engineering rules.
- `docs/specs/` defines product behavior.
- `references/` stores imported reference material and audit notes.
- Implementation code follows the specs.
- Tests, manual QA notes, and verification artifacts define evidence.
