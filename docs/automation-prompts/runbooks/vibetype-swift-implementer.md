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

If selector status is `select`, claim exactly `selected.path`. If status is
`no_ready`, stop without changing repository files and report the selector
summary, `ready_count`, `dependency_pending_count`, and first dependency-pending
examples. If status is `queue_error`, stop without claiming and report the
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

If the claim cannot be committed safely, stop and report the blocker.

After claim, read only the selected task body and required root/spec files.
Follow the selected task exactly, including allowed paths, denied paths,
expected outputs, and verification. If behavior changes, update the relevant
spec in the same iteration before implementing or completing. If the worktree
has uncommitted changes that overlap the selected task, stop and report the
blocker. Do not promote another task into preparatory status.

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
and confirmation that the canonical checkout now contains the status update.
