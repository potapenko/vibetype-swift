---
id: VT-042
title: Start Recording Temp File
status: backlog
priority: P1
lane: recording
parent: VT-040
dependencies:
  - VT-031
  - VT-041
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-042-start-recording-temp-file.md
---

# VT-042 - Start Recording Temp File

Status: backlog

## Goal

Implement the first real AVFoundation recording start path to a temporary audio
file.

## Scope

- Start recording only when microphone permission allows it.
- Write to a temporary local file.
- Avoid indefinite waits and avoid parallel recordings.

## Acceptance

- Starting recording creates or prepares a temp audio artifact path.
- Starting twice is rejected or ignored by contract.
- Failure state is surfaced without crashing.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
