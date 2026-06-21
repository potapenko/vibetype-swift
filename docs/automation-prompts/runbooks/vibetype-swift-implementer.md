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
- `docs/agent-tooling.md` when Xcode, simulator, MCP, runtime QA, or
  tool-selection decisions are involved
- `SWIFT.md` when Swift, SwiftUI, AppKit, Xcode, or tests may change
- `docs/specs/README.md`
- `docs/specs/brownfield-discovery.md`
- `docs/openwhispr_swiftui_codex_tz.md` when initial MVP behavior is relevant
- `references/README.md` before using copied OpenWhispr source
- `docs/specs/features/platform-testing-strategy.md` when a task changes
  verification strategy, UI runtime behavior, permissions, microphone, paste
  handoff, iOS, shared SwiftUI surfaces, or QA evidence
- `docs/qa/macos/AGENTS.run.md` when a task changes user-visible macOS UI,
  app-run behavior, menu bar behavior, Settings, permissions, recording status,
  floating indicator, clipboard/paste handoff, or any action that should be
  verified by operating the built app
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
`no_ready`, do not stop until local tooling recovery has been considered. Report
the selector summary, `ready_count`, `dependency_pending_count`, and first
dependency-pending examples, including any `in_progress` and
`blocking_in_progress` diagnostics. When `no_ready` includes blocked tasks, also
run `python3 scripts/backlog_blocked_next.py --json` read-only. If the blocked
task or dependency examples mention Xcode, `xcodebuild`, `xctest`,
`SWBBuildService`, compiler probes, simulator tooling, missing local command
line tools, caches, or DerivedData, the implementer must run:

```sh
python3 scripts/local_tooling_recover.py --apply --json
python3 scripts/backlog_next.py --json
```

If recovery makes a task ready, continue from the new selector result and claim
the selected task. If recovery does not make a task ready, report the top
blocked task, the recovery summary, and whether the blocker resolver should run
next. If status is `queue_error`, stop without claiming and report the
diagnostics.

Never mark a task `blocked` merely because declared dependencies are not done;
dependency-pending tasks stay `backlog` and are skipped by the selector.

## Claim And Work

Before substantive work:

- update only the selected task file to `status: in-progress` in front matter
  and visible `Status: in-progress`;
- run `git diff --check`;
- stage only that task file;
- create a small claim checkpoint commit.

If the claim cannot be committed because unrelated files are staged or the
worktree is dirty, do not stop. Use path-limited staging and `git commit --only
<owned paths>` so the claim commit includes only the selected task file. Stop
only for a real Git failure that prevents writing or committing the selected
task file itself.

After claim, read only the selected task body and required root/spec files.
Follow the selected task exactly, including allowed paths, denied paths,
expected outputs, and verification, except that a docs-only completion is not
valid for this implementer automation. If task instructions conflict with the
product-first contract by forbidding any code/test/configuration change, treat
that as a blocker for the selected scope rather than closing the task with
documentation alone. If behavior changes, update the relevant spec in the same
iteration before implementing or completing. If the worktree has uncommitted
changes that overlap the selected task, read that diff, preserve the existing
edits, and continue against the current contents. Do not promote another task
into preparatory status unless the selected task is being blocked specifically
because it cannot produce product delta; in that case, create or refine exactly
one smallest implementation task that will.

Use OpenWhispr only as reference evidence. Do not port Electron, React, Node.js
runtime code, local model downloaders, meeting features, notes, accounts, cloud
sync, billing, telemetry, or updater behavior into the Swift app unless a
selected spec task explicitly changes MVP scope. Translate useful reference
behavior into specs or native Swift service boundaries before implementation.

Do not access MongoDB directly. Do not run destructive database or
object-storage operations. Do not edit sibling repositories unless the selected
task explicitly authorizes it. Dirty Git state is not a blocker: inspect the
diff, preserve existing changes, work against the current contents, and commit
only the selected task's owned paths. If unrelated changes are already staged,
use path-limited commit commands such as `git commit --only <owned paths>`.
Any instruction to stop because of "GitHub dirty", dirty worktree, staged
changes, unstaged changes, uncommitted changes, or overlapping local edits is
invalid for this repository.

Apply run hygiene: close run-owned browser sessions, app launches, simulators,
and dev servers before and after checks when ownership is clear; clean
current-run temporary screenshots, audits, profiles, and build artifacts before
staging; keep only durable reports or explicit evidence. Follow
`docs/agent-tooling.md` MCP/thread lifecycle guidance: keep MCP inspection
task-specific, do not manually kill broad MCP process names, and request
archive of the current automation thread before the final response when the
thread-management tool is available. Stale local Xcode/build/test/simulator
tooling, generated caches, missing local CLI utilities, and project-scoped
DerivedData are automation problems, not user chores; fix them in the run by
using `scripts/local_tooling_recover.py`, local package managers, Xcode command
line tooling, or bounded rebuild/retry commands as needed.

