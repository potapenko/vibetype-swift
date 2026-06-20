# Agent Onboarding

This is the short startup checklist for VibeType Swift work.

## First Read

For implementation or file-changing work, read in this order:

1. `AGENTS.md`
2. `BACKLOG_DEVELOPMENT.md`
3. `SWIFT.md` when Swift, SwiftUI, AppKit, Xcode, or tests are involved
4. `docs/specs/README.md`
5. `docs/specs/brownfield-discovery.md`
6. `docs/openwhispr_swiftui_codex_tz.md` for initial MVP behavior
7. the relevant feature spec under `docs/specs/features/`
8. `references/README.md` before using copied OpenWhispr source

## Normal Development Loop

1. Run `python3 scripts/backlog_next.py --json`.
2. Claim exactly the selected task with a claim checkpoint commit.
3. Read the selected task body.
4. Update specs before behavior changes.
5. Implement only the selected scope.
6. Run the task verification.
7. Mark the task done or blocked.
8. Create a scoped completion checkpoint commit.
9. Report verification, changed files, and the next selector result.

For platform verification, use
`docs/specs/features/platform-testing-strategy.md`. Most tasks should use
unit/build checks. Add bounded Computer Use smoke only for changed macOS runtime
surfaces, and use XcodeBuildMCP / Build iOS Apps for future iOS targets or
shared SwiftUI surfaces when the selected task requires it.

## Current Project Shape

The repository currently contains a minimal Xcode SwiftUI app template, not a
working dictation app. Treat `docs/openwhispr_swiftui_codex_tz.md` and
`docs/specs/` as behavior evidence, not completed behavior.

Use `references/openwhispr-main/` only as behavior reference material. The
Swift app remains native and should not inherit the Electron/React/Node
architecture.
