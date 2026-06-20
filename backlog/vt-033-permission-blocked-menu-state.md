---
id: VT-033
title: Permission Blocked Menu State
status: backlog
priority: P1
lane: permissions
parent: VT-030
dependencies:
  - VT-012
  - VT-031
  - VT-032
allowed_paths:
  - vibetype/vibetype/**
  - docs/specs/features/menu-bar-app-shell.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-033-permission-blocked-menu-state.md
---

# VT-033 - Permission Blocked Menu State

Status: backlog

## Goal

Reflect missing microphone or accessibility permissions in the menu bar UI.

## Scope

- Disable or redirect dictation actions when microphone permission is blocked.
- Keep copy-only behavior available when accessibility is missing.
- Do not add recording or paste implementation.

## Acceptance

- Missing microphone permission blocks recording.
- Missing accessibility permission does not block transcription itself.
- The menu exposes a clear next action.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' build`
- `git diff --check`
