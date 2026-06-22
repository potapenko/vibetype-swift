---
id: VT-045
title: Recording Timeout Guard
status: done
priority: P2
lane: recording
parent: VT-040
dependencies:
  - VT-042
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - backlog/vt-045-recording-timeout-guard.md
---

# VT-045 - Recording Timeout Guard

Status: done

## Goal

Add a maximum recording duration guard so microphone capture cannot wait
forever.

## Scope

- Use a configurable or constant MVP timeout.
- Stop or fail the current recording when the timeout is exceeded.
- Use a controllable clock or fake in tests where practical.

## Acceptance

- Recording has a bounded maximum duration.
- Timeout state is visible to the app state model.
- Tests do not sleep for the full production timeout.

## Implementation Notes

- The AVFoundation recorder starts capture with a five-minute MVP duration
  limit.
- Artifacts at or beyond the maximum duration fail with a user-visible
  maximum-length message and are not handed to transcription or output.
- Fake-backed recorder and controller tests cover the timeout path without
  waiting for the production duration.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`

## Verification Result

- Passed: `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- Passed: `git diff --check`
