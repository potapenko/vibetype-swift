---
id: VT-073
title: Hold To Record Activation Mode Slice
status: backlog
priority: P3
lane: hotkey
parent: VT-070
dependencies:
  - VT-002
allowed_paths:
  - vibetype/vibetype/Services/GlobalHotkeyService.swift
  - vibetype/vibetypeTests/GlobalHotkeyServiceTests.swift
  - docs/specs/features/**
  - backlog/vt-073-hold-to-record-decision-slice.md
---

# VT-073 - Hold To Record Activation Mode Slice

Status: backlog

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

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
