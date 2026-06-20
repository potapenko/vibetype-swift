# VibeType Swift

Native macOS Swift project for a small menu bar dictation utility.

The MVP goal is to record microphone input, send audio to the OpenAI
transcription API, and insert the returned text into the current active app.
The app should avoid accounts, subscriptions, server-side state, telemetry,
Electron, React, and Node.js.

This repository is currently set up for spec-first development. Product
behavior should be specified before implementation code is added.

## Start Here

Before implementing a non-trivial feature:

1. Read `AGENTS.md`.
2. Read `docs/specs/README.md`.
3. Read or create the relevant feature spec in `docs/specs/features/`.
4. Implement only after the product behavior is explicit.

## Current Spec Layer

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

## Prompt Pack

Reusable prompts live under `prompts/`. Use
`prompts/day-to-day-spec-first.md` for normal feature work after this bootstrap.
