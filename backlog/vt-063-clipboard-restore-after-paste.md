---
id: VT-063
title: Clipboard Restore After Paste
status: backlog
priority: P2
lane: text-output
parent: VT-060
dependencies:
  - VT-061
  - VT-062
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-063-clipboard-restore-after-paste.md
---

# VT-063 - Clipboard Restore After Paste

Status: backlog

## Goal

Restore the previous clipboard after auto-paste when the setting is enabled.

## Scope

- Restore only from the app-created clipboard snapshot.
- Use a short bounded delay after paste.
- Keep non-text clipboard restore behavior conservative.

## Acceptance

- Restore can be enabled or disabled.
- Copy-only mode still leaves transcript on clipboard.
- Restore failures do not crash the app.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
