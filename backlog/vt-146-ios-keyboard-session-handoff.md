---
id: VT-146
title: iOS Keyboard Session Handoff
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-143
  - VT-144
  - VT-145
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - docs/qa/**
  - backlog/vt-146-ios-keyboard-session-handoff.md
verification:
  - git diff --check
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' build
---

# VT-146 - iOS Keyboard Session Handoff

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-143, VT-144, VT-145
Expected outputs: bounded keyboard-to-containing-app handoff prototype
Verification: git diff --check; iOS simulator build/smoke or documented blocker

## Goal

Prototype the safe handoff between the keyboard extension and containing app
for starting or resuming a voice session.

## Scope

- Define the app-open or deep-link path from keyboard UI into the containing
  app.
- Keep the session bounded and explicit; no hidden background recording.
- Return the keyboard to a clear unavailable, waiting, or active-session state
  when the user comes back to the host text field.
- Use fake session state if real recording/transcription services are not
  implemented yet.

## Non-goals

- Do not implement live OpenAI transcription.
- Do not store API keys or transcript text in the keyboard extension.
- Do not require Open Access until a later shared-state task explicitly defines
  it.

## Acceptance

- Keyboard UI can request a containing-app session handoff without crashing.
- The handoff path has a bounded simulator smoke plan or blocker note.
- Product copy explains when the user is leaving the keyboard for setup or
  session activation.

## Notes

- This task tests the same product pattern described in the Wispr Flow
  reference: start from keyboard, activate in app when needed, continue from
  keyboard state.
