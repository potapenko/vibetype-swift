# VibeType Swift

Native macOS Swift project for a small menu bar dictation utility.

The MVP goal is to record microphone input, send audio to the OpenAI
transcription API, and insert the returned text into the current active app.
The app should avoid accounts, subscriptions, server-side state, telemetry,
Electron, React, and Node.js.

This repository is currently set up for spec-first development. Product
behavior should be specified before implementation code is added.

## Start Here

Before selecting or implementing a non-trivial task:

1. Read `AGENTS.md`.
2. Read `BACKLOG_DEVELOPMENT.md`.
3. Run `python3 scripts/backlog_next.py --json` when selecting backlog work.
4. Read `SWIFT.md` before Swift, SwiftUI, AppKit, Xcode, or test changes.
5. Read `docs/specs/README.md`.
6. Read or create the relevant feature spec in `docs/specs/features/`.
7. Implement only after the product behavior is explicit.

File-changing task-solving chats should end with a scoped checkpoint commit.

## Current Spec Layer

- `BACKLOG_DEVELOPMENT.md` - selector-driven backlog workflow and checkpoint
  commit contract
- `SWIFT.md` - Swift, SwiftUI, AppKit interop, and Xcode engineering rules
- `backlog/` - executable backlog tasks selected by `scripts/backlog_next.py`
- `docs/agent-onboarding.md` - short agent startup checklist
- `docs/specs/brownfield-discovery.md` - current implementation snapshot
- `docs/specs/backlog.md` - first spec backlog and open decisions
- `docs/openwhispr_swiftui_codex_tz.md` - original product brief used as
  bootstrap evidence
- `docs/specs/features/menu-bar-app-shell.md` - first-pass menu bar and app
  state behavior
- `docs/specs/features/microphone-text-input.md` - first-pass capture and
  transcription flow
- `docs/specs/features/privacy-and-permissions.md` - first-pass consent,
  microphone, and data handling rules
- `docs/specs/features/settings-and-secret-storage.md` - first-pass settings
  and Keychain behavior
- `docs/specs/features/text-output-workflow.md` - first-pass auto-paste and
  clipboard handoff behavior
- `docs/specs/templates/feature-spec.md` - reusable feature spec template

## Reference Material

- `references/openwhispr-main/` - copied OpenWhispr source used only as
  behavior evidence for the native Swift rewrite
- `references/README.md` - rules for using the copied reference without
  importing Electron/React/Node architecture

## Prompt Pack

Reusable prompts live under `prompts/`. Use
`prompts/day-to-day-spec-first.md` for normal feature work after this bootstrap.
