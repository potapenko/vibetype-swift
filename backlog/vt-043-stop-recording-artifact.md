---
id: VT-043
title: Stop Recording Artifact
status: in-progress
priority: P1
lane: recording
parent: VT-040
dependencies:
  - VT-042
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-043-stop-recording-artifact.md
---

# VT-043 - Stop Recording Artifact

Status: in-progress

## Goal

Implement stop recording behavior that returns a bounded audio artifact for
transcription.

## Scope

- Stop active recording.
- Return file URL, duration, and basic size metadata if available.
- Surface empty or too-short recordings as a controlled result.

## Acceptance

- Stop only succeeds when recording is active.
- The returned artifact is suitable for the transcription service.
- Empty recordings are not sent to OpenAI.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
