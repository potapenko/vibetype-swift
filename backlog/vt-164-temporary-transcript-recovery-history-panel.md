---
id: VT-164
title: Temporary Transcript Recovery History Panel
status: backlog
priority: P1
lane: history
parent: VT-130
dependencies:
  - VT-123
  - VT-131
  - VT-133
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/transcript-history.md
  - docs/specs/features/settings-and-secret-storage.md
  - docs/specs/features/text-output-workflow.md
  - docs/specs/features/menu-bar-app-shell.md
  - docs/specs/features/privacy-and-permissions.md
  - backlog/vt-130-transcript-history-umbrella.md
  - backlog/vt-164-temporary-transcript-recovery-history-panel.md
verification:
  - xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test
  - git diff --check
---

# VT-164 - Temporary Transcript Recovery History Panel

Status: backlog
Priority: P1
Lane: history
Dependencies: VT-123, VT-131, VT-133
Expected outputs: updated specs, session recovery history state, native history panel, menu/settings entry points, focused tests
Verification: `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`; `git diff --check`

## Goal

Add a privacy-first transcript recovery history surface so users can recover a
recent successful dictation when automatic insertion into the active app fails
or the target input changes.

## Scope

- Update transcript history specs from persistent-first history to
  session-only recovery history for this MVP slice.
- Keep at most the 20 most recent accepted, non-empty transcripts.
- Add accepted transcripts after transcription succeeds and before output
  handoff can discard recoverability.
- Add a native Transcript History window opened from the menu bar.
- Add row actions to save a history row into the VibeType Clipboard and insert
  a history row through the existing active-app insertion boundary.
- Add a Clear History action and clear recovery history on app termination.
- Add Settings copy/control that makes the privacy behavior clear.
- Add focused tests for disabled history, append, retention, clear, and output
  failure recovery.

## Non-goals

- Do not add raw audio retention, retry-from-audio, failed-session history, or
  discarded recording recovery.
- Do not add cloud sync, accounts, semantic notes, search, tags, folders, or
  OpenWhispr Electron/React architecture.
- Do not use the macOS system clipboard as history storage.
- Do not make durable disk-backed transcript persistence part of this slice.

## Acceptance

- History is off by default unless the updated spec explicitly keeps it as
  session-only and privacy-safe.
- When enabled, accepted non-empty transcripts appear newest-first in the
  history panel.
- History keeps no more than 20 entries.
- Failed active-app insertion does not remove the accepted transcript from
  recovery history.
- Clear History removes current recovery entries without deleting settings,
  Keychain secrets, audio cleanup state, or Last Transcript.
- Quitting the app clears current recovery entries.
- Default logs do not include transcript text.
