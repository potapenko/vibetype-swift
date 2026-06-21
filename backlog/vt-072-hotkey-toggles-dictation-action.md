---
id: VT-072
title: Hotkey Toggles Dictation Action
status: backlog
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

Status: backlog

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