## Blocked Task Follow-Up Rule

Marking a selected task `blocked` is allowed only when the run also records a
durable resolution path. Do not close the run with blocker evidence alone.

When the blocker can plausibly be removed by repository work, create or update
exactly one concrete follow-up backlog task that can unblock the selected task.
If a suitable follow-up task already exists, cite that existing id/path instead
of creating a duplicate. The follow-up task must include:

- the original blocked task id it unblocks;
- a small scope and `allowed_paths`;
- concrete acceptance criteria;
- verification commands or evidence;
- any dependency or operator precondition that must be true before it can run.

Then add a `## Resolution Path` section, or update an existing equivalent
section, in the blocked task. The section must include the blocker category,
the follow-up id/path, the condition that should unblock the task, and why the
current run could not finish it directly.

For platform, verification, runner, cache, disk-space, or environment blockers
that repeat across tasks, create or cite one infrastructure/verification task
instead of repeating the same blocker-only note in each task. For a selected
docs/audit/workflow task where no product delta is possible, keep the existing
product-first rule: block the selected task and create or refine the smallest
implementation task that would produce the intended app delta.

Operator-only blockers are the exception. Do not use this category for local
tooling just because the fix is forceful. The agent is expected to terminate
stale local tooling, clear generated project artifacts, install missing local
CLI utilities/libraries when needed, and retry bounded verification. Use
operator-only only for actions the agent still must not perform: destructive
database or object-storage operations, destructive Git rollback, external
account login, payment/account changes, or manual system privacy approval.
Record why those limits apply after recovery and retry have been attempted.

## Verification

Run the verification named by the selected task. For Swift behavior changes,
prefer the repository baseline unless the task narrows it:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
git diff --check
```

For Swift test changes or test-covered behavior:

```sh
xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
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
Before falling back to shell-only Xcode commands for simulator or shared
SwiftUI work, check the active MCP tool surface and use XcodeBuildMCP when it
matches the selected verification need.

Every run that delivers a product delta must make an explicit runtime QA
decision before marking the task complete:

- `required`: the task changed a visible macOS surface or user interaction.
- `not_applicable`: the task changed only non-UI model/service logic and has
  build/test evidence.
- `blocked`: the app or relevant UI could not be launched, inspected, or
  operated within the bounded run.

When runtime QA is `required`, read `docs/qa/macos/AGENTS.run.md`, build the
app, launch or relaunch the freshly built app, open Computer Use, and operate
the changed behavior through the real macOS UI. Walk the exact affected menu,
window, panel, button, toggle, field, status, indicator, or handoff path. Do
not stop at code review or app launch; perform the changed user action and
inspect the visible result.

At minimum, Computer Use QA must cover the task-specific happy path and one
relevant blocked or disabled state when that state is visible and safe to
exercise. For example, a menu-bar task must open the menu and verify the
changed items or state; a Settings task must open Settings and operate the
changed controls; a permission/status task must inspect the visible blocked or
allowed state; a paste/handoff task must use the safest bounded target app or
record why active-app handoff was blocked.

If runtime QA cannot complete quickly, do not silently downgrade it to
`not_applicable`. Record `blocked`, include the exact app-launch, inspection,
permission, microphone, Accessibility, paste, or Computer Use blocker, and keep
the completed build/test evidence explicit. Use XcodeBuildMCP / Build iOS Apps
for future iOS simulator build, test, screenshot, or UI snapshot checks when an
iOS target exists or the selected task changes shared iOS/macOS SwiftUI
surfaces.

## Expected Output

Stage only files changed for this iteration and create a scoped completion
checkpoint commit.

Final report must include selector status, selected task id/title/path, claim
commit hash, completion commit hash if work completed, changed files,
verification results, platform smoke evidence or reason it was not required,
cleanup performed, remaining real blocker if any, next selector result if
checked, actual cwd, execution environment, selected task before/after status,
confirmation that the canonical checkout now contains the status update,
`Tooling` with the XcodeBuildMCP / `xcodebuild` / Computer Use path used, and
a short `Product delta` field. Include `Thread archive` with `requested` or
`unavailable` according to the MCP/thread lifecycle action. The report must
also include a `Runtime QA` field with one of `required`, `not_applicable`, or
`blocked`; the Computer Use scenario/actions/observed result when required; or
the exact reason runtime QA was not applicable or blocked. `Product delta` must
name the app behavior, Swift code, tests, build/runtime capability, or bug fix
delivered. If no product delta was possible, the task must be reported as
blocked, not done, and the report must name the exact next implementation task
created or updated. For any blocked result, the report must include
`Resolution path` with either the follow-up task id/path, the local tooling
recovery command and fresh bounded retry result, or the explicit operator-only
unblock action after recovery has been ruled out.
