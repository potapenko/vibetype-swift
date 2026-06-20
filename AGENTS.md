# AGENTS.md

This file defines workflow rules for agents working in this repository.

It is not the source of truth for detailed feature behavior. Detailed feature
behavior must live in `docs/specs/`.

## Repository Context

`vibetype-swift` is a new Swift project for a small native macOS menu bar
dictation utility. The app records microphone input, sends audio to the OpenAI
transcription API, and inserts returned text into the current active app.

At bootstrap time this repository has no implementation code, but it does have
a product brief in `docs/openwhispr_swiftui_codex_tz.md`. Treat that brief as
source evidence for the initial MVP, then preserve durable product behavior in
`docs/specs/`.

If implementation code exists, do brownfield discovery before changing
behavior.

## Database Safety

The agent must not access MongoDB directly during a session. This includes REPL
queries, ad hoc query helpers, `mongosh`, and manual DB scripts.

The agent must never run any destructive database operation. This includes
delete, remove, drop, cleanup, purge, and any utility that may remove documents
or collections.

The agent may write code that works with data through normal application flows,
but only under the configured non-destructive runtime.

All destructive database operations are operator-only. Only the user may run
cleanup or deletion utilities.

## Storage Safety

The agent must never run destructive object-storage operations. This includes
`aws s3 rm`, `aws s3 mv` between remote paths, `aws s3 sync --delete`,
`aws s3api delete-objects`, cleanup utilities, purge utilities, and any script
that may remove or overwrite Wasabi/S3 objects.

The agent may inspect storage, list objects, read manifests or reports, and
prepare exact console commands for the user.

All destructive Wasabi/S3 operations are operator-only. Only the user may run
deletion, purge, cleanup, or move commands that remove or replace existing
remote objects.

## Preview And Dry-Run Responsibility

Long preview, dry-run, report, or planning modes are the agent's validation
tools, not operator chores.

When a destructive or corrective workflow offers a preview/report mode, the
agent should use it to verify assumptions on a narrow, bounded sample such as
one explicit package, one artifact, or another safely limited scope before
preparing an operator command.

Do not ask the user to run a broad multi-hour preview just to validate the
agent's hypothesis. If the user is expected to run an operator-only apply step,
provide the shortest verified command path, plus status/stop/log commands.
Offer a broad preview only when the user explicitly asks for an audit report or
manual review before apply.

## Log Readability

Log readability is as important as code readability. Treat logs as an
operator-facing interface, not as a dump of internal state.

Product logs must stay short, scannable, and useful in a live console. Prefer a
brief action plus a compact artifact identifier. Put verbose tracing, payloads,
timings, and internal context behind opt-in debug logging instead of the default
product log stream.

When investigating a problem, enable local debug logging, test the failing path,
and turn it back off after verification.

## External Timeout Discipline

Do not let external operations wait forever. Calls to remote services, object
storage, uploads, downloads, media tools, and similar boundaries must have an
explicit maximum wait time.

If an external stage exceeds its timeout, fail the current attempt with an
exception instead of waiting indefinitely. Let the next service cycle or retry
pick the work up again from the current state.

When retrying, prefer reusing already-produced artifacts or already-completed
remote steps instead of recreating the whole chain from scratch. If a later
stage already succeeded, skip it and continue from the next missing or failed
step.

## Reading Order

Before doing implementation work:

1. Read this `AGENTS.md`.
2. Read `BACKLOG_DEVELOPMENT.md` for file-changing development, backlog work,
   or automation setup.
3. Read `docs/agent-onboarding.md`.
4. Read `SWIFT.md` before Swift, SwiftUI, AppKit, Xcode, or test changes.
5. Read `docs/specs/README.md`.
6. Read `docs/specs/brownfield-discovery.md`.
7. Read `docs/openwhispr_swiftui_codex_tz.md` when working on initial MVP
   behavior.
8. Read the relevant feature spec in `docs/specs/features/` if one exists.
9. Read `docs/specs/backlog.md` when selecting the next product area.
10. Read `references/README.md` before using copied OpenWhispr source as
    reference evidence.
11. Only then implement or modify behavior.

## Backlog Development

`BACKLOG_DEVELOPMENT.md` is the root development workflow for this repository.
It is the primary coordination model for Swift app, specs, docs, reference
audit, verification, and automation work.

Use the root Backlog Development workflow before opening detailed task bodies.
Agents may shallow-scan backlog task headers when selecting work, but they must
not read the body of a non-selected task. The selector command is:

```sh
python3 scripts/backlog_next.py --json
```

For sequential automation, the canonical checkout is the source of truth. Use
the current repository state, not chat memory, to determine task status.

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

For microphone, transcription, permissions, or external-service behavior, tests
must avoid indefinite waits and must use bounded timeouts or controllable fakes.

For Swift behavior changes, the baseline verification is:

```sh
xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build
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
