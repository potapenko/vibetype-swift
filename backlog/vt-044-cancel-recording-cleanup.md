---
id: VT-044
title: Cancel Recording Cleanup
status: backlog
priority: P2
lane: recording
parent: VT-040
dependencies:
  - VT-042
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-044-cancel-recording-cleanup.md
---

# VT-044 - Cancel Recording Cleanup

Status: backlog

## Goal

Add cancel behavior that stops recording and removes the current temporary
artifact when safe.

## Scope

- Cancel active recording.
- Clean up only the current app-created temporary artifact.
- Do not send canceled audio to transcription.

## Acceptance

- Cancel returns the app to idle or a controlled error state.
- No transcription starts after cancel.
- Cleanup is limited to the current recording artifact.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
