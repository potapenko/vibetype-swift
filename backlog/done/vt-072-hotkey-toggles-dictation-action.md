---
id: VT-072
title: Hotkey Toggles Dictation Action
status: done
priority: P2
lane: hotkey
parent: VT-070
dependencies:
  - VT-012
  - VT-071
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/**
  - backlog/vt-072-hotkey-toggles-dictation-action.md
---

# VT-072 - Hotkey Toggles Dictation Action

Status: done

## Goal

Wire the hotkey boundary to the same dictation action used by the menu.

## Scope

- Trigger start from idle.
- Trigger stop from recording.
- Guard against parallel recording or transcribing states.

## Acceptance

- Menu and hotkey share one action path.
- Repeated hotkey events do not create parallel work.
- Tests can simulate tap behavior through the fake service.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Completion Evidence

2026-06-22:

- Added `DictationHotkeyCoordinator` to subscribe to the hotkey boundary,
  derive start/stop commands from the active hotkey configuration, and invoke a
  single injected recording action path.
- Added fake-backed coordinator tests for key-down start, key-up stop,
  repeated key-down suppression, transcribing-state rejection, and in-flight
  action suppression.
- Verification passed:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`;
  `git diff --check`.
- Runtime QA was not applicable because this slice adds non-UI hotkey
  coordination logic and fake-backed tests, not real global registration or a
  visible macOS surface.
