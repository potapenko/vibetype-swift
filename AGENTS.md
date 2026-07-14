# AGENTS.md

This file defines workflow rules for agents working in this repository.

It is not the source of truth for detailed feature behavior. Detailed feature
behavior must live in `docs/specs/`.

## Repository Context

`holdtype-swift` is a native macOS menu bar dictation utility. The app records
microphone input, sends audio to OpenAI transcription, and inserts returned
text into the current active app.

The repository now contains real macOS implementation code, tests, specs, and
automation workflows. Treat `docs/openwhispr_swiftui_codex_tz.md` as fallback
source evidence for initial MVP behavior only when current specs do not settle
the behavior.

## Repository Safety

The user's global agent rules already define detailed database, object-storage,
preview, log, and timeout safety. This repository repeats only the local
non-negotiables:

- do not access MongoDB directly and never run destructive database operations;
- do not remove, move, overwrite, sync-delete, purge, or clean remote object
  storage;
- use bounded previews or dry runs yourself when validating an operator-only
  corrective workflow;
- keep product logs concise by default and put verbose payloads behind opt-in
  debug logging;
- put explicit timeouts on external services, media tools, uploads, downloads,
  and similar boundaries.

## Context Budget And Reading Order

Read the smallest file set that can safely answer the current request. Do not
read every spec, backlog task, runbook, reference checkout, or QA artifact "just
in case".

Baseline routing:

1. Always read this `AGENTS.md` before file changes.
2. Read `docs/agent-onboarding.md` for ordinary direct-chat implementation or
   investigation work.
3. Read `BACKLOG_DEVELOPMENT.md` only for explicit backlog work, scheduled
   backlog automation, backlog scripts/runbooks, or backlog file maintenance.
4. Read `SWIFT.md` only before Swift, SwiftUI, AppKit, Xcode project, or test
   changes.
5. Read `docs/specs/README.md` and `docs/specs/index.md` before product
   behavior changes, then read only the relevant feature spec.
6. Read `docs/specs/brownfield-discovery.md` when the current source ownership
   is unclear or the task needs a repo map.
7. Read `docs/openwhispr_swiftui_codex_tz.md` only when a behavior is still
   governed by the initial MVP brief and no current feature spec settles it.
8. Read `docs/specs/backlog.md` only when grooming or selecting product areas.
9. Read `references/README.md` only before using copied OpenWhispr source, then
   open exact reference files rather than scanning `references/`.

Before any iOS Simulator, iPhone Mirroring, or signed physical-device runtime
QA, agents must read and follow `iOS Simulator, Mirroring, And Physical Device
QA` in `docs/agent-tooling.md`. That section is the repository-wide authority
for tool setup, the Simulator/Mirroring/device evidence boundary, microphone
qualification, signing checks, and cleanup.

For backlog selection, prefer compact readback:

```sh
python3 scripts/backlog_next.py --compact-json
```

Use full `--json` only when compact output lacks diagnostics needed for the
current decision.

## Direct Chat Work Versus Backlog Work

Ordinary user requests in a live chat are direct tasks. If the user asks for a
feature, fix, refactor, or investigation without explicitly asking to create,
select, decompose, claim, or process backlog items, do the work directly in the
chat after the required reading, specs, implementation, verification, and
scoped checkpoint commit.

Do not create new backlog tasks, split the work into backlog files, or run the
selector merely because a task is non-trivial. Use normal chat planning first,
then implement once the user approves or the request is clearly an
implementation request.

Use backlog workflow only when one of these is true:

- the user explicitly asks to use, create, select, decompose, groom, archive, or
  execute backlog tasks;
- a scheduled automation, installed runbook, or worker prompt explicitly says
  it is a backlog worker;
- the current request is maintenance of backlog files themselves;
- the user and agent explicitly agree to make a long effort restartable through
  committed backlog tasks.

If a direct chat task later needs follow-up work, report the follow-up in the
chat. Create backlog files for that follow-up only when the user asks for
durable backlog tracking or the active automation/runbook requires it.

## Landing And Marketing Fast Lane

Landing-page and marketing work is a narrow, low-context workflow. This applies
to copy, static HTML/CSS, social metadata, images, campaign assets, and asset
organization under `website/`, `marketing/`, and `docs/marketing/`.

