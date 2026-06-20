---
id: VT-142
title: iOS Keyboard Visual Reference Note
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-141
allowed_paths:
  - docs/qa/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - backlog/vt-142-ios-keyboard-visual-reference-note.md
verification:
  - git diff --check
---

# VT-142 - iOS Keyboard Visual Reference Note

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-141
Expected outputs: compact visual/design note, verification result
Verification: git diff --check

## Goal

Create a durable design note for the iOS keyboard reference before building UI.

## Scope

- Summarize the relevant reference screens without copying brand assets:
  keyboard idle/start, listening, accept/cancel, and settings handoff.
- Define VibeType-specific visual principles for the keyboard: compact dark
  chrome, visible next-keyboard control, clear microphone action, low text
  density, and reachable settings.
- Record which parts are inspiration only and which become VibeType product
  requirements.

## Non-goals

- Do not implement SwiftUI.
- Do not add image assets copied from Wispr Flow or 9to5Mac.
- Do not change macOS visual design.

## Acceptance

- A short note under `docs/qa/` or the relevant spec captures visual states and
  design constraints for the keyboard.
- The note cites the external reference URL and the user-provided screenshot as
  reference evidence, not as source assets.

## Notes

- Keep the note concise enough for an implementation agent to use without
  revisiting the chat.
