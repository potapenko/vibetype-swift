# Agent Onboarding

This is the short startup checklist for VibeType Swift work.

## First Read

For implementation or file-changing work, read in this order:

1. `AGENTS.md`
2. `BACKLOG_DEVELOPMENT.md`
3. `SWIFT.md` when Swift, SwiftUI, AppKit, Xcode, or tests are involved
4. `docs/agent-tooling.md` when Xcode, simulator, MCP, runtime QA, or
   tool-selection decisions are involved
5. `docs/specs/README.md`
6. `docs/specs/brownfield-discovery.md`
7. `docs/openwhispr_swiftui_codex_tz.md` for initial MVP behavior
8. the relevant feature spec under `docs/specs/features/`
9. `references/README.md` before using copied OpenWhispr source

## Normal Development Loop

1. Run `python3 scripts/backlog_archive_done.py --apply --json` when doing
   scheduled or maintenance work, then commit any moved completed task files
   before claiming new implementation work.
2. Run `python3 scripts/backlog_next.py --json`; this standard selector run
   expires stale `in-progress` claims by default.
3. If `expired_in_progress_reset_paths` is non-empty, run `git diff --check`,
   stage only those reset task files, create a scoped repair commit, and rerun
   the selector before claiming work.
4. Claim exactly the selected task with a claim checkpoint commit.
5. Read the selected task body.
6. Update specs before behavior changes.
7. Implement only the selected scope.
8. Run the task verification.
9. Mark the task done or blocked.
10. Create a scoped completion checkpoint commit.
11. Report verification, changed files, and the next selector result.

For platform verification, use
`docs/specs/features/platform-testing-strategy.md`. Most tasks should use
unit/build checks. The current target is the macOS menu bar MVP: use Build
macOS Apps or macOS-capable XcodeBuildMCP when available for macOS build,
run/test, screenshot, or UI snapshot evidence, and add bounded Computer Use
smoke only for changed macOS runtime surfaces that the MCP surface cannot
operate directly. Build iOS Apps and iOS simulator checks are v2-only unless a
direct user request or future-version task explicitly opts into deferred iOS
lanes.
Use `docs/agent-tooling.md` to choose between active MCP tools, normal
`xcodebuild`, and Computer Use for a selected task.

## Current Project Shape

The repository currently contains a minimal Xcode SwiftUI app template, not a
working dictation app. Treat `docs/openwhispr_swiftui_codex_tz.md` and
`docs/specs/` as behavior evidence, not completed behavior.

Use `references/openwhispr-main/` only as behavior reference material. The
Swift app remains native and should not inherit the Electron/React/Node
architecture.
