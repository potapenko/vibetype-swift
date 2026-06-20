---
id: VT-140
title: iOS Voice Keyboard Umbrella
status: backlog
priority: P3
lane: ios-keyboard
dependencies:
  - VT-141
  - VT-142
  - VT-143
  - VT-144
  - VT-145
  - VT-146
  - VT-147
allowed_paths:
  - backlog/**
  - docs/specs/features/ios-keyboard-feasibility.md
  - docs/specs/features/platform-testing-strategy.md
  - docs/qa/**
  - vibetype/**
verification:
  - git diff --check
---

# VT-140 - iOS Voice Keyboard Umbrella

Status: backlog
Priority: P3
Lane: ios-keyboard
Dependencies: VT-141, VT-142, VT-143, VT-144, VT-145, VT-146, VT-147
Expected outputs: child task completion review, follow-up backlog updates if needed
Verification: git diff --check

## Goal

Track the iOS voice-keyboard direction as a dependency-gated product area.

## Scope

- Keep the voice keyboard work split into small spec, design, target, state,
  handoff, and settings slices.
- Close out the umbrella only after child tasks establish a coherent MVP path.

## Non-goals

- Do not implement the keyboard extension in this parent task.
- Do not change macOS menu bar behavior from this parent task.

## Acceptance

- Child tasks are either done or explicitly blocked with a resolution path.
- The final review records the next implementation or design task, if any.

## Notes

- Reference direction: Wispr Flow-style keyboard with a compact dark keyboard
  chrome, start/listening/confirm/settings states, and containing-app handoff.
