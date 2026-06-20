---
id: VT-122
title: Controller Start Stop Recording Flow
status: backlog
priority: P2
lane: controller
parent: VT-120
dependencies:
  - VT-043
  - VT-121
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - docs/specs/features/menu-bar-app-shell.md
  - backlog/vt-122-controller-start-stop-recording-flow.md
---

# VT-122 - Controller Start Stop Recording Flow

Status: backlog

## Goal

Wire the controller's start and stop actions through the recording boundary.

## Scope

- Start recording only from idle.
- Stop only an active recording and move to transcribing when an artifact is
  returned.
- Ignore repeated start or stop actions that would create parallel work.
- Use fake-backed tests for state transitions.

## Acceptance

- Start from idle enters recording.
- Stop from recording produces the next transcribing-ready state.
- Repeated start while recording and start while transcribing are no-ops or
  visible blocked states, not parallel recordings.

## Source Evidence

- OpenWhispr uses start and stop locks to prevent overlapping recording work in
  `references/openwhispr-main/src/hooks/useAudioRecording.js`.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
