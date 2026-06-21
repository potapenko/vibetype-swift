---
id: VT-121
title: Controller Service Boundary
status: backlog
priority: P2
lane: controller
parent: VT-120
dependencies:
  - VT-011
  - VT-041
  - VT-052
  - VT-062
allowed_paths:
  - vibetype/**
  - vibetypeTests/**
  - docs/specs/features/microphone-text-input.md
  - docs/specs/features/openai-transcription.md
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-121-controller-service-boundary.md
---

# VT-121 - Controller Service Boundary

Status: backlog

## Goal

Introduce the Swift-native dictation session controller boundary with injected
recording, transcription, settings, and output dependencies.

## Scope

- Add the smallest controller type or protocol needed for menu and hotkey
  actions to share one dictation path.
- Use injected services or fakes; do not call the microphone, OpenAI, Keychain,
  pasteboard, or CGEvent directly from the controller.
- Keep the first slice focused on ownership and dependency shape.

## Acceptance

- Menu and future hotkey code can target one controller action boundary.
- The boundary can be exercised with fakes in tests.
- Controller setup does not introduce live external calls or permission prompts.

## Source Evidence

- OpenWhispr guards start and stop work behind one recording hook in
  `references/openwhispr-main/src/hooks/useAudioRecording.js`.

## Verification

- `xcodebuild -project vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
