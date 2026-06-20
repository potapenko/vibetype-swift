---
kind: automation-runbook
automationLayer: per-user-automation-registry
automationRole: vibetype-swift-backlog-groomer
status: active
---

# VibeType Swift Backlog Groomer Runbook

This runbook is the versioned runtime contract for the current user's
`vibetype-swift-backlog-groomer` installed Codex automation.

Configured automation cwd:
`/Users/eugenepotapenko/Projects/potapenko-github/vibetype-swift`

## Runtime Contract

Run one bounded backlog grooming pass for the VibeType Swift repository.
Translate the MVP brief, current Swift project state, existing specs, and the
copied OpenWhispr reference source into small executable backlog tasks for the
separate implementer automation. Do not implement Swift product code.

Use the configured canonical checkout as the source of truth. Before edits,
confirm the actual cwd is the configured repository root and execution
environment is `local`. If running from an isolated worktree whose commit will
not advance the canonical checkout, stop and report a blocker.

Required reading before edits:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-onboarding.md`
- `SWIFT.md`
- `docs/specs/README.md`
- `docs/specs/backlog.md`
- `docs/specs/features/backlog-grooming-automation.md`
- `docs/openwhispr_swiftui_codex_tz.md`
- `references/README.md`
- only OpenWhispr reference files relevant to the behavior being groomed

Inspect current Swift source shape with `rg` or `rg --files` before creating
tasks.

## Safety

Run `git status --short` before writing. If there are uncommitted changes or
staged changes, stop without editing and report the blocker.

Before grooming, run the standard selector. It has built-in claim-expiry repair:

```sh
python3 scripts/backlog_next.py --json
```

If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
stage only those reset task files, create a scoped repair commit such as
`Expire stale backlog claims`, and rerun the same selector command before
continuing. If non-expired `in_progress` entries remain, stop without grooming
and report the active claim diagnostics.

Do not modify sibling repositories. Do not access MongoDB directly. Do not run
destructive database or object-storage operations.

## Backlog Rules

Existing backlog files and the selector are authoritative for ids,
dependencies, priorities, and ready work:

```sh
python3 scripts/backlog_next.py --json
```

Do not mark tasks done. Do not claim tasks. Do not change implementer-owned
source files. Do not delete tasks. Do not duplicate tasks that already cover the
behavior.

Create or refine at most eight backlog tasks per run. Prefer umbrella parent
tasks plus small child tasks when a product area is larger than one checkpoint.
Child tasks should usually have one observable output and be close to a
10-minute agent slice: one menu item, one state model, one service protocol,
one permission mapping, one settings field, one fake-backed test, or one spec
decision.

Keep each task narrow, with `allowed_paths`, dependencies, acceptance criteria,
and verification commands.

## Reference Translation

OpenWhispr is behavior evidence only. Translate reference scenarios into native
Swift, SwiftUI, AppKit, AVFoundation, URLSession, Keychain, NSPasteboard,
accessibility, or CGEvent tasks.

Never add Electron, React, Node.js runtime, Tauri, Rust runtime, local model
downloads, cloud sync, accounts, billing, updater, or telemetry work unless a
selected spec explicitly changes MVP scope.

Preserve the first-iteration bias that the earliest implementation task creates
a visible native menu bar item before deeper recording, transcription,
settings, permissions, or paste work.

## Verification

After edits, run:

```sh
python3 scripts/backlog_next.py --json
git diff --check
```

Stage only backlog/spec/workflow files changed by this groomer run and create a
scoped checkpoint commit such as `backlog: groom Swift MVP tasks`. Do not stage
source-code implementation files or unrelated changes.

## Expected Output

Final report must include created or updated task ids, parent/child grouping
changes, reference files inspected, selector status and selected task path,
verification results, commit hash if created, actual cwd, execution
environment, and any blocker.