- Read only this `AGENTS.md` plus the exact landing or marketing files needed
  for the request. Do not load Swift architecture, app feature specs, package
  sources, app tests, backlog bodies, or unrelated repository history.
- Do not run Xcode builds, Swift or package tests, the full website test suite,
  browser QA, app runtime checks, deployment dry-runs, or repeated preflight
  checks unless the user explicitly requests that exact verification.
- Do not create or update product feature specs for copy-only, image-only,
  static-layout, metadata, or marketing-asset changes.
- Use only a quick check of the edited artifact itself when useful, such as
  confirming image dimensions, inspecting the resulting metadata, or running
  `git diff --check`.
- When the user says to publish, make the requested change, create the scoped
  checkpoint commit on `master`, and push it without adding repeated dry-run or
  monitoring loops. If a safe direct `master` push is impossible, follow the
  Master-Only Git Policy and ask the user instead of creating a workaround.

## Backlog Development

`BACKLOG_DEVELOPMENT.md` is the root development workflow for this repository.
It is the primary coordination model for explicit backlog work, scheduled
backlog automations, backlog grooming, and user-requested restartable task
queues. It is not required for ordinary direct chat tasks.

When operating in backlog mode, use the root Backlog Development workflow before
opening detailed task bodies. Agents may shallow-scan backlog task headers when
selecting work, but they must not read the body of a non-selected task. The
default selector readback is compact:

```sh
python3 scripts/backlog_next.py --compact-json
```

Use `python3 scripts/backlog_next.py --json` only for detailed queue
diagnostics after compact output proves insufficient.

For sequential automation, the canonical checkout is the source of truth. Use
the current repository state, not chat memory, to determine task status.

## Master-Only Git Policy

Agents must work only on the repository's existing `master` branch. Agents must
never create a Git branch under any circumstance. This prohibition applies to
local branches, remote branches, temporary branches, publish branches, task
branches, automation branches, and branches created through a worktree.

- Never run branch-creating or branch-switching workflows such as
  `git switch -c`, `git checkout -b`, `git branch <name>`, or
  `git worktree add -b`.
- Never switch away from `master`, push a non-`master` ref, or use a detached
  worktree as a substitute for direct `master` work.
- Commit and push task changes directly on `master`, while staging only the
  task-owned paths and preserving unrelated user changes.
- A dirty, ahead, behind, or diverged `master` is not permission to create an
  alternate branch. If a direct `master` commit or fast-forward push cannot be
  completed safely, stop and ask the user how to proceed.
- Never force-push `master` or rewrite its history to work around divergence.

## Dirty Git State Is Never A Blocker

Agents must never stop, skip, block, or report success-without-work merely
because `git status` is dirty. This includes conditions described as "GitHub
dirty", "dirty Git", dirty worktree, dirty checkout, unstaged changes, staged
changes, uncommitted changes, or overlapping local edits.

Dirty state is normal in this repository because multiple automation and manual
threads may touch the same checkout. The required behavior is:

- inspect the relevant diff;
- preserve existing changes;
- work against the current file contents;
- stage and commit only the current task's owned paths;
- use path-limited commands such as `git add <owned paths>` and
  `git commit --only <owned paths>` when unrelated changes exist.

Do not revert, reset, clean, stash, or include unrelated changes unless the
user explicitly asks for that exact Git operation. Do not introduce new
workflow, runbook, prompt, or automation rules that make dirty Git state a stop
condition.

## Checkpoint Commits

At the end of every task-solving chat that changes repository files, the agent
must create a checkpoint commit before the final response.

Checkpoint commits must stage and commit only the files changed for the current
task. Do not stage unrelated user changes or unrelated generated files. If the
worktree already contains unrelated changes, leave them untouched and mention
them in the final response.

If no repository files changed during the chat, report that no checkpoint
commit was needed.

Automation runs, separate worker chats, and bounded subtask executions count as
task-solving iterations. If they change repository files, they must finish by
updating any relevant plan/task status, running the appropriate verification,
staging only their own changes, and creating a scoped checkpoint commit before
reporting completion or handing work to the next run.

## Spec-First Rule

Before implementing any non-trivial feature:

