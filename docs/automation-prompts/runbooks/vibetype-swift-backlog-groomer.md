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
When grooming platform or shared SwiftUI tasks, use `docs/agent-tooling.md` so
new tasks name the appropriate XcodeBuildMCP, `xcodebuild`, Computer Use, or
fallback evidence path.

Use the configured canonical checkout as the source of truth. Before edits,
confirm the actual cwd is the configured repository root and execution
environment is `local`. If running from an isolated worktree whose commit will
not advance the canonical checkout, stop and report a blocker.

Required reading before edits:

- `AGENTS.md`
- `BACKLOG_DEVELOPMENT.md`
- `docs/agent-onboarding.md`
- `docs/agent-tooling.md`
- `SWIFT.md`
- `docs/specs/README.md`
- `docs/specs/backlog.md`
- `docs/specs/features/backlog-grooming-automation.md`
- `docs/specs/features/ui-functionality-coverage.md`
- `docs/openwhispr_swiftui_codex_tz.md`
- `references/README.md`
- only OpenWhispr reference files relevant to the behavior being groomed

Inspect current Swift source shape with `rg` or `rg --files` before creating
tasks.

## Safety

Run `git status --short` before writing. Dirty Git state is not a blocker. If
there are staged or unstaged changes, inspect the relevant diff, preserve those
changes, and continue against the current checkout. Stage and commit only
groomer-owned backlog/spec/workflow paths. If unrelated changes are already
staged, use path-limited commit commands such as `git commit --only <owned
paths>` so the unrelated index does not block grooming.

Before grooming, run the standard selector. It has built-in claim-expiry repair:

```sh
python3 scripts/local_tooling_recover.py --apply --json
python3 scripts/backlog_next.py --json
```

Local Xcode/build/test/simulator tooling failures, stale compiler probes,
generated caches, project-scoped DerivedData, and missing local CLI utilities
are automation problems. The groomer must recover them automatically before
reporting a tooling blocker. Do not ask the user to clear local tooling state.

If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
stage only those reset task files, create a scoped repair commit such as
`Expire stale backlog claims`, and rerun the same selector command before
continuing. If non-expired `in_progress` entries remain, stop without grooming
and report the active claim diagnostics.

Do not modify sibling repositories. Do not access MongoDB directly. Do not run
destructive database or object-storage operations.

Apply run hygiene: keep MCP inspection task-specific, do not manually kill
broad MCP process names unless the process is clearly run-owned, and follow the
hard final resource cleanup and MCP/thread lifecycle guidance in
`docs/agent-tooling.md` by terminating or closing every resource the run
started, reporting any residual resource that cannot be terminated, and
requesting archive of the current automation thread before the final response
when the thread-management tool is available. Clean only current-run temporary
artifacts that are not durable evidence. For stale local Xcode/build/test
tooling, use `scripts/local_tooling_recover.py` rather than stopping for user
cleanup.

## Backlog Rules

Existing backlog files and the selector are authoritative for ids,
dependencies, priorities, and ready work:

```sh
python3 scripts/backlog_next.py --json
```

Do not mark tasks done. Do not claim tasks. Do not change implementer-owned
source files. Do not delete tasks. Do not duplicate tasks that already cover the
behavior.

When saying existing tasks cover reference behavior, verify the coverage against
`docs/specs/features/ui-functionality-coverage.md` and the selector output.
A blocked or dependency-pending task is not enough by itself. Record the first
unblock action or create/refine one small executable task instead of treating a
blocked area as complete coverage.

Create or refine at most eight backlog tasks per run. Prefer umbrella parent
tasks plus small child tasks when a product area is larger than one checkpoint.
Child tasks should usually have one observable output and be close to a
10-minute agent slice: one menu item, one state model, one service protocol,
one permission mapping, one settings field, one fake-backed test, or one spec
decision.

Keep each task narrow, with `allowed_paths`, dependencies, acceptance criteria,
and verification commands.

Update `docs/specs/features/ui-functionality-coverage.md` in the same run when
new or refined tasks change the current state, next task, reference evidence, or
verification plan for a visible surface or end-to-end product flow.

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
source-code implementation files or unrelated changes. Dirty unrelated files
must be preserved, not treated as a reason to stop.

## Expected Output

Final report must include created or updated task ids, parent/child grouping
changes, reference files inspected, selector status and selected task path,
verification results, local tooling recovery summary, tooling assumptions added
to tasks when relevant, commit hash if created, actual cwd, execution
environment, cleanup performed with terminated resources and any residual
resources with reasons, `Thread archive` with `requested` or `unavailable`
according to the MCP/thread lifecycle action, UI/functionality coverage rows
updated or explicitly unchanged, unrelated dirty files preserved, and any
blocker.
