---
id: VT-131
title: History Settings Flag
status: backlog
priority: P2
lane: history
parent: VT-130
dependencies:
  - VT-021
allowed_paths:
  - vibetype/vibetype/Models/AppSettings.swift
  - vibetype/vibetypeTests/AppSettingsTests.swift
  - docs/specs/features/settings-and-secret-storage.md
  - backlog/vt-131-history-settings-flag.md
---

# VT-131 - History Settings Flag

Status: backlog

## Goal

Add the persisted `saveTranscriptHistory` setting that gates all future
history writes.

## Scope

- Add `saveTranscriptHistory` to `AppSettings` and `AppSettingsStore`.
- Default it to `false`.
- Persist it through the same non-secret settings path as other toggles.
- Add or update fake `UserDefaults` tests for default-off and save/load.

## Non-goals

- Do not add transcript history storage.
- Do not add a settings UI control.
- Do not write or clear history entries.

## Acceptance

- New installs load transcript history as disabled.
- Saving and loading settings preserves the flag.
- No API key, prompt text, transcript text, or history entry is stored by this
  setting task.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
