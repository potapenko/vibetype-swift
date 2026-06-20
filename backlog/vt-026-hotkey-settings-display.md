---
id: VT-026
title: Hotkey Settings Display
status: backlog
priority: P2
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-071
  - VT-073
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/global-hotkey.md
  - backlog/vt-026-hotkey-settings-display.md
---

# VT-026 - Hotkey Settings Display

Status: backlog

## Goal

Show the active dictation shortcut and activation mode in the native Settings
window.

## Scope

- Add a read-only Settings row for the active global hotkey.
- Show the activation mode as hold-to-record or toggle according to the
  product decision.
- Surface fallback or unavailable registration status when the hotkey service
  exposes it.

## Non-goals

- Do not add hotkey editing, capture UI, validation UI, or multiple hotkey
  slots.
- Do not add voice-agent, meeting, chat-agent, or platform-specific Linux
  hotkey setup.
- Do not implement actual hotkey registration in this task.

## Acceptance

- Settings displays the shortcut and activation mode using product language.
- If no global hotkey is active, Settings shows that manual menu recording is
  still available.
- No unsupported OpenWhispr hotkey slots or editing controls appear.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
