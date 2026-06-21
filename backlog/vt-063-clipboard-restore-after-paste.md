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
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-063-clipboard-restore-after-paste.md
---

# VT-063 - Clipboard Restore After Paste

Status: backlog

## Goal

Restore the previous clipboard after auto-paste when the setting is enabled.

## Scope

- Restore only from the app-created clipboard snapshot.
- Restore only after a paste event reports success.
- Use a short bounded delay after paste; the first Swift adapter may start near
  the spec's 400-500ms restore window.
- Keep non-text clipboard restore behavior conservative; MVP restore is
  plain-text oriented unless a later task explicitly expands it.
- Do not restore after copy-only fallback or failed paste, because the
  transcript should remain available for manual paste.

## Acceptance

- Restore can be enabled or disabled.
- Copy-only mode still leaves transcript on clipboard.
- Failed paste still leaves transcript on clipboard.
- Restore failures do not crash the app.

## Source Evidence

- OpenWhispr's `clipboard.js` snapshots the previous clipboard before writing
  the transcript, restores only after a successful paste, and leaves fallback
  text available when auto-paste cannot complete.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
