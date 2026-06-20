---
id: VT-145
title: iOS Keyboard Visual State Surface
status: backlog
priority: P3
lane: ios-keyboard
parent: VT-140
dependencies:
  - VT-142
  - VT-143
  - VT-144
allowed_paths:
  - vibetype/**
  - docs/qa/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - backlog/vt-145-ios-keyboard-visual-state-surface.md
verification:
  - git diff --check
  - xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype-iOS -destination 'platform=iOS Simulator' build
---

# VT-145 - iOS Keyboard Visual State Surface

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-142, VT-143, VT-144
Expected outputs: keyboard SwiftUI visual states, simulator evidence or blocker
Verification: git diff --check; iOS simulator build/screenshot or documented blocker

## Goal

Build the first keyboard UI surface for the Wispr Flow-inspired voice states.

## Scope

- Implement compact keyboard UI for idle/start, listening, accept/cancel, and
  setup/settings handoff states.
- Keep the next-keyboard control visible and reachable.
- Use VibeType branding and product language, not copied Wispr Flow assets or
  text.
- Add previews or fake-backed fixtures for each state.
- Capture simulator screenshot evidence when the target can run.

## Non-goals

- Do not implement live recording, live transcription, or host-app insertion.
- Do not implement full settings persistence in this task.
- Do not change macOS Settings layout except for shared components if the task
  explicitly needs them.

## Acceptance

- The keyboard extension can render all declared visual states from fake state.
- Text fits within the keyboard-height constraints on iPhone simulator.
- Runtime QA is either screenshot-backed or blocked with the exact simulator
  build/run blocker.

## Notes

- The visual direction is dark, compact, and keyboard-native, with large
  obvious start/listen/accept/cancel controls.
