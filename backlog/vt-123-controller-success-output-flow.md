---
id: VT-123
title: Controller Success Output Flow
status: backlog
priority: P2
lane: controller
parent: VT-120
dependencies:
  - VT-054
  - VT-062
  - VT-064
  - VT-121
allowed_paths:
  - vibetype/vibetype/**
  - vibetype/vibetypeTests/**
  - docs/specs/features/openai-transcription.md
  - docs/specs/features/text-output-workflow.md
  - backlog/vt-123-controller-success-output-flow.md
---

# VT-123 - Controller Success Output Flow

Status: backlog

## Goal

Connect a successful transcription result to last transcript state and the
configured output workflow.

## Scope

- Accept only normalized, non-empty transcript text.
- Store accepted text as the current last transcript.
- Send accepted text to the output boundary according to settings.
- Keep live OpenAI, real clipboard, and real paste events out of tests.

## Acceptance

- A fake successful transcription updates the last transcript.
- Empty or whitespace-only output does not run copy or paste handoff.
- Output handoff failure leaves the transcript visible or recoverable.

## Source Evidence

- OpenWhispr trims transcription text, updates transcript state, and then
  performs paste-or-copy handoff in
  `references/openwhispr-main/src/hooks/useAudioRecording.js`.
- Accessibility can fall back to copy-only behavior per
  `references/openwhispr-main/src/utils/permissions.ts`.

## Verification

- `xcodebuild -project vibetype/vibetype.xcodeproj -scheme vibetype -destination 'platform=macOS' test`
- `git diff --check`
