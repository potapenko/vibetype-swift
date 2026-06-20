---
id: VT-021
title: Settings Defaults Model
status: in-progress
priority: P1
lane: settings
parent: VT-020
dependencies:
  - VT-000
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-021-settings-defaults-model.md
---

# VT-021 - Settings Defaults Model

Status: in-progress

## Goal

Add a small Swift settings model with MVP defaults.

## Scope

- Represent model, language, auto-paste, copy, restore clipboard, sound, and
  floating indicator defaults.
- Keep API key storage out of this task.
- Use Swift-native persistence only if the existing app shape makes it trivial.

## Acceptance

- Defaults are explicit in one place.
- Settings can be read without a live UI.
- No secret value is stored in UserDefaults.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
