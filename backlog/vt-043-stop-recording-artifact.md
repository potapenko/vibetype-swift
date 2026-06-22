---
id: VT-043
title: Stop Recording Artifact
status: done
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

Status: done

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

## Completion Evidence

2026-06-22:

- Added `AudioRecordingArtifact` as the stop result for completed recording
  files, including file URL, duration, and byte-count metadata.
- Updated the AVFoundation recorder stop path to reject missing, empty, and
  too-short completed files with controlled recording errors before any
  transcription upload can consume them.
- Updated fake recorder/test coverage for successful artifact metadata,
  missing completed file, empty completed file, and too-short completed file
  behavior.
- Updated the microphone text-input spec to make completed recording artifact
  metadata and invalid-artifact rejection part of the product contract.
- Verification passed:
  `/opt/homebrew/bin/timeout 300 xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`;
  `git diff --check`.
- Runtime QA was not applicable because this slice changes non-UI recorder
  service behavior covered by fake-backed tests and full scheme test evidence.