1. Clarify the product goal.
2. Create or update a spec under `docs/specs/`.
3. Confirm user-visible behavior, invariants, and edge cases.
4. Only then begin implementation.

## When A Spec Is Required

Create or update a spec when a task:

- introduces a new feature
- changes observable behavior
- introduces or modifies route, state, persistence, permission, or data
  contracts
- affects multi-step user flows
- changes recording, transcription, status, editing, or text handoff behavior
- changes privacy, consent, microphone access, local storage, or remote-service
  use
- changes gating, permissions, or eligibility logic
- introduces behavior that could be misunderstood later

A new spec is usually not required for:

- pure refactors
- formatting-only changes
- comments-only edits
- behavior-neutral internal cleanup

## Separation Of Concerns

- `AGENTS.md` defines workflow and agent rules.
- `docs/specs/` defines product behavior.
- tests or QA artifacts define verification and evidence.

Do not merge these layers into one file.

## Swift Implementation Rule

Implement against the spec, not against ad hoc chat memory. If behavior changes,
update the spec in the same task.

For Swift or Apple-platform code, specs must settle user-visible behavior before
implementation details such as SwiftUI/AppKit/UIKit structure, speech framework
choice, accessibility permissions, clipboard behavior, persistence, or remote
transcription provider are treated as fixed.

All Swift implementation must follow `SWIFT.md`. If a task needs to violate
`SWIFT.md` for platform or integration reasons, document the reason in the code
review or final response and prefer a small, isolated exception.

## Verification Rule

If a task changes behavior, update or add appropriate verification artifacts.
Verification may be unit tests, integration tests, UI tests, manual app-run
evidence, or another project-appropriate artifact.

Before every UI test, Computer Use session, or automated runtime QA pass on
macOS, agents must start a scoped `caffeinate` process (for example,
`caffeinate -dimsu`) before the first interface action. Keep it running for the
entire UI session so system idle timers cannot sleep or lock the Mac, then stop
that process when the UI session finishes. Do not begin UI automation without
this guard.

Agents must perform every interface action that is available through Computer
Use or another approved automation surface themselves. Do not ask the operator
to click buttons, navigate menus, dismiss prompts, or enter ordinary values on
the agent's behalf. Request operator action only when the required physical or
authentication gesture is genuinely unavailable to automation, and continue
all independent work instead of stopping while that action is pending.

For UI tests, Computer Use, and automated runtime QA, HoldType must launch with
live Keychain access disabled. Use the UI-test launch helper or
`script/build_and_run.sh --verify`, which launches the app with a sanitized
environment; do not raw-launch the app for automation when Keychain behavior is
not the task. Agents must not enter the macOS login keychain password or click
`Always Allow` during automated testing.

`script/build_and_run.sh --live-debug` is manual live-provider tooling only. Do
not use it for automated verification, scheduled runs, UI tests, or Computer
Use smoke unless the user explicitly asks for a live OpenAI debug session.

For microphone, transcription, permissions, or external-service behavior, tests
must avoid indefinite waits and must use bounded timeouts or controllable fakes.

iOS runtime evidence must keep the three lanes separate: Simulator proves the
actual extension and simulated host interaction; iPhone Mirroring may operate
and observe only the containing app; a signed physical iPhone proves real
microphone ownership, recording lifecycle, and device signing. One lane must
never be reported as proof for another.

For Swift behavior changes, the baseline verification is:

```sh
xcodebuild -project HoldType.xcodeproj -scheme HoldType -destination 'platform=macOS' build
git diff --check
```

Run the matching `xcodebuild ... test` command when tests or test-covered
behavior change. For docs/spec-only changes, `git diff --check` is usually
enough unless the edited docs change executable commands that should be
exercised.

## Writing Style For Specs

Specs should be:

- short
- explicit
- product-level
- behavior-oriented

Avoid deep implementation detail unless it is necessary to preserve the product
contract.

## OpenWhispr Reference Use

The copied OpenWhispr source under `references/openwhispr-main/` is reference
evidence only. Use it to understand behavior around hotkeys, recording,
permissions, paste handoff, settings, and edge cases.

Do not port Electron, React, Node.js runtime, local model downloaders, meeting
features, notes, accounts, cloud sync, billing, telemetry, or updater behavior
into this Swift app unless a future spec explicitly changes the MVP scope.
