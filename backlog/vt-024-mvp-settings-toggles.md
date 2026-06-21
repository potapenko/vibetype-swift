---
id: VT-024
title: MVP Settings Toggles
status: in-progress
priority: P2
lane: settings
parent: VT-020
dependencies:
  - VT-013
  - VT-021
allowed_paths:
  - vibetype/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-024-mvp-settings-toggles.md
---

# VT-024 - MVP Settings Toggles

Status: in-progress

## Goal

Expose the core MVP settings toggles in the native settings UI.

## Scope

- Add controls for auto-paste, copy to clipboard, restore clipboard, sound, and
  floating indicator.
- Bind controls to the settings model.
- Keep advanced OpenWhispr settings out of this task.

## Acceptance

- Each MVP toggle has a native control.
- Values survive app relaunch if persistence exists.
- UI does not include unsupported advanced settings.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
