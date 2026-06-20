---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: vibetype-swift-implementer
status: active
---

# VibeType Swift Implementer Runbook

This runbook is the versioned runtime contract for the current user's
`vibetype-swift-implementer` installed Codex automation.

Configured automation cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

## Runtime Contract

Work on the VibeType Swift development backlog as one bounded 10-minute
iteration.

This automation is product-first. Each run must try to move the working app
forward, not merely improve repository paperwork. A selected task is successful
only when the run produces a concrete product delta: app behavior, Swift source,
tests that protect product behavior, build/runtime configuration needed by the
app, or a verified bug fix. Documentation, specs, audits, and backlog edits are
allowed only as supporting work for that product delta.

Do not complete a task by producing only Markdown. If the selected task body
appears to ask for only docs, audit notes, reference translation, workflow
cleanup, or task grooming, reinterpret it through the product-first lens before
doing the easy part:

1. identify the smallest app behavior or testable product capability that the
   task is meant to unblock;
2. implement that smallest safe code/test/configuration change in the same run
   when the behavior is already clear and dependencies are available;
3. update specs or backlog only as needed to support the code change;
4. if the task forbids code changes, has allowed paths that make code
   impossible, or lacks enough product clarity to implement safely, do not mark
   it `done`; mark it `blocked` with the reason `no product delta possible from
   selected scope`, record the exact smallest product change that should be
   made next, and create or update a concrete implementation task for that
   change.

The selected task's wording is not an excuse to choose a paperwork-only
completion path. Prefer code and executable verification first. Reference
research is useful only when it directly changes product behavior, tests, or a
ready implementation task that the current scope cannot safely execute.

Use the configured canonical checkout as the source of truth. Historical run
memory is context only; it does not mark tasks complete and must not override
repository workflow files.

Before selection, confirm actual cwd is the configured repository root and
execution environment is `local`. If the run is under an isolated worktree
whose commit will not advance the canonical checkout, stop and report a blocker
before selecting or implementing a task.

Required reading before edits:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-onboarding.md`
- `SWIFT.md` when Swift, SwiftUI, AppKit, Xcode, or tests may change
- `docs/specs/README.md`
- `docs/specs/brownfield-discovery.md`
- `docs/openwhispr_swiftui_codex_tz.md` when initial MVP behavior is relevant
- `references/README.md` before using copied OpenWhispr source
- `docs/specs/features/platform-testing-strategy.md` when a task changes
  verification strategy, UI runtime behavior, permissions, microphone, paste
  handoff, iOS, shared SwiftUI surfaces, or QA evidence
- any task-relevant specs required by `AGENTS.md` or the selected task

Do not require optional README files that are absent from the checkout.

## Selector

Run this selector from the repo root:

```sh
python3 scripts/backlog_next.py --json
```

Treat selector JSON as the only source of truth. Do not reimplement backlog
sorting, select by filename manually, or read non-selected task bodies.

If selector output includes non-empty `expired_in_progress_reset_paths`, stop
before claiming work, run `git diff --check`, stage only those reset task
files, create a scoped claim-expiry repair commit such as
`Expire stale backlog claims`, and rerun the same selector command. This keeps
abandoned claims from stopping the queue forever while preserving an auditable
repair commit.

If selector status is `select`, claim exactly `selected.path`. If status is
`no_ready`, stop without changing repository files and report the selector
summary, `ready_count`, `dependency_pending_count`, and first dependency-pending
examples, including any `in_progress` and `blocking_in_progress` diagnostics.
If status is `queue_error`, stop without claiming and report the diagnostics.

Never mark a task `blocked` merely because declared dependencies are not done;
dependency-pending tasks stay `backlog` and are skipped by the selector.

## Claim And Work

Before substantive work:

- update only the selected task file to `status: in-progress` in front matter
  and visible `Status: in-progress`;
- run `git diff --check`;
- stage only that task file;
- create a small claim checkpoint commit.

If the claim cannot be committed safely, stop and report the blocker.

After claim, read only the selected task body and required root/spec files.
Follow the selected task exactly, including allowed paths, denied paths,
expected outputs, and verification, except that a docs-only completion is not
valid for this implementer automation. If task instructions conflict with the
product-first contract by forbidding any code/test/configuration change, treat
that as a blocker for the selected scope rather than closing the task with
documentation alone. If behavior changes, update the relevant spec in the same
iteration before implementing or completing. If the worktree has uncommitted
changes that overlap the selected task, stop and report the blocker. Do not
promote another task into preparatory status unless the selected task is being
blocked specifically because it cannot produce product delta; in that case,
create or refine exactly one smallest implementation task that will.

Use OpenWhispr only as reference evidence. Do not port Electron, React, Node.js
runtime code, local model downloaders, meeting features, notes, accounts, cloud
sync, billing, telemetry, or updater behavior into the Swift app unless a
selected spec task explicitly changes MVP scope. Translate useful reference
behavior into specs or native Swift service boundaries before implementation.

Do not access MongoDB directly. Do not run destructive database or
object-storage operations. Do not edit sibling repositories unless the selected
task explicitly authorizes it.

Apply run hygiene: close run-owned browser sessions, app launches, simulators,
and dev servers before and after checks when ownership is clear; clean
current-run temporary screenshots, audits, profiles, and build artifacts before
staging; keep only durable reports or explicit evidence.

## Verification

Run the verification named by the selected task. For Swift behavior changes,
prefer the repository baseline unless the task narrows it:

```sh
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
git diff --check
```

For Swift test changes or test-covered behavior:

```sh
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
git diff --check
```

For docs/spec-only changes, at minimum run:

```sh
git diff --check
```

Docs/spec-only verification is sufficient only for a blocked or non-product
support update. It is not sufficient evidence to mark an implementer-selected
task `done`. A `done` task from this automation must include verification
matched to the product delta, such as Swift build/test, focused typecheck,
fake-backed tests, or bounded runtime smoke when relevant.

Use `docs/specs/features/platform-testing-strategy.md` to choose extra platform
checks. Use fake-backed tests for services and state machines. Do not call the
live OpenAI API from normal automation. Do not require real microphone input or
real system permission prompts for normal tests.

Use Computer Use only for bounded macOS runtime smoke when the selected task
changes visible app surfaces such as menu bar, Settings, floating indicator,
permission UI, or active-app paste handoff. Use XcodeBuildMCP / Build iOS Apps
for future iOS simulator build, test, screenshot, or UI snapshot checks when an
iOS target exists or the selected task changes shared iOS/macOS SwiftUI
surfaces.

If a platform smoke check cannot complete quickly, record the blocker and keep
the completed build/test evidence explicit instead of waiting indefinitely.

## Expected Output

Stage only files changed for this iteration and create a scoped completion
checkpoint commit.

Final report must include selector status, selected task id/title/path, claim
commit hash, completion commit hash if work completed, changed files,
verification results, platform smoke evidence or reason it was not required,
cleanup performed, remaining real blocker if any, next selector result if
checked, actual cwd, execution environment, selected task before/after status,
confirmation that the canonical checkout now contains the status update, and a
short `Product delta` field. `Product delta` must name the app behavior, Swift
code, tests, build/runtime capability, or bug fix delivered. If no product delta
was possible, the task must be reported as blocked, not done, and the report
must name the exact next implementation task created or updated.
