---
id: VT-042
title: Start Recording Temp File
status: done
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

Status: done

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

## Completion Evidence

2026-06-22:

- Added `AVFoundationAudioRecorderService`, backed by `AVAudioRecorder`, that
  checks microphone permission before preparing a unique temporary `.m4a`
  capture path.
- Repeated starts are rejected with `alreadyRecording` while preserving the
  active recording state; start failures surface typed errors and delete the
  prepared recorder artifact.
- Updated the microphone text-input spec to make permission-gated temporary
  audio artifacts part of the recording-start contract.
- Verification passed:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`;
  `git diff --check`.
- Runtime QA was not applicable because this slice adds non-UI recorder service
  behavior covered by fake-backed tests and full scheme test evidence.
