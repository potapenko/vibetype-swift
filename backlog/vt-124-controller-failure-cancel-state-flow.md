---
id: VT-124
title: Controller Failure Cancel State Flow
status: backlog
priority: P2
lane: controller
parent: VT-120
dependencies:
  - VT-044
  - VT-053
  - VT-121
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - docs/specs/features/openai-transcription.md
  - backlog/vt-124-controller-failure-cancel-state-flow.md
---

# VT-124 - Controller Failure Cancel State Flow

Status: backlog

## Goal

Make controller cancellation and failure states recoverable without losing the
previous accepted transcript.

## Scope

- Cancel active recording before transcription begins.
- Map recorder or transcription failures into visible app state.
- Preserve the previous successful transcript after failure or cancellation.
- Use fakes instead of live microphone, network, or output side effects.

## Acceptance

- Cancel stops the active fake recording and does not start transcription.
- A failed recording or transcription ends in a visible failure state.
- Previous successful transcript text is not overwritten by failure or cancel.

## Source Evidence

- OpenWhispr exposes cancel recording and cancel processing paths in
  `references/openwhispr-main/src/hooks/useAudioRecording.js`.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
