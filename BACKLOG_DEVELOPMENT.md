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
  agent or human changes the task;
- `done` - terminal and verified for the declared scope.

Do not introduce other status values. A task must not be marked `blocked`
solely because its dependencies are not `done`; leave it `backlog` and let the
selector skip it as dependency-pending.

## Selection Rule

Agents must not read the full backlog body before selecting work. They also
must not reimplement queue selection in prompt logic.

Use this flow:

1. Run `python3 scripts/backlog_next.py --json` from the canonical checkout.
2. If the selector returns `status: "select"`, claim exactly the returned
   `selected.path`.
3. If the selector returns `status: "no_ready"`, stop and report that no
   dependency-ready task is available. Do not mark arbitrary tasks `blocked`.
4. If the selector returns `status: "queue_error"`, stop and report the queue
   diagnostics. Do not claim a task.
5. Read the selected task body only after claim.

The selector reads only front matter and title lines. It treats `done`,
`in-progress`, and `blocked` as skipped states, treats `backlog`, `ready`, and
missing status as candidates, checks that all declared dependencies are `done`,
and picks the dependency-ready task with the highest priority. Ties prefer the
task that directly unblocks the most other tasks, then the numeric task id.

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

If the claim cannot be safely committed, stop. Do not implement, inspect
private task details, or run validation for an unclaimed task.

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

## Completion Rule

At the end of the iteration:

1. run the task's verification;
2. mark the task `Status: done` and `status: done` only when the declared scope
   is complete;
3. if the task cannot be completed because of a real blocker discovered after
   claim, set `Status: blocked` and `status: blocked`, then record blocker
   evidence in the task or declared report;
4. add follow-up tasks only when they are real next work;
5. stage only files changed for the iteration;
6. run `git diff --cached --check`;
7. create a scoped completion checkpoint commit;
8. report claim commit, completion commit, verification, changed files, next
   eligible task, and remaining blockers.

Completion is not a chat summary alone. The terminal task state must be
committed.

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
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
git diff --check
```

For Swift test changes or behavior with test coverage:

```sh
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
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

## Relationship To Other Files

- `AGENTS.md` defines workflow, safety, and agent rules.
- `BACKLOG_DEVELOPMENT.md` defines queue execution, claim, and checkpoint
  behavior.
- `SWIFT.md` defines Swift, SwiftUI, AppKit interop, and engineering rules.
- `docs/specs/` defines product behavior.
- `references/` stores imported reference material and audit notes.
- Implementation code follows the specs.
- Tests, manual QA notes, and verification artifacts define evidence.
