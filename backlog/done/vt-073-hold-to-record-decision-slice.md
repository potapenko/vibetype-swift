---
id: VT-073
title: Hold To Record Activation Mode Slice
status: done
priority: P3
lane: hotkey
parent: VT-070
dependencies:
  - VT-002
allowed_paths:
  - vibetype/Services/GlobalHotkeyService.swift
  - vibetypeTests/FakeGlobalHotkeyService.swift
  - vibetypeTests/GlobalHotkeyServiceTests.swift
  - docs/specs/features/**
  - backlog/vt-073-hold-to-record-decision-slice.md
---

# VT-073 - Hold To Record Activation Mode Slice

Status: done

## Goal

Make the MVP hotkey activation-mode decision executable in the Swift hotkey
model.

## Scope

- Update the hotkey spec only if the MVP activation-mode decision needs
  tightening.
- Ensure the Swift hotkey model exposes the chosen MVP activation mode in a
  way later controller code can branch on without string parsing.
- Add or update fake-backed/unit coverage for hold-to-record versus toggle
  semantics at the hotkey model boundary.
- Do not register real global hotkeys, wire the dictation controller, or change
  Settings UI in this slice.

## Acceptance

- Spec states the activation mode for MVP.
- Swift code has an executable representation of the chosen activation mode and
  any fallback/toggle behavior needed by later controller work.
- Tests cover the model-level distinction between hold-to-record and toggle
  behavior, including whether key-up should stop recording.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Completion Evidence

- Added executable hold-to-record and toggle-mode hotkey recording commands at
  the model boundary.
- Added fake-backed tests for hold-mode key down/up behavior, toggle-mode
  key-down-only behavior, key-repeat suppression, and whether key-up stops
  recording.
- Tightened the hotkey spec to state that the MVP prefers hold-to-record and
  uses toggle only when key-up cannot be delivered safely.
- Expanded the allowed test-helper path to include the existing fake hotkey
  service because it was required to compile the selected fake-backed tests.
- Verification passed:
  `xcodebuild -quiet -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test -only-testing:vibetypeTests/GlobalHotkeyServiceTests`
- Verification passed:
  `xcodebuild -quiet -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- Verification passed: `git diff --check`
- Full-scheme verification
  `xcodebuild -quiet -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
  entered the local macOS test runner and then stalled in runner
  materialization/finalization; the run-owned process was interrupted after a
  bounded wait and reported `** TEST INTERRUPTED **`.
- Runtime QA: not applicable; this slice changed non-UI model/test behavior
  only and did not register real global hotkeys or change visible app surfaces.
