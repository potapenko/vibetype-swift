---
id: VT-144
title: iOS Keyboard Session State Model
status: in-progress
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-113
allowed_paths:
  - vibetype/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - backlog/vt-144-ios-keyboard-session-state-model.md
verification:
  - git diff --check
  - xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' test
---

# VT-144 - iOS Keyboard Session State Model

Status: in-progress
Priority: P3
Lane: ios-keyboard
Dependencies: VT-113
Expected outputs: keyboard session state model and fake-backed tests
Verification: git diff --check; iOS test or documented blocker

## Goal

Create a deterministic state model for the keyboard voice-session UI before
building the visual surface.

## Scope

- Model keyboard states for setup needed, idle/start, launching session,
  listening, confirming, transcribing, accepted transcript, error, and compact
  settings.
- Keep transitions pure and fake-backed so tests do not depend on microphone,
  provider network, host app text input, or simulator UI.
- Include decisions for cancel, accept, open containing app, and open inline
  settings.

## Non-goals

- Do not call OpenAI.
- Do not capture microphone audio.
- Do not insert text into a host app.
- Do not build the final keyboard layout.

## Acceptance

- State transitions are represented by small Swift types.
- Tests cover start, cancel, accept, error, settings entry, and unavailable
  paths using fakes.
- No default logs include dictated text.

## Notes

- This model should be reusable by the containing app preview surface and the
  keyboard extension where practical.
- This task is the implementation follow-up for blocked VT-141. It should turn
  the intended keyboard-visible product contract into executable Swift state
  and tests before additional iOS keyboard UI tasks depend on it.
